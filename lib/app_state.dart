import 'package:flutter/foundation.dart';

import 'db/app_db.dart';
import 'db/templates.dart';
import 'models.dart';
import 'services/drive_sync.dart';
import 'services/notifications.dart';
import 'theme/skins.dart';
import 'util/ids.dart';

/// מצב גלובלי קל: היומנים, היומן הנוכחי, סוגי אירועים, תרופות, הגדרות.
/// אפשר כמה יומנים במקביל (D-22); המסכים מציגים את היומן הנוכחי,
/// והתזכורות פועלות לכל היומנים.
/// כל שינוי בנתונים: כתיבה למסד, עדכון תזכורות, בקשת סנכרון, רענון מסכים.
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  final db = AppDb.instance;
  final sync = DriveSync.instance;

  /// כל היומנים.
  List<Subject> subjects = [];

  /// היומן המוצג כרגע.
  Subject? subject;

  /// סוגים ותרופות של כל היומנים (לתזכורות) ושל היומן הנוכחי (למסכים).
  List<EventType> allTypes = [];
  List<Med> allMeds = [];
  List<EventType> types = [];
  List<Med> meds = [];
  int dayStartHour = 7;

  /// סקין ופונט. נפרד מ-notifyListeners כדי שתיעוד אירוע לא יבנה מחדש את כל האפליקציה.
  final appearance = ValueNotifier<Appearance>(Appearance.initial);

  Map<String, EventType> get typeById => {for (final t in allTypes) t.id: t};
  Map<String, Med> get medById => {for (final m in allMeds) m.id: m};
  List<EventType> get visibleTypes => types.where((t) => !t.hidden).toList();
  bool get isSetUp => subject != null;
  String get subjectId => subject?.id ?? 'none';
  bool get hasManyJournals => subjects.length > 1;

  /// היומן הראשון: אליו שייכים נתונים ישנים בלי subject_id.
  String? get _firstId {
    if (subjects.isEmpty) return null;
    final ids = subjects.map((s) => s.id).toList()..sort();
    return ids.first;
  }

  /// לאיזה יומן שייך פריט עם subject_id (null = היומן הראשון).
  String? ownerOf(String? subjectId) => subjectId ?? _firstId;

  Subject? subjectById(String? id) {
    final key = ownerOf(id);
    for (final s in subjects) {
      if (s.id == key) return s;
    }
    return null;
  }

  EventType? get medType {
    for (final t in types) {
      if (t.isMed) return t;
    }
    return null;
  }

  Future<void> load() async {
    subjects = await db.subjects();
    final wanted = await db.getSetting('current_subject');
    subject = subjects.isEmpty
        ? null
        : subjects.firstWhere(
            (s) => s.id == wanted,
            orElse: () => subjects.first,
          );
    allTypes = await db.eventTypes();
    allMeds = await db.meds();
    final cur = subject?.id;
    types = allTypes.where((t) => ownerOf(t.subjectId) == cur).toList();
    meds = allMeds.where((m) => ownerOf(m.subjectId) == cur).toList();
    Notifications.journalPrefix = {
      if (hasManyJournals)
        for (final s in subjects) s.id: '${s.name} · ',
    };
    Notifications.firstJournalId = _firstId;
    dayStartHour = await db.dayStartHour;
    appearance.value = Appearance(
      Skin.byKey(await db.getSetting('skin')),
      AppFont.byKey(await db.getSetting('font')),
    );
    notifyListeners();
  }

  Future<void> setSkin(Skin skin) async {
    await db.setSetting('skin', skin.key);
    appearance.value = Appearance(skin, appearance.value.font);
  }

  Future<void> setFont(AppFont font) async {
    await db.setSetting('font', font.key);
    appearance.value = Appearance(appearance.value.skin, font);
  }

  /// שינוי מקומי: רענון מסכים + סנכרון בעוד כמה שניות.
  void _changed() {
    notifyListeners();
    sync.requestSync();
  }

  /// אחרי מיזוג מהדרייב: טעינה מחדש ותזמון מחדש של כל התזכורות.
  Future<void> onRemoteChanges() async {
    await load();
    await rescheduleEverything();
  }

  Future<void> rescheduleEverything() async {
    for (final t in allTypes) {
      await _afterEventChange(t.id);
    }
    await Notifications.instance.rescheduleAll();
  }

  // ---------- מבנה (סוגים, שדות, תרופות, נושא) ----------

  /// אחרי שינוי מבנה (סוג הוסתר, מרווח תזכורת שונה, תרופה הופסקה):
  /// טעינה מחדש ותזמון מחדש, כדי שתזכורת ישנה לא תמשיך לצלצל.
  Future<void> reloadStructure() async {
    await load();
    await rescheduleEverything();
    sync.requestSync();
  }

  Future<void> saveSubject(Subject s) async {
    await db.saveSubject(s);
    await reloadStructure();
  }

  // ---------- יומנים מרובים ----------

  Future<void> switchJournal(String id) async {
    await db.setSetting('current_subject', id);
    await load();
  }

  Future<Subject> createJournal(
    Template tpl, {
    String? name,
    DateTime? startDate,
  }) async {
    final s = await db.createFromTemplate(
      tpl,
      name: name,
      startDate: startDate,
    );
    await db.setSetting('current_subject', s.id);
    await reloadStructure();
    return s;
  }

  /// מחיקת יומן (רק אם יש עוד יומן). הנתונים מסומנים כמחוקים והתזכורות מבוטלות.
  Future<void> deleteJournal(Subject s) async {
    if (subjects.length < 2) return;
    final n = Notifications.instance;
    for (final t in allTypes.where((t) => ownerOf(t.subjectId) == s.id)) {
      await n.cancel(Notifications.typeId(t.id));
      await db.softDelete('event_types', t.id);
    }
    for (final m in allMeds.where((m) => ownerOf(m.subjectId) == s.id)) {
      await n.cancel(Notifications.medId(m.id));
      await db.softDelete('meds', m.id);
    }
    for (final a in await db.appointments(subjectId: s.id)) {
      await n.cancelAppointment(a);
      await db.softDelete('appointments', a.id);
    }
    for (final f in await db.openFollowUps(subjectId: s.id)) {
      await n.cancelFollowUp(f);
      await db.softDelete('follow_ups', f.id);
    }
    await db.deleteSubject(s.id);
    if (subject?.id == s.id) await db.setSetting('current_subject', null);
    await reloadStructure();
  }

  /// מעבר ליומן של פריט (לפני פתיחת מסך מהתראה של יומן אחר).
  Future<void> showJournalOf(String? itemSubjectId) async {
    final owner = ownerOf(itemSubjectId);
    if (owner != null && owner != subject?.id) await switchJournal(owner);
  }

  /// משימות מעקב פתוחות של היומן הנוכחי.
  Future<List<FollowUp>> openFollowUpsHere() => db.openFollowUps(
    subjectId: subjectId,
    includeUnassigned: subjectId == _firstId,
  );

  // ---------- אירועים ----------

  /// אירוע חדש. היומן נקבע לפי הסוג (גם כשנרשם מהתראה של יומן אחר).
  LogEvent newEvent(String typeId, {Map<String, dynamic>? values}) => LogEvent(
    id: newId(),
    subjectId: ownerOf(typeById[typeId]?.subjectId) ?? subjectId,
    typeId: typeId,
    timestamp: DateTime.now(),
    values: values,
  );

  Future<void> saveEvent(LogEvent e) async {
    await db.saveEvent(e);
    await _afterEventChange(e.typeId);
    _changed();
  }

  Future<void> deleteEvent(LogEvent e) async {
    await db.deleteEvent(e.id);
    await _afterEventChange(e.typeId);
    _changed();
  }

  Future<void> undoDelete(LogEvent e) async {
    await db.restoreEvent(e.id);
    await _afterEventChange(e.typeId);
    _changed();
  }

  Future<void> _afterEventChange(String typeId) async {
    final t = typeById[typeId];
    if (t == null) return;
    if (t.isMed) {
      for (final m in allMeds.where(
        (m) => ownerOf(m.subjectId) == ownerOf(t.subjectId),
      )) {
        final lastMed = m.active ? await db.lastMedEvent(m.id) : null;
        if (lastMed != null) {
          await Notifications.instance.scheduleMedReminder(
            m,
            lastMed.timestamp,
          );
        } else {
          await Notifications.instance.cancel(Notifications.medId(m.id));
        }
      }
      return;
    }
    final last = t.hidden ? null : await db.lastEventOfType(typeId);
    if (last != null) {
      await Notifications.instance.scheduleTypeReminder(t, last.timestamp);
    } else {
      await Notifications.instance.cancel(Notifications.typeId(t.id));
    }
  }

  // ---------- תורים ומעקב ----------

  Future<void> saveAppointment(Appointment a) async {
    await db.saveAppointment(a);
    await Notifications.instance.scheduleAppointment(a);
    _changed();
  }

  Future<void> deleteAppointment(Appointment a) async {
    await Notifications.instance.cancelAppointment(a);
    await db.deleteAppointment(a.id);
    _changed();
  }

  Future<void> addFollowUp(FollowUp f) async {
    await db.saveFollowUp(f);
    await Notifications.instance.scheduleFollowUp(f);
    _changed();
  }

  Future<void> completeFollowUp(FollowUp f) async {
    f.doneAt = DateTime.now();
    await db.saveFollowUp(f);
    await Notifications.instance.cancelFollowUp(f);
    _changed();
  }

  Future<void> deleteFollowUp(FollowUp f) async {
    await Notifications.instance.cancelFollowUp(f);
    await db.deleteFollowUp(f.id);
    _changed();
  }
}

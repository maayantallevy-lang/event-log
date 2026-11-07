import 'package:flutter/foundation.dart';

import 'db/app_db.dart';
import 'models.dart';
import 'services/drive_sync.dart';
import 'services/notifications.dart';
import 'theme/skins.dart';
import 'util/ids.dart';

/// מצב גלובלי קל: נושא היומן, סוגי אירועים, תרופות, הגדרות.
/// כל שינוי בנתונים: כתיבה למסד, עדכון תזכורות, בקשת סנכרון, רענון מסכים.
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  final db = AppDb.instance;
  final sync = DriveSync.instance;

  List<EventType> types = [];
  List<Med> meds = [];
  Subject? subject;
  int dayStartHour = 7;

  /// סקין ופונט. נפרד מ-notifyListeners כדי שתיעוד אירוע לא יבנה מחדש את כל האפליקציה.
  final appearance = ValueNotifier<Appearance>(Appearance.initial);

  Map<String, EventType> get typeById => {for (final t in types) t.id: t};
  Map<String, Med> get medById => {for (final m in meds) m.id: m};
  List<EventType> get visibleTypes => types.where((t) => !t.hidden).toList();
  bool get isSetUp => subject != null;
  String get subjectId => subject?.id ?? 'none';

  EventType? get medType {
    for (final t in types) {
      if (t.isMed) return t;
    }
    return null;
  }

  Future<void> load() async {
    types = await db.eventTypes();
    meds = await db.meds();
    subject = await db.currentSubject();
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
    for (final t in types) {
      await _afterEventChange(t.id);
    }
    await Notifications.instance.rescheduleAll();
  }

  // ---------- מבנה (סוגים, שדות, תרופות, נושא) ----------

  Future<void> reloadStructure() async {
    await load();
    sync.requestSync();
  }

  Future<void> saveSubject(Subject s) async {
    await db.saveSubject(s);
    await reloadStructure();
  }

  // ---------- אירועים ----------

  LogEvent newEvent(String typeId, {Map<String, dynamic>? values}) => LogEvent(
    id: newId(),
    subjectId: subjectId,
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
      for (final m in meds) {
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
    await Notifications.instance.cancel(Notifications.followUpId(f.id));
    _changed();
  }

  Future<void> deleteFollowUp(FollowUp f) async {
    await Notifications.instance.cancel(Notifications.followUpId(f.id));
    await db.deleteFollowUp(f.id);
    _changed();
  }
}

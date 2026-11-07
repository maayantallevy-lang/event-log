import 'package:flutter/foundation.dart';

import 'db/app_db.dart';
import 'models.dart';
import 'services/notifications.dart';

/// מצב גלובלי קל: סוגי אירועים, תרופות, תינוק, הגדרות.
/// כל שינוי בנתונים קורא ל-[bump] כדי שהמסכים יתרעננו.
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  final db = AppDb.instance;

  List<EventType> types = [];
  List<Med> meds = [];
  Baby? baby;
  int dayStartHour = 7;
  int revision = 0;

  Map<int, EventType> get typeById => {for (final t in types) t.id: t};
  Map<int, Med> get medById => {for (final m in meds) m.id: m};

  EventType? get medType {
    for (final t in types) {
      if (t.isMed) return t;
    }
    return null;
  }

  Future<void> load() async {
    types = await db.eventTypes(includeHidden: true);
    meds = await db.meds(activeOnly: false);
    baby = await db.currentBaby();
    dayStartHour = await db.dayStartHour;
    revision++;
    notifyListeners();
  }

  /// לאחר שינוי באירועים (לא במבנה) - רק רענון מסכים.
  void bump() {
    revision++;
    notifyListeners();
  }

  List<EventType> get visibleTypes => types.where((t) => !t.hidden).toList();

  // ---------- פעולות שמשלבות DB + תזכורות ----------

  Future<int> saveEvent(LogEvent e) async {
    int id;
    if (e.id == 0) {
      id = await db.insertEvent(e);
    } else {
      await db.updateEvent(e);
      id = e.id;
    }
    await _afterEventChange(e.typeId);
    bump();
    return id;
  }

  Future<void> deleteEvent(LogEvent e) async {
    await db.deleteEvent(e.id);
    await _afterEventChange(e.typeId);
    bump();
  }

  Future<void> _afterEventChange(int typeId) async {
    final t = typeById[typeId];
    if (t == null) return;
    final last = await db.lastEventOfType(typeId);
    if (t.isMed) {
      // לכל תרופה פעילה - תזכורת לפי המנה האחרונה שלה.
      for (final m in meds.where((m) => m.active)) {
        final lastMed = await db.lastMedEvent(m.id);
        if (lastMed != null) {
          await Notifications.instance.scheduleMedReminder(
            m,
            lastMed.timestamp,
          );
        } else {
          await Notifications.instance.cancel(Notifications.medId(m.id));
        }
      }
    } else if (last != null) {
      await Notifications.instance.scheduleTypeReminder(t, last.timestamp);
    } else {
      await Notifications.instance.cancel(Notifications.typeId(t.id));
    }
  }

  Future<void> saveAppointment(Appointment a) async {
    if (a.id == 0) {
      final id = await db.insertAppointment(a);
      final saved = await db.appointment(id);
      if (saved != null)
        await Notifications.instance.scheduleAppointment(saved);
    } else {
      await db.updateAppointment(a);
      await Notifications.instance.scheduleAppointment(a);
    }
    bump();
  }

  Future<void> deleteAppointment(Appointment a) async {
    await Notifications.instance.cancelAppointment(a);
    await db.deleteAppointment(a.id);
    bump();
  }

  Future<void> addFollowUp(FollowUp f) async {
    final id = await db.insertFollowUp(f);
    final saved = await db.followUp(id);
    if (saved != null) await Notifications.instance.scheduleFollowUp(saved);
    bump();
  }

  Future<void> completeFollowUp(FollowUp f) async {
    f.doneAt = DateTime.now();
    await db.updateFollowUp(f);
    await Notifications.instance.cancel(Notifications.followUpId(f.id));
    bump();
  }

  Future<void> deleteFollowUp(FollowUp f) async {
    await Notifications.instance.cancel(Notifications.followUpId(f.id));
    await db.deleteFollowUp(f.id);
    bump();
  }
}

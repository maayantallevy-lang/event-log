import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../db/app_db.dart';
import '../models.dart';
import '../util/format.dart';
import '../util/ids.dart';

/// מה קרה כשהמשתמש לחץ על התראה (או על כפתור בה).
class NotificationTap {
  final String payload;
  final String? actionId;
  NotificationTap(this.payload, this.actionId);

  String get kind => payload.split(':').first;
  String get id => payload.substring(payload.indexOf(':') + 1);
}

class Notifications {
  Notifications._();
  static final Notifications instance = Notifications._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// האם מותר לתזמן התראות בזמן מדויק (אנדרואיד 12+ דורש אישור).
  /// בלי אישור - התראות "בערך בזמן" (עד כמה דקות איחור), בלי קריסה.
  bool exactAllowed = true;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// פותח את מסך ההרשאה "התראות ותזכורות" של אנדרואיד.
  Future<void> requestExactAlarms() async {
    await _android?.requestExactAlarmsPermission();
    exactAllowed = await _android?.canScheduleExactNotifications() ?? true;
  }

  Future<void> requestNotifications() async {
    await _android?.requestNotificationsPermission();
  }

  Future<bool> notificationsEnabled() async =>
      await _android?.areNotificationsEnabled() ?? true;

  /// נקרא מה-UI כשיש לחיצה על התראה.
  void Function(NotificationTap tap)? onTap;

  /// לחיצה שקרתה לפני שה-UI היה מוכן.
  NotificationTap? pending;

  static const _channel = AndroidNotificationDetails(
    'reminders',
    'תזכורות',
    channelDescription: 'תזכורות לפי מרווח, תרופות, תורים ומשימות מעקב',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.reminder,
  );

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: _handle,
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    try {
      await android?.requestNotificationsPermission();
      exactAllowed = await android?.canScheduleExactNotifications() ?? true;
    } catch (_) {
      exactAllowed = false;
    }
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true &&
        launch?.notificationResponse != null) {
      _handle(launch!.notificationResponse!);
    }
    _ready = true;
  }

  void _handle(NotificationResponse r) {
    final payload = r.payload;
    if (payload == null || payload.isEmpty) return;
    final tap = NotificationTap(payload, r.actionId);
    if (onTap != null) {
      onTap!(tap);
    } else {
      pending = tap;
    }
  }

  Future<void> _schedule(
    int id,
    String title,
    String body,
    DateTime when,
    String payload, {
    List<AndroidNotificationAction>? actions,
  }) async {
    if (!when.isAfter(DateTime.now())) return;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channel.channelId,
        _channel.channelName,
        channelDescription: _channel.channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        actions: actions,
      ),
    );
    Future<void> go(AndroidScheduleMode mode) => _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      details,
      androidScheduleMode: mode,
      payload: payload,
    );
    try {
      await go(
        exactAllowed
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {
      // ההרשאה בוטלה בינתיים: נופלים לתזמון לא מדויק במקום לקרוס.
      exactAllowed = false;
      try {
        await go(AndroidScheduleMode.inexactAllowWhileIdle);
      } catch (_) {}
    }
  }

  Future<void> cancel(int id) => _plugin.cancel(id);

  static const _logActions = [
    AndroidNotificationAction('done', 'נרשם עכשיו', showsUserInterface: true),
    AndroidNotificationAction(
      'snooze',
      'נודניק 15 דק\'',
      showsUserInterface: true,
    ),
  ];

  // ---------- שם היומן בכותרת (כשיש יותר מיומן אחד) ----------

  /// מזהה יומן -> "שם · ". ריק כשיש יומן אחד בלבד. מתעדכן ב-AppState.load.
  static Map<String, String> journalPrefix = {};
  static String? firstJournalId;
  static String _pfx(String? subjectId) =>
      journalPrefix[subjectId ?? firstJournalId] ?? '';

  // ---------- מזהי התראות ----------
  // המזהים במסד הם מחרוזות; ההתראה צריכה int יציב כדי שאפשר יהיה לבטל אותה.
  static int _h(String s) => stableHash(s) % 400000;
  static int typeId(String t) => 1000000 + _h(t);
  static int medId(String m) => 2000000 + _h(m);

  /// עד [maxApptReminders] תזכורות לתור + התראת "איך היה?".
  static const maxApptReminders = 10;
  static int apptId(String a, int idx) => 10000000 + _h(a) * 12 + idx;
  static int apptAskId(String a) => apptId(a, 11);
  // מזהים של גרסאות 0.3 ומטה, כדי לבטל התראות ישנות שנשארו מתוזמנות.
  static int _legacyApptId(String a, int idx) => 3000000 + _h(a) * 5 + idx;
  static int followUpId(String f) => 6000000 + _h(f);

  /// נדנוד יומי = התראה נפרדת לכל אחד מ-[followUpDays] הימים הבאים, כדי
  /// שגם התראה שהוחלקה תחזור מחר (ובלי תלות באזור הזמן של הספרייה).
  static const followUpDays = 14;
  static int followUpDayId(String f, int day) => 20000000 + _h(f) * 16 + day;

  // ---------- תזכורת "כל X שעות" לסוג אירוע ----------

  Future<void> scheduleTypeReminder(EventType t, DateTime last) async {
    await cancel(typeId(t.id));
    final h = t.intervalReminderHours;
    if (h == null || h <= 0) return;
    final when = last.add(Duration(minutes: (h * 60).round()));
    await _schedule(
      typeId(t.id),
      '${_pfx(t.subjectId)}הגיע הזמן: ${t.name}',
      'הפעם האחרונה: ${fmtTime(last)}',
      when,
      'log:${t.id}',
      actions: _logActions,
    );
  }

  Future<void> snoozeType(EventType t) async {
    await _schedule(
      typeId(t.id),
      '${_pfx(t.subjectId)}הגיע הזמן: ${t.name}',
      'נודניק',
      DateTime.now().add(const Duration(minutes: 15)),
      'log:${t.id}',
      actions: _logActions,
    );
  }

  // ---------- תזכורת תרופה ----------

  Future<void> scheduleMedReminder(Med m, DateTime last) async {
    await cancel(medId(m.id));
    final h = m.intervalHours;
    if (h == null || h <= 0) return;
    final when = last.add(Duration(minutes: (h * 60).round()));
    await _schedule(
      medId(m.id),
      '${_pfx(m.subjectId)}תרופה: ${m.name}',
      'המנה האחרונה ניתנה ב-${fmtTime(last)}',
      when,
      'med:${m.id}',
      actions: _logActions,
    );
  }

  Future<void> snoozeMed(Med m) async {
    await _schedule(
      medId(m.id),
      '${_pfx(m.subjectId)}תרופה: ${m.name}',
      'נודניק',
      DateTime.now().add(const Duration(minutes: 15)),
      'med:${m.id}',
      actions: _logActions,
    );
  }

  // ---------- תורים ----------

  Future<void> scheduleAppointment(Appointment a) async {
    await cancelAppointment(a);
    if (a.done) return;
    final where = a.location == null || a.location!.isEmpty
        ? ''
        : ' · ${a.location}';
    for (var i = 0; i < a.remindBeforeMin.length && i < maxApptReminders; i++) {
      final when = a.scheduledAt.subtract(
        Duration(minutes: a.remindBeforeMin[i]),
      );
      await _schedule(
        apptId(a.id, i),
        '${_pfx(a.subjectId)}תור: ${a.title}',
        '${weekdayName(a.scheduledAt)} ${fmtTime(a.scheduledAt)}$where',
        when,
        'appt:${a.id}',
      );
    }
    if (!a.followUpAsked) {
      await _schedule(
        apptAskId(a.id),
        '${_pfx(a.subjectId)}איך היה בתור "${a.title}"?',
        'קיבלת מרשם או הפניה? לחץ לסיכום קצר',
        a.scheduledAt.add(const Duration(hours: 1)),
        'ask:${a.id}',
      );
    }
  }

  Future<void> cancelAppointment(Appointment a) async {
    for (var i = 0; i < maxApptReminders; i++) {
      await cancel(apptId(a.id, i));
    }
    await cancel(apptAskId(a.id));
    for (var i = 0; i < 5; i++) {
      await cancel(_legacyApptId(a.id, i));
    }
  }

  // ---------- משימות מעקב: נדנוד פעם ביום ----------

  Future<void> cancelFollowUp(FollowUp f) async {
    await cancel(followUpId(f.id)); // מזהה של גרסאות קודמות
    for (var d = 0; d < followUpDays; d++) {
      await cancel(followUpDayId(f.id, d));
    }
  }

  Future<void> scheduleFollowUp(FollowUp f) async {
    await cancelFollowUp(f);
    if (!f.isOpen) return;
    final parts = f.remindDailyAt.split(':');
    final h = int.tryParse(parts[0]) ?? 10;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    final now = DateTime.now();
    var first = DateTime(now.year, now.month, now.day, h, m);
    if (!first.isAfter(now.add(const Duration(minutes: 1)))) {
      first = DateTime(now.year, now.month, now.day + 1, h, m);
    }
    for (var d = 0; d < followUpDays; d++) {
      // בנייה לפי תאריך (ולא add של 24 שעות) כדי לא לזוז במעבר שעון.
      final when = DateTime(first.year, first.month, first.day + d, h, m);
      await _schedule(
        followUpDayId(f.id, d),
        '${_pfx(f.subjectId)}תזכורת: ${f.title}',
        'סמן "בוצע" כשסיימת ואפסיק להזכיר',
        when,
        'followup:${f.id}',
        actions: const [
          AndroidNotificationAction('done', 'בוצע', showsUserInterface: true),
          AndroidNotificationAction(
            'snooze',
            'תזכר מחר',
            showsUserInterface: true,
          ),
        ],
      );
    }
  }

  /// נקרא בכל פתיחת אפליקציה: מוודא שכל התזכורות הפתוחות מתוזמנות.
  /// גם מבטל תזכורות של תורים ומשימות שנמחקו או הושלמו (גם בטלפון אחר).
  Future<void> rescheduleAll() async {
    final db = AppDb.instance;
    for (final f in await db.openFollowUps()) {
      await scheduleFollowUp(f);
    }
    for (final f in await db.closedFollowUps()) {
      await cancelFollowUp(f);
    }
    for (final a in await db.appointments(upcomingOnly: true)) {
      await scheduleAppointment(a);
    }
    for (final a in await db.inactiveUpcomingAppointments()) {
      await cancelAppointment(a);
    }
  }
}

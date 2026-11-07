import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../db/app_db.dart';
import '../models.dart';
import '../util/format.dart';

/// מה קרה כשהמשתמש לחץ על התראה (או על כפתור בה).
class NotificationTap {
  final String payload;
  final String? actionId;
  NotificationTap(this.payload, this.actionId);

  String get kind => payload.split(':').first;
  int get id => int.tryParse(payload.split(':').last) ?? 0;
}

class Notifications {
  Notifications._();
  static final Notifications instance = Notifications._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// נקרא מה-UI כשיש לחיצה על התראה.
  void Function(NotificationTap tap)? onTap;

  /// לחיצה שקרתה לפני שה-UI היה מוכן.
  NotificationTap? pending;

  static const _channel = AndroidNotificationDetails(
    'reminders',
    'תזכורות',
    channelDescription: 'תזכורות האכלה, תרופות ותורים',
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
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
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
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );
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

  // ---------- מזהי התראות ----------
  static int typeId(int t) => 1000 + t;
  static int medId(int m) => 2000 + m;
  static int apptId(int a, int idx) => 3000 + a * 4 + idx;
  static int apptAskId(int a) => 40000 + a;
  static int followUpId(int f) => 50000 + f;

  // ---------- תזכורת "כל X שעות" לסוג אירוע ----------

  Future<void> scheduleTypeReminder(EventType t, DateTime last) async {
    await cancel(typeId(t.id));
    final h = t.intervalReminderHours;
    if (h == null || h <= 0) return;
    final when = last.add(Duration(minutes: (h * 60).round()));
    await _schedule(
      typeId(t.id),
      'הגיע הזמן: ${t.name}',
      'ה${t.name} האחרון/ה היה ב-${fmtTime(last)}',
      when,
      'log:${t.id}',
      actions: _logActions,
    );
  }

  Future<void> snoozeType(EventType t) async {
    await _schedule(
      typeId(t.id),
      'הגיע הזמן: ${t.name}',
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
      'תרופה: ${m.name}',
      'המנה האחרונה ניתנה ב-${fmtTime(last)}',
      when,
      'med:${m.id}',
      actions: _logActions,
    );
  }

  Future<void> snoozeMed(Med m) async {
    await _schedule(
      medId(m.id),
      'תרופה: ${m.name}',
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
    for (var i = 0; i < a.remindBeforeMin.length && i < 4; i++) {
      final when = a.scheduledAt.subtract(
        Duration(minutes: a.remindBeforeMin[i]),
      );
      await _schedule(
        apptId(a.id, i),
        'תור: ${a.title}',
        '${weekdayName(a.scheduledAt)} ${fmtTime(a.scheduledAt)}$where',
        when,
        'appt:${a.id}',
      );
    }
    if (!a.followUpAsked) {
      await _schedule(
        apptAskId(a.id),
        'איך היה בתור "${a.title}"?',
        'קיבלת מרשם או הפניה? לחץ לסיכום קצר',
        a.scheduledAt.add(const Duration(hours: 1)),
        'ask:${a.id}',
      );
    }
  }

  Future<void> cancelAppointment(Appointment a) async {
    for (var i = 0; i < 4; i++) {
      await cancel(apptId(a.id, i));
    }
    await cancel(apptAskId(a.id));
  }

  // ---------- משימות מעקב: נדנוד פעם ביום ----------

  Future<void> scheduleFollowUp(FollowUp f) async {
    await cancel(followUpId(f.id));
    if (!f.isOpen) return;
    final parts = f.remindDailyAt.split(':');
    final h = int.tryParse(parts[0]) ?? 10;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    final now = DateTime.now();
    var when = DateTime(now.year, now.month, now.day, h, m);
    if (!when.isAfter(now.add(const Duration(minutes: 1)))) {
      when = when.add(const Duration(days: 1));
    }
    await _schedule(
      followUpId(f.id),
      'תזכורת: ${f.title}',
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

  /// נקרא בכל פתיחת אפליקציה: מוודא שכל התזכורות הפתוחות מתוזמנות.
  Future<void> rescheduleAll() async {
    final db = AppDb.instance;
    for (final f in await db.openFollowUps()) {
      await scheduleFollowUp(f);
    }
    for (final a in await db.appointments(upcomingOnly: true)) {
      await scheduleAppointment(a);
    }
  }
}

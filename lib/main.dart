import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_state.dart';
import 'screens/appointment_screen.dart';
import 'screens/follow_up_sheet.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/log_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/stats_screen.dart';
import 'services/notifications.dart';
import 'theme/skins.dart';
import 'widgets/log_sheet.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState.instance;
  await state.load();
  await Notifications.instance.init();
  await Notifications.instance.rescheduleAll();
  state.sync.onRemoteChanges = state.onRemoteChanges;
  unawaited(state.sync.start());
  runApp(const EventLogApp());
}

class EventLogApp extends StatelessWidget {
  const EventLogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Appearance>(
      valueListenable: AppState.instance.appearance,
      builder: (context, look, _) => MaterialApp(
        title: 'יומנון',
        debugShowCheckedModeBanner: false,
        locale: const Locale('he'),
        supportedLocales: const [Locale('he'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: look.skin.theme(look.font),
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
        home: ListenableBuilder(
          listenable: AppState.instance,
          builder: (context, _) => AppState.instance.isSetUp
              ? const Shell()
              : const OnboardingScreen(),
        ),
      ),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int index = 0;
  final state = AppState.instance;

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // חוזרים לאפליקציה: אולי טלפון אחר תיעד בינתיים.
    if (s == AppLifecycleState.resumed) unawaited(state.sync.sync());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Notifications.instance.onTap = _onNotificationTap;
    final pending = Notifications.instance.pending;
    if (pending != null) {
      Notifications.instance.pending = null;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _onNotificationTap(pending),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Notifications.instance.onTap = null;
    super.dispose();
  }

  /// לחיצה על התראה או על כפתור בה.
  Future<void> _onNotificationTap(NotificationTap tap) async {
    if (!mounted) return;
    final db = state.db;
    switch (tap.kind) {
      case 'log':
        final t = state.typeById[tap.id];
        if (t == null) return;
        if (tap.actionId == 'done') {
          await state.saveEvent(state.newEvent(t.id));
          _snack('נרשם: ${t.name}');
        } else if (tap.actionId == 'snooze') {
          await Notifications.instance.snoozeType(t);
          _snack('אזכיר בעוד 15 דקות');
        } else {
          await state.showJournalOf(t.subjectId);
          if (mounted) showLogSheet(context, t);
        }
        break;
      case 'med':
        final m = state.medById[tap.id];
        if (m == null) return;
        await state.showJournalOf(m.subjectId);
        final medType = state.medType;
        if (medType == null) return;
        if (tap.actionId == 'done') {
          await state.saveEvent(
            state.newEvent(
              medType.id,
              values: {'med_id': m.id, 'dose': m.defaultDose},
            ),
          );
          _snack('נרשם: ${m.name}');
        } else if (tap.actionId == 'snooze') {
          await Notifications.instance.snoozeMed(m);
          _snack('אזכיר בעוד 15 דקות');
        } else {
          if (mounted) showLogSheet(context, medType);
        }
        break;
      case 'appt':
        final a = await db.appointment(tap.id);
        if (a == null) return;
        await state.showJournalOf(a.subjectId);
        if (mounted) openAppointment(context, a);
        break;
      case 'ask':
        final a = await db.appointment(tap.id);
        if (a != null && !a.followUpAsked) {
          await state.showJournalOf(a.subjectId);
          if (mounted) showFollowUpSheet(context, a);
        }
        break;
      case 'followup':
        final f = await db.followUp(tap.id);
        if (f == null) return;
        if (tap.actionId == 'done') {
          await state.completeFollowUp(f);
          _snack('סומן כבוצע: ${f.title}');
        } else {
          // 'snooze' או לחיצה רגילה: ההתראה הבאה היא מחר באותה שעה.
          await Notifications.instance.scheduleFollowUp(f);
          await state.showJournalOf(f.subjectId);
          setState(() => index = 0);
        }
        break;
    }
  }

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  Widget build(BuildContext context) {
    const screens = [
      HomeScreen(),
      LogScreen(),
      StatsScreen(),
      SettingsScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: index, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'בית'),
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'יומן'),
          NavigationDestination(
            icon: Icon(Icons.bar_chart),
            label: 'סטטיסטיקה',
          ),
          NavigationDestination(icon: Icon(Icons.settings), label: 'הגדרות'),
        ],
      ),
    );
  }
}

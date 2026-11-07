import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_state.dart';
import 'models.dart';
import 'screens/appointment_screen.dart';
import 'screens/follow_up_sheet.dart';
import 'screens/home_screen.dart';
import 'screens/log_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/stats_screen.dart';
import 'services/notifications.dart';
import 'widgets/log_sheet.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppState.instance.load();
  await Notifications.instance.init();
  await Notifications.instance.rescheduleAll();
  runApp(const BabyLogApp());
}

class BabyLogApp extends StatelessWidget {
  const BabyLogApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF42A5F5));
    return MaterialApp(
      title: 'יומן תינוק',
      debugShowCheckedModeBanner: false,
      locale: const Locale('he'),
      supportedLocales: const [Locale('he'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        cardTheme: const CardThemeData(
          margin: EdgeInsets.symmetric(vertical: 4),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF42A5F5),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const Shell(),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int index = 0;
  final state = AppState.instance;

  @override
  void initState() {
    super.initState();
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
          await state.saveEvent(
            LogEvent(
              id: 0,
              babyId: state.baby?.id ?? 1,
              typeId: t.id,
              timestamp: DateTime.now(),
            ),
          );
          _snack('נרשם: ${t.name}');
        } else if (tap.actionId == 'snooze') {
          await Notifications.instance.snoozeType(t);
          _snack('אזכיר בעוד 15 דקות');
        } else {
          if (mounted) showLogSheet(context, t);
        }
        break;
      case 'med':
        final m = state.medById[tap.id];
        final medType = state.medType;
        if (m == null || medType == null) return;
        if (tap.actionId == 'done') {
          await state.saveEvent(
            LogEvent(
              id: 0,
              babyId: state.baby?.id ?? 1,
              typeId: medType.id,
              timestamp: DateTime.now(),
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
        if (a != null && mounted) openAppointment(context, a);
        break;
      case 'ask':
        final a = await db.appointment(tap.id);
        if (a != null && !a.followUpAsked && mounted) {
          showFollowUpSheet(context, a);
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

import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../db/app_db.dart';
import '../models.dart';
import '../util/format.dart';
import '../widgets/log_sheet.dart';
import 'appointment_screen.dart';
import 'follow_up_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final state = AppState.instance;
  Map<int, LogEvent> lastByType = {};
  List<LogEvent> recent = [];
  List<Appointment> upcoming = [];
  List<Appointment> awaitingFollowUp = [];
  List<FollowUp> followUps = [];
  Timer? ticker;

  @override
  void initState() {
    super.initState();
    state.addListener(_load);
    _load();
    ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    state.removeListener(_load);
    ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final db = state.db;
    final map = <int, LogEvent>{};
    for (final t in state.visibleTypes) {
      final e = await db.lastEventOfType(t.id);
      if (e != null) map[t.id] = e;
    }
    final r = await db.events(limit: 5);
    final up = await db.appointments(upcomingOnly: true);
    final awaiting = await db.appointmentsAwaitingFollowUp();
    final fu = await db.openFollowUps();
    if (!mounted) return;
    setState(() {
      lastByType = map;
      recent = r;
      upcoming = up.take(3).toList();
      awaitingFollowUp = awaiting;
      followUps = fu;
    });
  }

  Future<void> _log(EventType t) async {
    final saved = await showLogSheet(context, t);
    if (saved == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('נרשם: ${t.name}'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'בטל',
          onPressed: () => state.deleteEvent(saved),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final baby = state.baby;
    final subtitle = baby?.birthDate == null ? null : ageText(baby!.birthDate!);
    return Scaffold(
      appBar: AppBar(
        title: Text(baby?.name ?? 'יומן תינוק'),
        bottom: subtitle == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(20),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _statusCard(),
            if (awaitingFollowUp.isNotEmpty) _awaitingCard(),
            if (followUps.isNotEmpty) _followUpsCard(),
            const SizedBox(height: 8),
            _buttonsGrid(),
            const SizedBox(height: 12),
            if (recent.isNotEmpty) _recentList(),
          ],
        ),
      ),
    );
  }

  Widget _statusCard() {
    final types = state.visibleTypes.where((t) => lastByType[t.id] != null);
    final medById = state.medById;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (types.isEmpty && upcoming.isEmpty)
              const Text('עדיין אין אירועים. לחץ על כפתור כדי לתעד.'),
            for (final t in types) _statusLine(t, lastByType[t.id]!, medById),
            if (upcoming.isNotEmpty) ...[
              if (types.isNotEmpty) const Divider(),
              for (final a in upcoming) _appointmentLine(a),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusLine(EventType t, LogEvent e, Map<int, Med> medById) {
    final details = describeValues(t, e.values, medById);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(iconFor(t.icon), color: Color(t.color), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: [
                  TextSpan(
                    text: '${t.name} ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: ago(e.timestamp)),
                  if (details.isNotEmpty)
                    TextSpan(
                      text: ' · $details',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _appointmentLine(Appointment a) {
    return InkWell(
      onTap: () => openAppointment(context, a),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            const Icon(Icons.event, color: Colors.teal, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${a.title} · ${weekdayName(a.scheduledAt)} ${fmtTime(a.scheduledAt)} (${until(a.scheduledAt)})',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _awaitingCard() {
    return Card(
      color: Colors.blue.shade50,
      child: Column(
        children: [
          for (final a in awaitingFollowUp)
            ListTile(
              leading: const Icon(Icons.help_outline, color: Colors.blue),
              title: Text('איך היה בתור "${a.title}"?'),
              subtitle: Text(fmtDateTime(a.scheduledAt)),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => showFollowUpSheet(context, a),
            ),
        ],
      ),
    );
  }

  Widget _followUpsCard() {
    return Card(
      color: Colors.amber.shade50,
      child: Column(
        children: [
          for (final f in followUps)
            ListTile(
              leading: Icon(
                f.kind == FollowUpKind.buyMed
                    ? Icons.local_pharmacy
                    : f.kind == FollowUpKind.bookAppointment
                    ? Icons.event_available
                    : Icons.task_alt,
                color: DateTime.now().difference(f.createdAt).inDays >= 7
                    ? Colors.red
                    : Colors.amber.shade800,
              ),
              title: Text(f.title),
              subtitle: Text('נוצר ${fmtDate(f.createdAt)}'),
              trailing: FilledButton.tonal(
                onPressed: () => _completeFollowUp(f),
                child: const Text('בוצע'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _completeFollowUp(FollowUp f) async {
    await state.completeFollowUp(f);
    if (!mounted) return;
    if (f.kind == FollowUpKind.bookAppointment) {
      final add = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('קבעת תור?'),
          content: const Text('להוסיף אותו ליומן עכשיו?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('לא עכשיו'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('כן, הוסף תור'),
            ),
          ],
        ),
      );
      if (add == true && mounted) {
        await openAppointment(context, null, titleHint: f.title);
      }
    }
  }

  Widget _buttonsGrid() {
    final types = state.visibleTypes;
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.1,
      children: [for (final t in types) _bigButton(t), _apptButton()],
    );
  }

  Widget _bigButton(EventType t) {
    final color = Color(t.color);
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _log(t),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(iconFor(t.icon), color: Colors.white, size: 36),
            const SizedBox(height: 6),
            Text(
              t.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _apptButton() {
    return Material(
      color: Colors.teal,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => openAppointment(context, null),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event, color: Colors.white, size: 36),
            SizedBox(height: 6),
            Text(
              'תור',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recentList() {
    final typeById = state.typeById;
    final medById = state.medById;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'אחרונים',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          for (final e in recent)
            Builder(
              builder: (context) {
                final t = typeById[e.typeId];
                if (t == null) return const SizedBox.shrink();
                final details = describeValues(t, e.values, medById);
                return ListTile(
                  dense: true,
                  leading: Icon(iconFor(t.icon), color: Color(t.color)),
                  title: Text(
                    '${t.name}${details.isEmpty ? '' : ' · $details'}',
                  ),
                  subtitle: Text(
                    '${fmtTime(e.timestamp)} · ${ago(e.timestamp)}${e.note == null ? '' : ' · ${e.note}'}',
                  ),
                  onTap: () => showLogSheet(context, t, existing: e),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await state.deleteEvent(e);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('נמחק'),
                          action: SnackBarAction(
                            label: 'בטל',
                            onPressed: () => state.saveEvent(
                              LogEvent(
                                id: 0,
                                babyId: e.babyId,
                                typeId: e.typeId,
                                timestamp: e.timestamp,
                                values: e.values,
                                note: e.note,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

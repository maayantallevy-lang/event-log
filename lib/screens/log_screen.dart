import 'package:flutter/material.dart';

import '../app_state.dart';
import '../db/app_db.dart';
import '../models.dart';
import '../util/format.dart';
import '../widgets/log_sheet.dart';
import 'appointment_screen.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

/// פריט ביומן: אירוע או תור, ממוינים יחד לפי זמן.
class _Item {
  final DateTime at;
  final LogEvent? event;
  final Appointment? appt;
  _Item.event(this.event) : at = event!.timestamp, appt = null;
  _Item.appt(this.appt) : at = appt!.scheduledAt, event = null;
}

class _LogScreenState extends State<LogScreen> {
  final state = AppState.instance;
  int? filterType; // null = הכל, -1 = תורים
  int rangeDays = 3; // 1, 3, 7, 0 = הכל
  List<_Item> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    state.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    state.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final from = rangeDays == 0
        ? null
        : logicalDayStart(
            now,
            state.dayStartHour,
          ).subtract(Duration(days: rangeDays - 1));
    final list = <_Item>[];
    if (filterType == null || filterType! > 0) {
      final evs = await state.db.events(
        from: from,
        typeIds: filterType == null ? null : {filterType!},
      );
      list.addAll(evs.map(_Item.event));
    }
    if (filterType == null || filterType == -1) {
      final appts = await state.db.appointments(from: from);
      list.addAll(appts.map(_Item.appt));
    }
    list.sort((a, b) => b.at.compareTo(a.at));
    if (!mounted) return;
    setState(() {
      items = list;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('יומן'),
        actions: [
          PopupMenuButton<int>(
            icon: const Icon(Icons.date_range),
            initialValue: rangeDays,
            onSelected: (v) {
              rangeDays = v;
              _load();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 1, child: Text('היום')),
              PopupMenuItem(value: 3, child: Text('3 ימים')),
              PopupMenuItem(value: 7, child: Text('שבוע')),
              PopupMenuItem(value: 30, child: Text('חודש')),
              PopupMenuItem(value: 0, child: Text('הכל')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _filterChips(),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                ? const Center(child: Text('אין אירועים בטווח הזה'))
                : _list(),
          ),
        ],
      ),
    );
  }

  Widget _filterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('הכל'),
            selected: filterType == null,
            onSelected: (_) {
              filterType = null;
              _load();
            },
          ),
          const SizedBox(width: 6),
          for (final t in state.visibleTypes) ...[
            ChoiceChip(
              avatar: Icon(iconFor(t.icon), size: 18, color: Color(t.color)),
              label: Text(t.name),
              selected: filterType == t.id,
              onSelected: (_) {
                filterType = t.id;
                _load();
              },
            ),
            const SizedBox(width: 6),
          ],
          ChoiceChip(
            avatar: const Icon(Icons.event, size: 18, color: Colors.teal),
            label: const Text('תורים'),
            selected: filterType == -1,
            onSelected: (_) {
              filterType = -1;
              _load();
            },
          ),
        ],
      ),
    );
  }

  Widget _list() {
    final today = DateTime.now();
    final typeById = state.typeById;
    final medById = state.medById;
    final rows = <Widget>[];
    DateTime? currentDay;
    final counts = <DateTime, Map<int, int>>{};
    for (final it in items) {
      final day = logicalDayStart(it.at, state.dayStartHour);
      if (it.event != null) {
        counts.putIfAbsent(day, () => {});
        counts[day]!.update(it.event!.typeId, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    for (final it in items) {
      final day = logicalDayStart(it.at, state.dayStartHour);
      if (currentDay == null || day != currentDay) {
        currentDay = day;
        final c = counts[day] ?? {};
        final summary = c.entries
            .map((e) => '${e.value} ${typeById[e.key]?.name ?? ''}')
            .join(' · ');
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              children: [
                Text(
                  dayTitle(day, today),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    summary,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      }
      if (it.appt != null) {
        rows.add(_apptTile(it.appt!));
      } else {
        final e = it.event!;
        final t = typeById[e.typeId];
        if (t == null) continue;
        rows.add(_eventTile(e, t, medById));
      }
    }
    return ListView(children: rows);
  }

  Widget _apptTile(Appointment a) {
    final past = a.scheduledAt.isBefore(DateTime.now());
    return ListTile(
      leading: Icon(
        past ? Icons.event_available : Icons.event,
        color: Colors.teal,
      ),
      title: Text(a.title),
      subtitle: Text(
        [
          fmtTime(a.scheduledAt),
          if (a.location != null && a.location!.isNotEmpty) a.location!,
          if (a.summary != null && a.summary!.isNotEmpty) a.summary!,
        ].join(' · '),
      ),
      onTap: () => openAppointment(context, a),
    );
  }

  Widget _eventTile(LogEvent e, EventType t, Map<int, Med> medById) {
    final details = describeValues(t, e.values, medById);
    return Dismissible(
      key: ValueKey('ev${e.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) async {
        await state.deleteEvent(e);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('נמחק: ${t.name}'),
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
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Color(t.color).withAlpha(50),
          child: Icon(iconFor(t.icon), color: Color(t.color)),
        ),
        title: Text('${t.name}${details.isEmpty ? '' : ' · $details'}'),
        subtitle: Text(
          '${fmtTime(e.timestamp)}${e.note == null ? '' : ' · ${e.note}'}',
        ),
        onTap: () => showLogSheet(context, t, existing: e),
      ),
    );
  }
}

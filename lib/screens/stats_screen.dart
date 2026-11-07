import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../util/format.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _DayStat {
  final DateTime day;
  int count = 0;
  double sum = 0;
  int n = 0; // כמה ערכים מספריים נספרו (לממוצע)
  _DayStat(this.day);

  double value(String agg) => agg == StatAgg.avg ? (n == 0 ? 0 : sum / n) : sum;
}

class _StatsScreenState extends State<StatsScreen> {
  final state = AppState.instance;
  String? typeId;
  int days = 7;
  List<_DayStat> stats = [];
  double avgGapMinutes = 0;
  double avgAmount = 0;
  int total = 0;
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

  EventType? get type {
    if (typeId == null) {
      final v = state.visibleTypes;
      if (v.isNotEmpty) typeId = v.first.id;
    }
    return state.typeById[typeId];
  }

  EventField? get statField {
    final t = type;
    if (t == null) return null;
    if (t.isMed) return null;
    for (final f in t.fields) {
      if (f.id == t.statFieldId) return f;
    }
    return null;
  }

  Future<void> _load() async {
    final t = type;
    if (t == null) {
      setState(() => loading = false);
      return;
    }
    final now = DateTime.now();
    final todayStart = logicalDayStart(now, state.dayStartHour);
    final from = todayStart.subtract(Duration(days: days - 1));
    final evs = await state.db.events(from: from, typeIds: {t.id});
    final byDay = <DateTime, _DayStat>{};
    for (var i = 0; i < days; i++) {
      final d = from.add(Duration(days: i));
      byDay[d] = _DayStat(d);
    }
    final f = statField;
    final key = f?.id.toString();
    double sumAmount = 0;
    int amountCount = 0;
    for (final e in evs) {
      final d = logicalDayStart(e.timestamp, state.dayStartHour);
      final s = byDay[d];
      if (s == null) continue;
      s.count++;
      if (key != null) {
        final v = e.values[key];
        if (v is num) {
          s.sum += v.toDouble();
          s.n++;
          sumAmount += v.toDouble();
          amountCount++;
        }
      } else if (t.isMed) {
        final v = e.values['dose'];
        if (v is num) {
          s.sum += v.toDouble();
          s.n++;
          sumAmount += v.toDouble();
          amountCount++;
        }
      }
    }
    // מרווח ממוצע בין אירועים עוקבים (evs ממוינים מהחדש לישן).
    double gaps = 0;
    for (var i = 0; i + 1 < evs.length; i++) {
      gaps += evs[i].timestamp.difference(evs[i + 1].timestamp).inMinutes;
    }
    if (!mounted) return;
    setState(() {
      stats = byDay.values.toList();
      total = evs.length;
      avgGapMinutes = evs.length > 1 ? gaps / (evs.length - 1) : 0;
      avgAmount = amountCount > 0 ? sumAmount / amountCount : 0;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = type;
    return Scaffold(
      appBar: AppBar(
        title: const Text('סטטיסטיקה'),
        actions: [
          PopupMenuButton<int>(
            icon: const Icon(Icons.date_range),
            onSelected: (v) {
              days = v;
              _load();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 7, child: Text('7 ימים')),
              PopupMenuItem(value: 14, child: Text('14 ימים')),
              PopupMenuItem(value: 30, child: Text('30 ימים')),
            ],
          ),
        ],
      ),
      body: t == null
          ? const Center(child: Text('אין סוגי אירועים'))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final tt in state.visibleTypes) ...[
                        ChoiceChip(
                          avatar: Icon(
                            iconFor(tt.icon),
                            size: 18,
                            color: Color(tt.color),
                          ),
                          label: Text(tt.name),
                          selected: typeId == tt.id,
                          onSelected: (_) {
                            typeId = tt.id;
                            _load();
                          },
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (loading)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  _summaryCard(t),
                  const SizedBox(height: 12),
                  _chartCard(
                    '${t.name} ליום ($days ימים אחרונים)',
                    stats.map((s) => s.count.toDouble()).toList(),
                    Color(t.color),
                  ),
                  if (statField != null || t.isMed) ...[
                    const SizedBox(height: 12),
                    _chartCard(
                      '${t.statAgg == StatAgg.avg ? 'ממוצע' : 'סה"כ'} ${statField?.label ?? 'מינון'} ליום${statField?.unit == null ? '' : ' (${statField!.unit})'}',
                      stats.map((s) => s.value(t.statAgg)).toList(),
                      Color(t.color).withAlpha(170),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'יום נספר מ-${two(state.dayStartHour)}:00 עד ${two(state.dayStartHour)}:00 למחרת (ניתן לשנות בהגדרות).',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _summaryCard(EventType t) {
    final f = statField;
    final perDay = total / days;
    String gap;
    if (avgGapMinutes <= 0) {
      gap = '-';
    } else {
      final h = (avgGapMinutes / 60).floor();
      final m = (avgGapMinutes % 60).round();
      gap = '$h:${two(m)}';
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _stat('סה"כ', '$total'),
            _stat('ממוצע ליום', perDay.toStringAsFixed(1)),
            _stat('מרווח ממוצע', gap),
            if (f != null || t.isMed)
              _stat(
                'ממוצע ${f?.label ?? 'מינון'}',
                '${fmtNum(avgAmount)} ${f?.unit ?? ''}'.trim(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _chartCard(String title, List<double> values, Color color) {
    final maxY = values.isEmpty
        ? 1.0
        : (values.reduce((a, b) => a > b ? a : b) * 1.2).clamp(1.0, 1e9);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 8),
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(
              height: 200,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: BarChart(
                  BarChartData(
                    maxY: maxY,
                    barGroups: [
                      for (var i = 0; i < values.length; i++)
                        BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: values[i],
                              color: color,
                              width: days > 14 ? 6 : 14,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ],
                        ),
                    ],
                    titlesData: FlTitlesData(
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: const AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 32,
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          getTitlesWidget: (v, meta) {
                            final i = v.toInt();
                            if (i < 0 || i >= stats.length) {
                              return const SizedBox.shrink();
                            }
                            if (days > 14 && i % 3 != 0) {
                              return const SizedBox.shrink();
                            }
                            final d = stats[i].day;
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${d.day}.${d.month}',
                                style: const TextStyle(fontSize: 10),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    gridData: const FlGridData(
                      show: true,
                      drawVerticalLine: false,
                    ),
                    borderData: FlBorderData(show: false),
                    barTouchData: BarTouchData(enabled: true),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

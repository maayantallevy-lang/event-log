import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../db/app_db.dart' show describeValues;
import '../models.dart';
import '../util/format.dart';

/// טווח הסטטיסטיקה: יום אחד (לפי שעות), שבוע או חודש (לפי ימים).
enum StatRange { day, week, month }

extension on StatRange {
  int get days => switch (this) {
    StatRange.day => 1,
    StatRange.week => 7,
    StatRange.month => 30,
  };
  String get label => switch (this) {
    StatRange.day => 'יום',
    StatRange.week => 'שבוע',
    StatRange.month => 'חודש',
  };
}

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

/// עמודה אחת בגרף: שעה (בתצוגת יום) או יום (בשבוע/חודש).
class _Bucket {
  final DateTime start;
  int count = 0;
  double sum = 0;
  int n = 0; // כמה ערכים מספריים נספרו (לממוצע)
  _Bucket(this.start);

  double value(String agg) => agg == StatAgg.avg ? (n == 0 ? 0 : sum / n) : sum;
}

class _StatsScreenState extends State<StatsScreen> {
  final state = AppState.instance;
  String? typeId;
  StatRange range = StatRange.week;

  /// כמה טווחים אחורה מהיום (0 = הטווח שמסתיים היום).
  int offset = 0;

  List<_Bucket> buckets = [];
  List<LogEvent> events = [];
  double avgGapMinutes = 0;
  double sumAmount = 0;
  int amountCount = 0;
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
    final v = state.visibleTypes;
    // אחרי מעבר יומן: הסוג הקודם לא שייך ליומן הנוכחי.
    if (!v.any((t) => t.id == typeId)) typeId = v.isEmpty ? null : v.first.id;
    return state.typeById[typeId];
  }

  EventField? get statField {
    final t = type;
    if (t == null || t.isMed) return null;
    for (final f in t.fields) {
      if (f.id == t.statFieldId) return f;
    }
    return null;
  }

  bool get hasAmount => statField != null || (type?.isMed ?? false);

  /// תחילת הטווח המוצג (יום לוגי).
  DateTime get rangeStart {
    final today = logicalDayStart(DateTime.now(), state.dayStartHour);
    final end = today.subtract(Duration(days: offset * range.days));
    return end.subtract(Duration(days: range.days - 1));
  }

  DateTime get rangeEnd => rangeStart.add(Duration(days: range.days));

  Future<void> _load() async {
    final t = type;
    if (t == null) {
      if (mounted) setState(() => loading = false);
      return;
    }
    final from = rangeStart;
    final to = rangeEnd;
    final evs = await state.db.events(
      subjectId: state.subjectId,
      from: from,
      to: to,
      typeIds: {t.id},
    );

    final list = <_Bucket>[];
    if (range == StatRange.day) {
      for (var h = 0; h < 24; h++) {
        list.add(_Bucket(from.add(Duration(hours: h))));
      }
    } else {
      for (var i = 0; i < range.days; i++) {
        list.add(_Bucket(from.add(Duration(days: i))));
      }
    }

    final key = statField?.id;
    double amount = 0;
    int amountN = 0;
    for (final e in evs) {
      if (e.timestamp.isBefore(from) || !e.timestamp.isBefore(to)) continue;
      final int idx = range == StatRange.day
          ? e.timestamp.difference(from).inHours
          // round ולא inDays: ביום של מעבר שעון יש 23 או 25 שעות.
          : (logicalDayStart(
                      e.timestamp,
                      state.dayStartHour,
                    ).difference(from).inHours /
                    24)
                .round();
      if (idx < 0 || idx >= list.length) continue;
      final b = list[idx];
      b.count++;
      final dynamic v = key != null
          ? e.values[key]
          : (t.isMed ? e.values['dose'] : null);
      if (v is num) {
        b.sum += v.toDouble();
        b.n++;
        amount += v.toDouble();
        amountN++;
      }
    }

    // מרווח ממוצע בין אירועים עוקבים (evs ממוינים מהחדש לישן).
    double gaps = 0;
    for (var i = 0; i + 1 < evs.length; i++) {
      gaps += evs[i].timestamp.difference(evs[i + 1].timestamp).inMinutes;
    }
    if (!mounted) return;
    setState(() {
      buckets = list;
      events = evs;
      avgGapMinutes = evs.length > 1 ? gaps / (evs.length - 1) : 0;
      sumAmount = amount;
      amountCount = amountN;
      loading = false;
    });
  }

  void _setRange(StatRange r) {
    range = r;
    offset = 0;
    _load();
  }

  void _shift(int delta) {
    final next = offset + delta;
    if (next < 0) return;
    offset = next;
    _load();
  }

  String get _rangeTitle {
    final today = logicalDayStart(DateTime.now(), state.dayStartHour);
    final s = rangeStart;
    if (range == StatRange.day) return dayTitle(s, today);
    final e = rangeEnd.subtract(const Duration(days: 1));
    final tail = offset == 0 ? ' (עד היום)' : '';
    return '${s.day}.${s.month} - ${e.day}.${e.month}$tail';
  }

  @override
  Widget build(BuildContext context) {
    final t = type;
    return Scaffold(
      appBar: AppBar(title: const Text('סטטיסטיקה')),
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
                SegmentedButton<StatRange>(
                  segments: [
                    for (final r in StatRange.values)
                      ButtonSegment(value: r, label: Text(r.label)),
                  ],
                  selected: {range},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => _setRange(s.first),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'קודם',
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => _shift(1),
                    ),
                    Expanded(
                      child: Text(
                        _rangeTitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'הבא',
                      icon: const Icon(Icons.chevron_left),
                      onPressed: offset == 0 ? null : () => _shift(-1),
                    ),
                  ],
                ),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  _summaryCard(t),
                  const SizedBox(height: 12),
                  _chartCard(
                    range == StatRange.day
                        ? 'כמה פעמים בכל שעה'
                        : 'כמה פעמים בכל יום',
                    buckets.map((b) => b.count.toDouble()).toList(),
                    Color(t.color),
                    integer: true,
                  ),
                  if (hasAmount) ...[
                    const SizedBox(height: 12),
                    _chartCard(
                      '${t.statAgg == StatAgg.avg ? 'ממוצע' : 'סה"כ'} '
                      '${statField?.label ?? 'מינון'}'
                      '${range == StatRange.day ? ' בכל שעה' : ' בכל יום'}'
                      '${statField?.unit == null ? '' : ' (${statField!.unit})'}',
                      buckets.map((b) => b.value(t.statAgg)).toList(),
                      Color(t.color).withAlpha(170),
                      integer: false,
                    ),
                  ],
                  if (range == StatRange.day) ...[
                    const SizedBox(height: 12),
                    _dayList(t),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'יום נספר מ-${two(state.dayStartHour)}:00 עד ${two(state.dayStartHour)}:00 למחרת (ניתן לשנות בהגדרות).',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _summaryCard(EventType t) {
    final f = statField;
    final total = events.length;
    String gap;
    if (avgGapMinutes <= 0) {
      gap = '-';
    } else {
      final h = (avgGapMinutes / 60).floor();
      final m = (avgGapMinutes % 60).round();
      gap = '$h:${two(m)}';
    }
    final unit = f?.unit ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Row(
          children: [
            _stat('סה"כ פעמים', '$total'),
            if (range != StatRange.day)
              _stat('ממוצע ליום', fmtNum(total / range.days)),
            _stat('מרווח ממוצע', gap),
            if (hasAmount && amountCount > 0)
              t.statAgg == StatAgg.avg
                  ? _stat(
                      'ממוצע ${f?.label ?? 'מינון'}',
                      '${fmtNum(sumAmount / amountCount)} $unit'.trim(),
                    )
                  : _stat(
                      'סה"כ ${f?.label ?? 'מינון'}',
                      '${fmtNum(sumAmount)} $unit'.trim(),
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
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// רשימת האירועים של היום הנבחר.
  Widget _dayList(EventType t) {
    final medById = state.medById;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: events.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: Text('אין אירועים ביום הזה')),
              )
            : Column(
                children: [
                  for (final e in events)
                    ListTile(
                      dense: true,
                      leading: Text(
                        fmtTime(e.timestamp),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      title: Text(
                        [
                          describeValues(t, e.values, medById),
                          if ((e.note ?? '').isNotEmpty) e.note!,
                        ].where((s) => s.isNotEmpty).join(' · '),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  /// מרווח "יפה" לקווי הרשת: 1, 2, 5, 10, 20, 50...
  static double _niceStep(double max, {required bool integer}) {
    if (max <= 0) return 1;
    final raw = max / 4;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    double step = mag;
    for (final m in [1.0, 2.0, 2.5, 5.0, 10.0]) {
      step = m * mag;
      if (step >= raw) break;
    }
    if (integer) step = math.max(1, step.ceilToDouble());
    return step;
  }

  Widget _chartCard(
    String title,
    List<double> values,
    Color color, {
    required bool integer,
  }) {
    final maxV = values.isEmpty ? 0.0 : values.reduce(math.max);
    final step = _niceStep(maxV, integer: integer);
    final maxY = math.max(step, (maxV / step).ceil() * step);
    final n = values.length;
    final barWidth = n > 20 ? 6.0 : (n > 10 ? 9.0 : 16.0);
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = TextStyle(fontSize: 11, color: scheme.onSurfaceVariant);

    String bottomLabel(int i) {
      final s = buckets[i].start;
      if (range == StatRange.day) return two(s.hour);
      return '${s.day}.${s.month}';
    }

    bool showBottom(int i) {
      if (range == StatRange.day) return i % 3 == 0;
      if (range == StatRange.month) return i % 5 == 0 || i == n - 1;
      return true;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 12),
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
                    minY: 0,
                    barGroups: [
                      for (var i = 0; i < n; i++)
                        BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: values[i],
                              color: color,
                              width: barWidth,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
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
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 44,
                          interval: step,
                          getTitlesWidget: (v, meta) {
                            // רק על קווי הרשת, בלי שברים מוזרים.
                            final r = v / step;
                            if ((r - r.round()).abs() > 0.001) {
                              return const SizedBox.shrink();
                            }
                            return SideTitleWidget(
                              meta: meta,
                              space: 6,
                              child: Text(
                                integer ? v.round().toString() : fmtNum(v),
                                style: labelStyle,
                                maxLines: 1,
                                softWrap: false,
                              ),
                            );
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 26,
                          interval: 1,
                          getTitlesWidget: (v, meta) {
                            final i = v.toInt();
                            if (i < 0 || i >= n || !showBottom(i)) {
                              return const SizedBox.shrink();
                            }
                            return SideTitleWidget(
                              meta: meta,
                              space: 4,
                              child: Text(
                                bottomLabel(i),
                                style: labelStyle,
                                maxLines: 1,
                                softWrap: false,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: step,
                      getDrawingHorizontalLine: (_) => FlLine(
                        color: scheme.outlineVariant,
                        strokeWidth: 0.8,
                        dashArray: [4, 4],
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    barTouchData: BarTouchData(
                      enabled: true,
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                          '${bottomLabel(group.x)}\n'
                          '${integer ? rod.toY.round() : fmtNum(rod.toY)}',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
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

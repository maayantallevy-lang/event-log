import 'package:flutter/material.dart';

/// עורך תזכורות בסגנון יומן גוגל: רשימת תזכורות "X לפני", הוספה מהירה
/// מתוך הצעות נפוצות, והתאמה אישית (מספר + דקות/שעות/ימים/שבועות).
class ReminderEditor extends StatelessWidget {
  /// דקות לפני האירוע. 0 = בזמן האירוע.
  final List<int> minutes;
  final ValueChanged<List<int>> onChanged;
  final int max;

  const ReminderEditor({
    super.key,
    required this.minutes,
    required this.onChanged,
    this.max = 10,
  });

  static const presets = [0, 10, 30, 60, 120, 1440, 2880, 10080];

  void _add(int m) {
    if (minutes.contains(m) || minutes.length >= max) return;
    onChanged([...minutes, m]..sort());
  }

  void _remove(int m) => onChanged(minutes.where((x) => x != m).toList());

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final available = presets.where((p) => !minutes.contains(p)).toList();
    final full = minutes.length >= max;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (minutes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'אין תזכורות',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        for (final m in minutes)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.notifications_active_outlined),
            title: Text(reminderLabel(m), style: const TextStyle(fontSize: 16)),
            trailing: IconButton(
              tooltip: 'הסרה',
              icon: const Icon(Icons.close),
              onPressed: () => _remove(m),
            ),
          ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (!full)
              for (final p in available.take(4))
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: Text(reminderLabel(p)),
                  onPressed: () => _add(p),
                ),
            if (!full)
              ActionChip(
                avatar: const Icon(Icons.tune, size: 18),
                label: const Text('התאמה אישית'),
                onPressed: () async {
                  final m = await showCustomReminderDialog(context);
                  if (m != null) _add(m);
                },
              ),
          ],
        ),
      ],
    );
  }
}

/// "שעה לפני", "3 ימים לפני", "בזמן האירוע"...
String reminderLabel(int minutes) {
  if (minutes == 0) return 'בזמן התור';
  String unit(int n, String one, String two, String many) {
    if (n == 1) return one;
    if (n == 2) return two;
    return '$n $many';
  }

  final String text;
  if (minutes % 10080 == 0) {
    text = unit(minutes ~/ 10080, 'שבוע', 'שבועיים', 'שבועות');
  } else if (minutes % 1440 == 0) {
    text = unit(minutes ~/ 1440, 'יום', 'יומיים', 'ימים');
  } else if (minutes % 60 == 0) {
    text = unit(minutes ~/ 60, 'שעה', 'שעתיים', 'שעות');
  } else {
    text = '$minutes דקות';
  }
  return '$text לפני';
}

enum _Unit { minutes, hours, days, weeks }

extension on _Unit {
  String get label => switch (this) {
    _Unit.minutes => 'דקות',
    _Unit.hours => 'שעות',
    _Unit.days => 'ימים',
    _Unit.weeks => 'שבועות',
  };
  int get factor => switch (this) {
    _Unit.minutes => 1,
    _Unit.hours => 60,
    _Unit.days => 1440,
    _Unit.weeks => 10080,
  };
}

/// חלון "התאמה אישית": מספר + יחידה. מחזיר דקות או null.
Future<int?> showCustomReminderDialog(BuildContext context) {
  final ctrl = TextEditingController(text: '1');
  var unit = _Unit.hours;
  return showDialog<int>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        int? value() {
          final n = int.tryParse(ctrl.text.trim());
          if (n == null || n < 0 || n > 9999) return null;
          final m = n * unit.factor;
          return m > 60 * 24 * 7 * 8 ? null : m; // עד 8 שבועות
        }

        final v = value();
        return AlertDialog(
          title: const Text('תזכורת בהתאמה אישית'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24),
                decoration: const InputDecoration(border: OutlineInputBorder()),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final u in _Unit.values)
                    ChoiceChip(
                      label: Text(u.label),
                      selected: unit == u,
                      onSelected: (_) => setState(() => unit = u),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                v == null ? 'אפשר עד 8 שבועות לפני' : reminderLabel(v),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ביטול'),
            ),
            FilledButton(
              onPressed: v == null ? null : () => Navigator.pop(context, v),
              child: const Text('הוספה'),
            ),
          ],
        );
      },
    ),
  );
}

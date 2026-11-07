import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../util/format.dart';

/// פותח את פופאפ התיעוד לסוג אירוע. מחזיר את האירוע שנשמר, או null.
/// [existing] = עריכה של אירוע קיים.
Future<LogEvent?> showLogSheet(
  BuildContext context,
  EventType type, {
  LogEvent? existing,
}) {
  return showModalBottomSheet<LogEvent>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _LogSheet(type: type, existing: existing),
    ),
  );
}

class _LogSheet extends StatefulWidget {
  final EventType type;
  final LogEvent? existing;
  const _LogSheet({required this.type, this.existing});

  @override
  State<_LogSheet> createState() => _LogSheetState();
}

class _LogSheetState extends State<_LogSheet> {
  final state = AppState.instance;
  late DateTime when;
  late Map<String, dynamic> values;
  final noteCtrl = TextEditingController();
  final Map<String, TextEditingController> textCtrls = {};
  bool loading = true;
  bool saving = false;

  EventType get type => widget.type;

  @override
  void initState() {
    super.initState();
    when = widget.existing?.timestamp ?? DateTime.now();
    values = Map<String, dynamic>.from(widget.existing?.values ?? {});
    noteCtrl.text = widget.existing?.note ?? '';
    _prefill();
  }

  /// ברירות מחדל: הבחירה הקודמת לשדות עם "זכור אחרון".
  Future<void> _prefill() async {
    if (widget.existing == null) {
      final last = await state.db.lastEventOfType(type.id);
      if (type.isMed) {
        if (last != null && last.values['med_id'] != null) {
          final med = state.medById[last.values['med_id']];
          if (med != null && med.active) {
            values['med_id'] = med.id;
            values['dose'] = med.defaultDose;
          }
        } else {
          final active = state.meds.where((m) => m.active).toList();
          if (active.length == 1) {
            values['med_id'] = active.first.id;
            values['dose'] = active.first.defaultDose;
          }
        }
      } else if (last != null) {
        for (final f in type.fields) {
          if (f.rememberLast && last.values.containsKey(f.id.toString())) {
            values[f.id.toString()] = last.values[f.id.toString()];
          }
        }
      }
    }
    for (final f in type.fields) {
      if (f.kind == FieldKind.text ||
          f.kind == FieldKind.number ||
          f.kind == FieldKind.duration) {
        final v = values[f.id.toString()];
        textCtrls[f.id.toString()] = TextEditingController(
          text: v == null ? '' : (v is num ? fmtNum(v) : v.toString()),
        );
      }
    }
    if (type.isMed) {
      final d = values['dose'];
      textCtrls['dose'] = TextEditingController(
        text: d == null ? '' : fmtNum(d as num),
      );
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    noteCtrl.dispose();
    for (final c in textCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickTime() async {
    final d = await showDatePicker(
      context: context,
      initialDate: when,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(when),
    );
    if (t == null) return;
    setState(() => when = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  String? _validate() {
    if (type.isMed) {
      if (values['med_id'] == null) return 'בחר תרופה';
      return null;
    }
    for (final f in type.fields) {
      if (!f.required) continue;
      final v = values[f.id.toString()];
      if (v == null ||
          (v is List && v.isEmpty) ||
          (v is String && v.trim().isEmpty)) {
        return 'חסר: ${f.label}';
      }
    }
    return null;
  }

  Future<void> _save() async {
    // קריאת שדות טקסט/מספר מהבקרים.
    for (final f in type.fields) {
      final c = textCtrls[f.id.toString()];
      if (c == null) continue;
      final raw = c.text.trim();
      if (f.kind == FieldKind.text) {
        if (raw.isEmpty) {
          values.remove(f.id.toString());
        } else {
          values[f.id.toString()] = raw;
        }
      } else {
        final n = double.tryParse(raw.replaceAll(',', '.'));
        if (n == null) {
          values.remove(f.id.toString());
        } else {
          values[f.id.toString()] = f.kind == FieldKind.duration
              ? n.round()
              : n;
        }
      }
    }
    if (type.isMed) {
      final n = double.tryParse(textCtrls['dose']!.text.trim());
      if (n == null) {
        values.remove('dose');
      } else {
        values['dose'] = n;
      }
    }
    final err = _validate();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    setState(() => saving = true);
    final e = LogEvent(
      id: widget.existing?.id ?? 0,
      babyId: state.baby?.id ?? 1,
      typeId: type.id,
      timestamp: when,
      values: values,
      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
    );
    final id = await state.saveEvent(e);
    if (!mounted) return;
    Navigator.of(context).pop(
      LogEvent(
        id: id,
        babyId: e.babyId,
        typeId: e.typeId,
        timestamp: e.timestamp,
        values: e.values,
        note: e.note,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(type.color);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: color,
                child: Icon(iconFor(type.icon), color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.existing == null ? type.name : 'עריכה: ${type.name}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _timeRow(),
          const Divider(height: 24),
          if (loading)
            const Center(child: CircularProgressIndicator())
          else if (type.isMed)
            ..._medFields()
          else
            for (final f in type.fields) _fieldWidget(f),
          const SizedBox(height: 8),
          TextField(
            controller: noteCtrl,
            decoration: const InputDecoration(
              labelText: 'הערה',
              border: OutlineInputBorder(),
            ),
            minLines: 1,
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: color,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.check),
            label: Text(
              widget.existing == null ? 'שמור' : 'עדכן',
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeRow() {
    final now = DateTime.now();
    final isNow = now.difference(when).inMinutes.abs() < 1;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ActionChip(
          avatar: const Icon(Icons.schedule, size: 18),
          label: Text(isNow ? 'עכשיו' : fmtDateTime(when)),
          onPressed: _pickTime,
        ),
        for (final m in [5, 15, 30])
          ActionChip(
            label: Text('-$m דק\''),
            onPressed: () =>
                setState(() => when = when.subtract(Duration(minutes: m))),
          ),
        if (!isNow)
          ActionChip(
            label: const Text('עכשיו'),
            onPressed: () => setState(() => when = DateTime.now()),
          ),
      ],
    );
  }

  List<Widget> _medFields() {
    final active = state.meds.where((m) => m.active).toList();
    if (active.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('אין תרופות מוגדרות. הוסף תרופה בהגדרות > תרופות.'),
        ),
      ];
    }
    final selected = values['med_id'];
    final med = state.medById[selected];
    return [
      _label('איזו תרופה?'),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final m in active)
            ChoiceChip(
              label: Text(m.name),
              selected: selected == m.id,
              onSelected: (_) => setState(() {
                values['med_id'] = m.id;
                if (m.defaultDose != null) {
                  textCtrls['dose']!.text = fmtNum(m.defaultDose!);
                }
              }),
            ),
        ],
      ),
      const SizedBox(height: 12),
      _numberInput(textCtrls['dose']!, 'מינון', med?.unit, step: 0.5),
    ];
  }

  Widget _label(String s) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 6),
    child: Text(s, style: Theme.of(context).textTheme.titleMedium),
  );

  Widget _fieldWidget(EventField f) {
    final key = f.id.toString();
    switch (f.kind) {
      case FieldKind.single:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(f.label),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final o in f.options.where((o) => !o.hidden))
                  ChoiceChip(
                    label: Text(o.label),
                    selected: values[key] == o.id,
                    selectedColor: o.color == null
                        ? null
                        : Color(o.color!).withAlpha(90),
                    onSelected: (sel) => setState(() {
                      if (sel) {
                        values[key] = o.id;
                      } else {
                        values.remove(key);
                      }
                    }),
                  ),
              ],
            ),
          ],
        );
      case FieldKind.multi:
        final sel = ((values[key] as List?) ?? const []).cast<int>().toSet();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(f.label),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final o in f.options.where((o) => !o.hidden))
                  FilterChip(
                    label: Text(o.label),
                    selected: sel.contains(o.id),
                    selectedColor: o.color == null
                        ? null
                        : Color(o.color!).withAlpha(90),
                    onSelected: (s) => setState(() {
                      if (s) {
                        sel.add(o.id);
                      } else {
                        sel.remove(o.id);
                      }
                      values[key] = sel.toList();
                    }),
                  ),
              ],
            ),
          ],
        );
      case FieldKind.number:
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _numberInput(textCtrls[key]!, f.label, f.unit, step: 10),
        );
      case FieldKind.duration:
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _numberInput(textCtrls[key]!, f.label, 'דקות', step: 5),
        );
      case FieldKind.text:
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextField(
            controller: textCtrls[key],
            decoration: InputDecoration(
              labelText: f.label,
              border: const OutlineInputBorder(),
            ),
            minLines: 1,
            maxLines: 3,
          ),
        );
      case FieldKind.boolean:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(f.label),
          value: values[key] == true,
          onChanged: (v) => setState(() => values[key] = v),
        );
    }
    return const SizedBox.shrink();
  }

  Widget _numberInput(
    TextEditingController c,
    String label,
    String? unit, {
    required double step,
  }) {
    void add(double d) {
      final cur = double.tryParse(c.text.trim()) ?? 0;
      final next = (cur + d).clamp(0, 100000);
      c.text = fmtNum(next);
    }

    return Row(
      children: [
        IconButton.outlined(
          onPressed: () => add(-step),
          icon: const Icon(Icons.remove),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              labelText: label,
              suffixText: unit,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 6),
        IconButton.outlined(
          onPressed: () => add(step),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../util/format.dart';
import '../util/ids.dart';

class MedsScreen extends StatefulWidget {
  const MedsScreen({super.key});

  @override
  State<MedsScreen> createState() => _MedsScreenState();
}

class _MedsScreenState extends State<MedsScreen> {
  final state = AppState.instance;

  @override
  void initState() {
    super.initState();
    state.addListener(_refresh);
  }

  @override
  void dispose() {
    state.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _edit(Med? existing) async {
    final result = await showDialog<Med>(
      context: context,
      builder: (_) => _MedDialog(existing: existing),
    );
    if (result == null) return;
    await state.db.saveMed(result);
    await state.reloadStructure();
  }

  @override
  Widget build(BuildContext context) {
    final meds = state.meds.where((m) => m.active).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('תרופות')),
      body: meds.isEmpty
          ? const Center(child: Text('אין תרופות. לחץ + כדי להוסיף.'))
          : ListView(
              children: [
                for (final m in meds)
                  ListTile(
                    leading: const Icon(Icons.medication),
                    title: Text(m.name),
                    subtitle: Text(
                      [
                        if (m.defaultDose != null)
                          '${fmtNum(m.defaultDose!)} ${m.unit ?? ''}'.trim(),
                        if (m.intervalHours != null)
                          'כל ${fmtNum(m.intervalHours!)} שעות',
                      ].join(' · '),
                    ),
                    onTap: () => _edit(m),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await state.db.deactivateMed(m);
                        await state.reloadStructure();
                      },
                    ),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(null),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _MedDialog extends StatefulWidget {
  final Med? existing;
  const _MedDialog({this.existing});

  @override
  State<_MedDialog> createState() => _MedDialogState();
}

class _MedDialogState extends State<_MedDialog> {
  late final TextEditingController name;
  late final TextEditingController dose;
  late final TextEditingController interval;
  String unit = 'מ"ל';

  static const units = ['מ"ל', 'טיפות', 'מ"ג', 'כפית', 'יחידה'];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    name = TextEditingController(text: e?.name ?? '');
    dose = TextEditingController(
      text: e?.defaultDose == null ? '' : fmtNum(e!.defaultDose!),
    );
    interval = TextEditingController(
      text: e?.intervalHours == null ? '' : fmtNum(e!.intervalHours!),
    );
    if (e?.unit != null && units.contains(e!.unit)) unit = e.unit!;
  }

  @override
  void dispose() {
    name.dispose();
    dose.dispose();
    interval.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'תרופה חדשה' : 'עריכת תרופה'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'שם'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: dose,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'מינון רגיל'),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: unit,
                  items: [
                    for (final u in units)
                      DropdownMenuItem(value: u, child: Text(u)),
                  ],
                  onChanged: (v) => setState(() => unit = v ?? unit),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: interval,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'תזכורת כל כמה שעות (ריק = בלי)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ביטול'),
        ),
        FilledButton(
          onPressed: () {
            final n = name.text.trim();
            if (n.isEmpty) return;
            Navigator.pop(
              context,
              Med(
                id: widget.existing?.id ?? newId(),
                name: n,
                defaultDose: double.tryParse(dose.text.trim()),
                unit: unit,
                intervalHours: double.tryParse(interval.text.trim()),
                active: true,
                subjectId:
                    widget.existing?.subjectId ?? AppState.instance.subjectId,
              ),
            );
          },
          child: const Text('שמור'),
        ),
      ],
    );
  }
}

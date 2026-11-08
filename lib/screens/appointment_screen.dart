import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../util/format.dart';
import '../util/ids.dart';
import '../widgets/reminder_editor.dart';

/// פותח מסך הוספה/עריכה של תור. [existing] null = תור חדש.
Future<void> openAppointment(
  BuildContext context,
  Appointment? existing, {
  String? titleHint,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) =>
          AppointmentScreen(existing: existing, titleHint: titleHint),
    ),
  );
}

class AppointmentScreen extends StatefulWidget {
  final Appointment? existing;
  final String? titleHint;
  const AppointmentScreen({super.key, this.existing, this.titleHint});

  @override
  State<AppointmentScreen> createState() => _AppointmentScreenState();
}

class _AppointmentScreenState extends State<AppointmentScreen> {
  final state = AppState.instance;
  final titleCtrl = TextEditingController();
  final locationCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  final summaryCtrl = TextEditingController();
  String category = AppointmentCategory.all.first;
  late DateTime when;
  List<int> remind = []; // דקות לפני, ממוין

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      titleCtrl.text = e.title;
      locationCtrl.text = e.location ?? '';
      noteCtrl.text = e.note ?? '';
      summaryCtrl.text = e.summary ?? '';
      category = e.category;
      when = e.scheduledAt;
      remind = [...e.remindBeforeMin]..sort();
    } else {
      titleCtrl.text = widget.titleHint ?? '';
      final now = DateTime.now().add(const Duration(days: 1));
      when = DateTime(now.year, now.month, now.day, 9, 0);
      remind = [60, 1440];
    }
  }

  @override
  void dispose() {
    titleCtrl.dispose();
    locationCtrl.dispose();
    noteCtrl.dispose();
    summaryCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: when,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (d == null) return;
    setState(
      () => when = DateTime(d.year, d.month, d.day, when.hour, when.minute),
    );
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(when),
    );
    if (t == null) return;
    setState(
      () => when = DateTime(when.year, when.month, when.day, t.hour, t.minute),
    );
  }

  Future<void> _save() async {
    var title = titleCtrl.text.trim();
    if (title.isEmpty) title = category;
    final a = Appointment(
      id: widget.existing?.id ?? newId(),
      subjectId: widget.existing?.subjectId ?? state.subjectId,
      title: title,
      category: category,
      scheduledAt: when,
      location: locationCtrl.text.trim().isEmpty
          ? null
          : locationCtrl.text.trim(),
      remindBeforeMin: [...remind],
      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      summary: summaryCtrl.text.trim().isEmpty ? null : summaryCtrl.text.trim(),
      done: widget.existing?.done ?? false,
      followUpAsked: widget.existing?.followUpAsked ?? false,
    );
    await state.saveAppointment(a);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('למחוק את התור?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('ביטול'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('מחק'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await state.deleteAppointment(widget.existing!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isPast = when.isBefore(DateTime.now());
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'תור חדש' : 'עריכת תור'),
        actions: [
          if (widget.existing != null)
            IconButton(onPressed: _delete, icon: const Icon(Icons.delete)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final c in AppointmentCategory.all)
                ChoiceChip(
                  label: Text(c),
                  selected: category == c,
                  onSelected: (_) => setState(() {
                    category = c;
                    if (titleCtrl.text.trim().isEmpty ||
                        AppointmentCategory.all.contains(
                          titleCtrl.text.trim(),
                        )) {
                      titleCtrl.text = c;
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: titleCtrl,
            decoration: const InputDecoration(
              labelText: 'כותרת',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today),
                  label: Text('${weekdayName(when)} ${fmtDate(when)}'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.access_time),
                label: Text(fmtTime(when)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: locationCtrl,
            decoration: const InputDecoration(
              labelText: 'מקום',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          const Text('תזכורות', style: TextStyle(fontWeight: FontWeight.bold)),
          ReminderEditor(
            minutes: remind,
            onChanged: (v) => setState(() => remind = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteCtrl,
            decoration: const InputDecoration(
              labelText: 'הערה (מה להביא, מה לשאול)',
              border: OutlineInputBorder(),
            ),
            minLines: 1,
            maxLines: 4,
          ),
          if (isPast) ...[
            const SizedBox(height: 12),
            TextField(
              controller: summaryCtrl,
              decoration: const InputDecoration(
                labelText: 'סיכום אחרי התור',
                border: OutlineInputBorder(),
              ),
              minLines: 1,
              maxLines: 4,
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('שמור', style: TextStyle(fontSize: 18)),
          ),
        ],
      ),
    );
  }
}

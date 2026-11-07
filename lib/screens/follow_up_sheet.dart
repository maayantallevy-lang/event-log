import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'appointment_screen.dart';

/// שאלון קצר אחרי תור: סיכום, מרשם, הפניה, תור המשך.
/// כל "כן" יוצר משימת מעקב שמתזכרת פעם ביום עד שמסמנים "בוצע".
Future<void> showFollowUpSheet(BuildContext context, Appointment a) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _FollowUpSheet(appointment: a),
    ),
  );
}

class _FollowUpSheet extends StatefulWidget {
  final Appointment appointment;
  const _FollowUpSheet({required this.appointment});

  @override
  State<_FollowUpSheet> createState() => _FollowUpSheetState();
}

class _FollowUpSheetState extends State<_FollowUpSheet> {
  final state = AppState.instance;
  final summaryCtrl = TextEditingController();
  final medCtrl = TextEditingController();
  final referralCtrl = TextEditingController();
  bool? gotPrescription;
  bool? gotReferral;
  bool? needsNext;
  bool addMedToList = true;
  bool saving = false;

  @override
  void dispose() {
    summaryCtrl.dispose();
    medCtrl.dispose();
    referralCtrl.dispose();
    super.dispose();
  }

  Future<void> _finish({bool skip = false}) async {
    setState(() => saving = true);
    final a = widget.appointment;
    a.followUpAsked = true;
    a.done = true;
    if (!skip && summaryCtrl.text.trim().isNotEmpty) {
      a.summary = summaryCtrl.text.trim();
    }
    await state.saveAppointment(a);

    if (!skip) {
      if (gotPrescription == true) {
        final name = medCtrl.text.trim();
        await state.addFollowUp(
          FollowUp(
            id: 0,
            appointmentId: a.id,
            kind: FollowUpKind.buyMed,
            title: name.isEmpty ? 'לקנות את התרופה מהמרשם' : 'לקנות: $name',
            createdAt: DateTime.now(),
          ),
        );
        if (addMedToList && name.isNotEmpty) {
          final exists = state.meds.any(
            (m) => m.name.trim().toLowerCase() == name.toLowerCase(),
          );
          if (!exists) {
            await state.db.insertMed(Med(id: 0, name: name));
            await state.load();
          }
        }
      }
      if (gotReferral == true) {
        final what = referralCtrl.text.trim();
        await state.addFollowUp(
          FollowUp(
            id: 0,
            appointmentId: a.id,
            kind: FollowUpKind.bookAppointment,
            title: what.isEmpty ? 'לקבוע תור לפי ההפניה' : 'לקבוע תור: $what',
            createdAt: DateTime.now(),
          ),
        );
      }
    }
    if (!mounted) return;
    Navigator.pop(context);
    if (!skip && needsNext == true) {
      await openAppointment(context, null, titleHint: a.title);
    }
  }

  Widget _yesNo(String q, bool? value, void Function(bool) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Expanded(child: Text(q, style: const TextStyle(fontSize: 16))),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('כן')),
              ButtonSegment(value: false, label: Text('לא')),
            ],
            selected: value == null ? {} : {value},
            emptySelectionAllowed: true,
            onSelectionChanged: (s) {
              if (s.isNotEmpty) onChanged(s.first);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'איך היה בתור "${a.title}"?',
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
          TextField(
            controller: summaryCtrl,
            decoration: const InputDecoration(
              labelText: 'סיכום קצר (משקל, מה נאמר...)',
              border: OutlineInputBorder(),
            ),
            minLines: 1,
            maxLines: 4,
          ),
          _yesNo(
            'קיבלת מרשם?',
            gotPrescription,
            (v) => setState(() => gotPrescription = v),
          ),
          if (gotPrescription == true) ...[
            const SizedBox(height: 8),
            TextField(
              controller: medCtrl,
              decoration: const InputDecoration(
                labelText: 'שם התרופה',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: addMedToList,
              onChanged: (v) => setState(() => addMedToList = v ?? true),
              title: const Text('הוסף לרשימת התרופות שלי'),
            ),
          ],
          _yesNo(
            'קיבלת הפניה?',
            gotReferral,
            (v) => setState(() => gotReferral = v),
          ),
          if (gotReferral == true) ...[
            const SizedBox(height: 8),
            TextField(
              controller: referralCtrl,
              decoration: const InputDecoration(
                labelText: 'למה? (בדיקת דם, אולטרסאונד, מומחה...)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          _yesNo(
            'צריך תור המשך?',
            needsNext,
            (v) => setState(() => needsNext = v),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: saving ? null : () => _finish(),
            icon: const Icon(Icons.check),
            label: const Text('סיים', style: TextStyle(fontSize: 18)),
          ),
          TextButton(
            onPressed: saving ? null : () => _finish(skip: true),
            child: const Text('דלג, בלי מעקב'),
          ),
        ],
      ),
    );
  }
}

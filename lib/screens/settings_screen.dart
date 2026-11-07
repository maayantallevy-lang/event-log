import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../util/format.dart';
import 'event_types_screen.dart';
import 'meds_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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

  Future<void> _editBaby() async {
    final baby = state.baby;
    if (baby == null) return;
    final ctrl = TextEditingController(text: baby.name);
    DateTime? birth = baby.birthDate;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: const Text('התינוק/ת'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(labelText: 'שם'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.cake),
                label: Text(
                  birth == null ? 'תאריך לידה' : 'נולד/ה ${fmtDate(birth!)}',
                ),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: c,
                    initialDate: birth ?? DateTime.now(),
                    firstDate: DateTime.now().subtract(
                      const Duration(days: 365 * 3),
                    ),
                    lastDate: DateTime.now(),
                  );
                  if (d != null) setS(() => birth = d);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('ביטול'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('שמור'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await state.db.updateBaby(
        baby.id,
        ctrl.text.trim().isEmpty ? baby.name : ctrl.text.trim(),
        birth,
      );
      await state.load();
    }
  }

  Future<void> _editDayStart() async {
    final v = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('מאיזו שעה מתחיל "יום"?'),
        children: [
          for (final h in [0, 5, 6, 7, 8])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, h),
              child: Text(h == 0 ? 'חצות (יום קלנדרי)' : '${two(h)}:00'),
            ),
        ],
      ),
    );
    if (v == null) return;
    await state.db.setSetting('day_start_hour', '$v');
    await state.load();
  }

  Future<void> _export() async {
    final csv = await state.db.exportCsv(state.types, state.meds);
    final dir = await getTemporaryDirectory();
    final now = DateTime.now();
    final file = File(
      '${dir.path}/baby-log-${now.year}${two(now.month)}${two(now.day)}.csv',
    );
    await file.writeAsString(csv);
    await Share.shareXFiles([
      XFile(file.path, mimeType: 'text/csv'),
    ], subject: 'יומן תינוק - ייצוא');
  }

  @override
  Widget build(BuildContext context) {
    final baby = state.baby;
    return Scaffold(
      appBar: AppBar(title: const Text('הגדרות')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.child_care),
            title: Text(baby?.name ?? ''),
            subtitle: Text(
              baby?.birthDate == null
                  ? 'הוסף תאריך לידה'
                  : 'נולד/ה ${fmtDate(baby!.birthDate!)} · ${ageText(baby.birthDate!)}',
            ),
            onTap: _editBaby,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.grid_view),
            title: const Text('סוגי אירועים וכפתורים'),
            subtitle: const Text('שם, אייקון, צבע, השאלות והאפשרויות בפופאפ'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EventTypesScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.medication),
            title: const Text('תרופות'),
            subtitle: Text(
              '${state.meds.where((m) => m.active).length} תרופות פעילות',
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MedsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.wb_twilight),
            title: const Text('תחילת יום'),
            subtitle: Text(
              state.dayStartHour == 0
                  ? 'חצות'
                  : '${two(state.dayStartHour)}:00 (לילה נספר ביום שלפניו)',
            ),
            onTap: _editDayStart,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.file_download),
            title: const Text('ייצוא ל-CSV'),
            subtitle: const Text('לשליחה לרופא או לגיבוי'),
            onTap: _export,
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'יומן תינוק הוא כלי לתיעוד בלבד. הוא אינו מכשיר רפואי ואינו נותן ייעוץ על מינונים או טיפול. בכל שאלה רפואית פנו לרופא/ה או לטיפת חלב.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../db/templates.dart';
import '../models.dart';
import '../services/drive_sync.dart';
import '../util/format.dart';

/// מסך פתיחה: (1) איפה לשמור את הנתונים, (2) תבנית ושם ליומן.
/// במצב דרייב, אם כבר יש יומן בחשבון (טלפון נוסף / התקנה מחדש) -
/// הנתונים יורדים מהדרייב ושלב 2 מדולג.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final state = AppState.instance;
  int step = 0;
  bool busy = false;
  String? error;
  Template selected = templates.first;
  final nameCtrl = TextEditingController();
  DateTime? startDate;

  @override
  void dispose() {
    nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _chooseLocal() async {
    await state.db.setSetting('storage_mode', StorageMode.local);
    setState(() => step = 1);
  }

  Future<void> _chooseDrive() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await state.sync.connect();
      await state.sync.sync();
      final err = state.sync.status.value.error;
      if (err != null) throw SyncError(err);
      await state.load();
      if (state.isSetUp) {
        // יומן קיים הגיע מהדרייב - סיימנו.
        await state.rescheduleEverything();
        return;
      }
      if (mounted) setState(() => step = 1);
    } catch (e) {
      if (mounted) setState(() => error = 'ההתחברות לדרייב נכשלה: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _restoreFromFile() async {
    final res = await FilePicker.platform.pickFiles(withData: true);
    final bytes = res?.files.single.bytes;
    if (bytes == null) return;
    try {
      final snap = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      await state.db.setSetting('storage_mode', StorageMode.local);
      await state.db.merge(snap);
      await state.onRemoteChanges();
      if (!state.isSetUp && mounted) setState(() => step = 1);
    } catch (e) {
      if (mounted) setState(() => error = 'הקובץ לא נקרא: $e');
    }
  }

  Future<void> _create() async {
    setState(() => busy = true);
    final s = await state.db.createFromTemplate(
      selected,
      name: nameCtrl.text.trim(),
    );
    if (startDate != null && selected.startKind != null) {
      await state.db.saveSubject(
        Subject(
          id: s.id,
          name: s.name,
          startKind: selected.startKind,
          startDate: startDate,
        ),
      );
    }
    await state.load();
    state.sync.requestSync();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: step == 0 ? _storageStep() : _templateStep(),
        ),
      ),
    );
  }

  Widget _storageStep() {
    return ListView(
      key: const ValueKey('storage'),
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 24),
        Text(
          'יומן אירועים',
          style: Theme.of(context).textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'תיעוד מהיר של כל דבר שצריך לעקוב אחריו.\nאיפה לשמור את הנתונים?',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        _choice(
          icon: Icons.phone_android,
          title: 'רק בטלפון',
          body:
              'הנתונים לא יוצאים מהטלפון. גיבוי ידני לקובץ מההגדרות. '
              'מחיקת האפליקציה בלי גיבוי = מחיקת הנתונים.',
          onTap: busy ? null : _chooseLocal,
        ),
        const SizedBox(height: 12),
        _choice(
          icon: Icons.cloud_sync,
          title: 'בגוגל דרייב שלי',
          body:
              'סנכרון אוטומטי. כל טלפון שמחובר לאותו חשבון גוגל רואה ומעדכן '
              'את אותו יומן. האפליקציה רואה רק את התיקייה שהיא יצרה.',
          onTap: busy ? null : _chooseDrive,
        ),
        if (busy) ...[
          const SizedBox(height: 20),
          const Center(child: CircularProgressIndicator()),
        ],
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(error!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: busy ? null : _restoreFromFile,
          icon: const Icon(Icons.restore),
          label: const Text('יש לי קובץ גיבוי - שחזור'),
        ),
      ],
    );
  }

  Widget _choice({
    required IconData icon,
    required String title,
    required String body,
    required VoidCallback? onTap,
  }) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 40),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(body),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _templateStep() {
    return ListView(
      key: const ValueKey('template'),
      padding: const EdgeInsets.all(20),
      children: [
        Text('מה מתעדים?', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        const Text('התבנית היא רק התחלה - כל כפתור ושאלה ניתנים לעריכה.'),
        const SizedBox(height: 12),
        for (final t in templates)
          RadioListTile<Template>(
            value: t,
            groupValue: selected,
            onChanged: (v) => setState(() {
              selected = v ?? selected;
              startDate = null;
            }),
            title: Text(t.title),
            subtitle: Text(t.description),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: nameCtrl,
          decoration: InputDecoration(
            labelText: 'שם היומן',
            hintText: selected.subjectName,
            border: const OutlineInputBorder(),
          ),
        ),
        if (selected.startKind != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today),
            label: Text(
              startDate == null
                  ? '${StartKind.label(selected.startKind)} (לא חובה)'
                  : '${StartKind.label(selected.startKind)}: ${fmtDate(startDate!)}',
            ),
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
              );
              if (d != null) setState(() => startDate = d);
            },
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: busy ? null : _create,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text('יאללה, מתחילים', style: TextStyle(fontSize: 18)),
        ),
      ],
    );
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/drive_sync.dart';
import '../util/format.dart';
import '../widgets/journal_picker.dart';
import 'appearance_screen.dart';
import 'event_types_screen.dart';
import 'meds_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final state = AppState.instance;
  String mode = StorageMode.local;

  @override
  void initState() {
    super.initState();
    state.addListener(_refresh);
    _loadMode();
  }

  @override
  void dispose() {
    state.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
    _loadMode();
  }

  Future<void> _loadMode() async {
    final m = await state.sync.mode;
    if (mounted && m != mode) setState(() => mode = m);
  }

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  // ---------- נושא היומן ----------

  Future<void> _editSubject() async {
    final subj = state.subject;
    if (subj == null) return;
    final ctrl = TextEditingController(text: subj.name);
    DateTime? start = subj.startDate;
    String? kind = subj.startKind;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: const Text('נושא היומן'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(
                    labelText: 'שם (על מי / על מה מתעדים)',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'תאריך התחלה'),
                  items: [
                    for (final k in [null, ...StartKind.all])
                      DropdownMenuItem(
                        value: k,
                        child: Text(StartKind.label(k)),
                      ),
                  ],
                  onChanged: (v) => setS(() => kind = v),
                ),
                if (kind != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today),
                    label: Text(start == null ? 'בחר תאריך' : fmtDate(start!)),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: c,
                        initialDate: start ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (d != null) setS(() => start = d);
                    },
                  ),
                ],
              ],
            ),
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
    if (ok != true) return;
    await state.saveSubject(
      Subject(
        id: subj.id,
        name: ctrl.text.trim().isEmpty ? subj.name : ctrl.text.trim(),
        startKind: kind,
        startDate: kind == null ? null : start,
        template: subj.template,
        sortOrder: subj.sortOrder,
      ),
    );
  }

  Future<void> _deleteJournal() async {
    final subj = state.subject;
    if (subj == null || !state.hasManyJournals) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('למחוק את היומן "${subj.name}"?'),
        content: const Text(
          'כל האירועים, התורים, התרופות והכפתורים של היומן הזה יימחקו, '
          'גם מהטלפונים האחרים שמסונכרנים. היומנים האחרים לא ייפגעו.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('ביטול'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(c).colorScheme.error,
              foregroundColor: Theme.of(c).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('מחיקה'),
          ),
        ],
      ),
    );
    if (ok == true) await state.deleteJournal(subj);
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

  // ---------- אחסון וסנכרון ----------

  Future<void> _connectDrive() async {
    try {
      final email = await state.sync.connect();
      await state.sync.sync();
      _snack('מחובר לדרייב של $email');
    } catch (e) {
      _snack('ההתחברות נכשלה: $e');
    }
    _loadMode();
  }

  Future<void> _disconnectDrive() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('להפסיק לסנכרן?'),
        content: const Text(
          'הנתונים נשארים בטלפון וגם בדרייב, אבל שינויים חדשים לא יסונכרנו.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('ביטול'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('הפסק סנכרון'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await state.sync.disconnect();
    _loadMode();
  }

  // ---------- גיבוי ----------

  Future<File> _tempFile(String name) async {
    final dir = await getTemporaryDirectory();
    return File('${dir.path}/$name');
  }

  String _stamp() {
    final n = DateTime.now();
    return '${n.year}${two(n.month)}${two(n.day)}-${two(n.hour)}${two(n.minute)}';
  }

  Future<void> _exportBackup() async {
    final f = await _tempFile('event-log-backup-${_stamp()}.json');
    await f.writeAsString(jsonEncode(await state.db.snapshot()));
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(f.path, mimeType: 'application/json')],
        subject: 'יומנון - גיבוי',
      ),
    );
  }

  Future<void> _importBackup() async {
    final res = await FilePicker.platform.pickFiles(withData: true);
    final bytes = res?.files.single.bytes;
    if (bytes == null) return;
    try {
      final snap = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final n = await state.db.merge(snap);
      await state.onRemoteChanges();
      state.sync.requestSync();
      _snack('שוחזרו $n רשומות');
    } catch (e) {
      _snack('הקובץ לא נקרא: $e');
    }
  }

  Future<void> _exportCsv() async {
    final f = await _tempFile('event-log-${_stamp()}.csv');
    await f.writeAsString(await state.db.exportCsv(state.types, state.meds));
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(f.path, mimeType: 'text/csv')],
        subject: 'יומנון - ייצוא',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subj = state.subject;
    return Scaffold(
      appBar: AppBar(title: const Text('הגדרות')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.bookmark),
            title: Text(subj?.name ?? ''),
            subtitle: Text(
              subj?.startDate == null
                  ? 'שם ותאריך התחלה'
                  : '${StartKind.label(subj!.startKind)}: ${fmtDate(subj.startDate!)} · ${elapsedText(subj.startDate!, subj.startKind)}',
            ),
            onTap: _editSubject,
          ),
          ListTile(
            leading: const Icon(Icons.library_books_outlined),
            title: const Text('היומנים שלי'),
            subtitle: Text(
              state.hasManyJournals
                  ? '${state.subjects.length} יומנים · מעבר ויומן חדש'
                  : 'יומן חדש: תינוק, הריון, תרופות - כל אחד בנפרד',
            ),
            onTap: () => showJournalPicker(context),
          ),
          if (state.hasManyJournals)
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'מחיקת היומן "${subj?.name ?? ''}"',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: _deleteJournal,
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
            leading: const Icon(Icons.palette_outlined),
            title: const Text('מראה'),
            subtitle: Text(
              '${state.appearance.value.skin.label} · ${state.appearance.value.font.label}',
            ),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AppearanceScreen()),
              );
              if (mounted) setState(() {});
            },
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
          _storageSection(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.save_alt),
            title: const Text('גיבוי לקובץ'),
            subtitle: const Text('כל הנתונים בקובץ אחד (לשמירה או להעברה)'),
            onTap: _exportBackup,
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('שחזור מקובץ גיבוי'),
            subtitle: const Text('ממזג עם מה שכבר יש - לא מוחק כלום'),
            onTap: _importBackup,
          ),
          ListTile(
            leading: const Icon(Icons.table_view),
            title: const Text('ייצוא ל-CSV'),
            subtitle: const Text('טבלה לשליחה לרופא או לאקסל'),
            onTap: _exportCsv,
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'יומנון הוא כלי לתיעוד בלבד. הוא אינו מכשיר רפואי ואינו נותן ייעוץ על מינונים או טיפול. בכל שאלה רפואית פנו לרופא/ה.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _storageSection() {
    if (mode != StorageMode.drive) {
      return ListTile(
        leading: const Icon(Icons.phone_android),
        title: const Text('הנתונים שמורים רק בטלפון'),
        subtitle: const Text('הקש כדי לסנכרן לגוגל דרייב'),
        trailing: const Icon(Icons.cloud_upload_outlined),
        onTap: _connectDrive,
      );
    }
    return ValueListenableBuilder<SyncStatus>(
      valueListenable: state.sync.status,
      builder: (context, st, _) => Column(
        children: [
          ListTile(
            leading: Icon(
              st.error != null ? Icons.cloud_off : Icons.cloud_done,
              color: st.error != null ? Colors.orange : Colors.green,
            ),
            title: Text('מסונכרן לדרייב: ${st.account ?? ''}'),
            subtitle: Text(
              st.syncing
                  ? 'מסנכרן...'
                  : st.error ??
                        (st.lastSync == null
                            ? 'עוד לא סונכרן'
                            : 'סנכרון אחרון: ${fmtDateTime(st.lastSync!)}'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: st.syncing ? null : () => state.sync.sync(),
                    icon: const Icon(Icons.sync),
                    label: const Text('סנכרן עכשיו'),
                  ),
                ),
                const SizedBox(width: 8),
                if (st.error != null)
                  OutlinedButton(
                    onPressed: _connectDrive,
                    child: const Text('התחבר מחדש'),
                  ),
                TextButton(
                  onPressed: _disconnectDrive,
                  child: const Text('הפסק'),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'כל טלפון שמחובר לאותו חשבון גוגל רואה ומעדכן את אותו יומן. '
              'הנתונים בתיקייה "יומנון - נתונים" בדרייב.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

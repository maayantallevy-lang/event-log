import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../db/templates.dart';
import '../util/format.dart';
import '../util/ids.dart';

/// רשימת סוגי האירועים (הכפתורים): סדר, הוספה, עריכה, הסתרה.
class EventTypesScreen extends StatefulWidget {
  const EventTypesScreen({super.key});

  @override
  State<EventTypesScreen> createState() => _EventTypesScreenState();
}

class _EventTypesScreenState extends State<EventTypesScreen> {
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

  Future<void> _addType() async {
    final t = EventType(
      id: newId(),
      name: '',
      icon: 'star',
      color: palette[state.types.length % palette.length],
      sortOrder: state.types.length,
    );
    final saved = await showDialog<EventType>(
      context: context,
      builder: (_) => _TypeDialog(type: t),
    );
    if (saved == null) return;
    await state.db.saveEventType(saved);
    await state.reloadStructure();
    if (!mounted) return;
    final full = state.typeById[saved.id];
    if (full != null) _open(full);
  }

  /// הוספת כל הכפתורים של תבנית (סוג שכבר קיים לא משוכפל).
  Future<void> _addFromTemplate() async {
    final tpl = await showDialog<Template>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('הוספת כפתורים מתבנית'),
        children: [
          for (final t in templates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, t),
              child: ListTile(
                title: Text(t.title),
                subtitle: Text(t.description),
              ),
            ),
        ],
      ),
    );
    if (tpl == null) return;
    await state.db.addTemplateTypes(tpl);
    await state.reloadStructure();
  }

  void _open(EventType t) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EventTypeEditScreen(typeId: t.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final types = state.types;
    return Scaffold(
      appBar: AppBar(
        title: const Text('סוגי אירועים'),
        actions: [
          IconButton(
            tooltip: 'הוספה מתבנית',
            onPressed: _addFromTemplate,
            icon: const Icon(Icons.library_add),
          ),
        ],
      ),
      body: ReorderableListView(
        onReorder: (oldIndex, newIndex) async {
          if (newIndex > oldIndex) newIndex--;
          final list = [...types];
          final moved = list.removeAt(oldIndex);
          list.insert(newIndex, moved);
          await state.db.reorderEventTypes(list);
          await state.reloadStructure();
        },
        children: [
          for (final t in types)
            ListTile(
              key: ValueKey(t.id),
              leading: CircleAvatar(
                backgroundColor: Color(t.color).withAlpha(t.hidden ? 70 : 255),
                child: Icon(iconFor(t.icon), color: Colors.white),
              ),
              title: Text(
                t.name,
                style: TextStyle(
                  decoration: t.hidden ? TextDecoration.lineThrough : null,
                ),
              ),
              subtitle: Text(
                t.isMed
                    ? 'מובנה: תרופות ומינונים'
                    : '${t.fields.length} שאלות${t.intervalReminderHours == null ? '' : ' · תזכורת כל ${fmtNum(t.intervalReminderHours!)} שעות'}',
              ),
              trailing: const Icon(Icons.drag_handle),
              onTap: () => _open(t),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addType,
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// עריכת סוג אירוע אחד: פרטי הכפתור + רשימת השאלות.
class EventTypeEditScreen extends StatefulWidget {
  final String typeId;
  const EventTypeEditScreen({super.key, required this.typeId});

  @override
  State<EventTypeEditScreen> createState() => _EventTypeEditScreenState();
}

class _EventTypeEditScreenState extends State<EventTypeEditScreen> {
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

  EventType? get type => state.typeById[widget.typeId];

  Future<void> _editType() async {
    final t = type;
    if (t == null) return;
    final saved = await showDialog<EventType>(
      context: context,
      builder: (_) => _TypeDialog(type: t),
    );
    if (saved == null) return;
    await state.db.saveEventType(saved);
    await state.reloadStructure();
  }

  Future<void> _toggleHidden() async {
    final t = type;
    if (t == null) return;
    t.hidden = !t.hidden;
    await state.db.saveEventType(t);
    await state.reloadStructure();
  }

  Future<void> _delete() async {
    final t = type;
    if (t == null || t.isMed) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('למחוק את "${t.name}"?'),
        content: const Text(
          'אירועים שכבר נרשמו נשארים ביומן. אם יש אירועים, הסוג רק יוסתר.',
        ),
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
    await state.db.deleteEventType(t);
    await state.reloadStructure();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _addField() async {
    final t = type;
    if (t == null) return;
    final f = EventField(
      id: newId(),
      typeId: t.id,
      label: '',
      kind: FieldKind.single,
      sortOrder: t.fields.length,
    );
    final saved = await showDialog<EventField>(
      context: context,
      builder: (_) => _FieldDialog(field: f),
    );
    if (saved == null) return;
    await state.db.saveField(saved);
    await state.reloadStructure();
  }

  Future<void> _editField(EventField f) async {
    final saved = await showDialog<EventField>(
      context: context,
      builder: (_) => _FieldDialog(field: f),
    );
    if (saved == null) return;
    await state.db.saveField(saved);
    await state.reloadStructure();
  }

  Future<void> _deleteField(EventField f) async {
    await state.db.deleteField(f);
    final t = type;
    if (t != null && t.statFieldId == f.id) {
      t.statFieldId = null;
      await state.db.saveEventType(t);
    }
    await state.reloadStructure();
  }

  Future<void> _addOption(EventField f) async {
    final label = await _askText('אפשרות חדשה', '');
    if (label == null || label.trim().isEmpty) return;
    await state.db.saveOption(
      FieldOption(
        id: newId(),
        fieldId: f.id,
        label: label.trim(),
        sortOrder: f.options.length,
      ),
    );
    await state.reloadStructure();
  }

  Future<void> _editOption(FieldOption o) async {
    final label = await _askText('עריכת אפשרות', o.label);
    if (label == null) return;
    if (label.trim().isEmpty) {
      await state.db.deleteOption(o.id);
    } else {
      o.label = label.trim();
      await state.db.saveOption(o);
    }
    await state.reloadStructure();
  }

  Future<String?> _askText(String title, String initial) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          if (initial.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(c, ''),
              child: const Text('מחק', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('ביטול'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, ctrl.text),
            child: const Text('שמור'),
          ),
        ],
      ),
    );
  }

  Future<void> _setStatField(String? fieldId) async {
    final t = type;
    if (t == null) return;
    t.statFieldId = fieldId;
    await state.db.saveEventType(t);
    await state.reloadStructure();
  }

  Future<void> _setStatAgg(String agg) async {
    final t = type;
    if (t == null) return;
    t.statAgg = agg;
    await state.db.saveEventType(t);
    await state.reloadStructure();
  }

  @override
  Widget build(BuildContext context) {
    final t = type;
    if (t == null) {
      return const Scaffold(body: Center(child: Text('הסוג נמחק')));
    }
    final numberFields = t.fields
        .where(
          (f) => f.kind == FieldKind.number || f.kind == FieldKind.duration,
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(t.name),
        actions: [
          IconButton(
            tooltip: t.hidden ? 'הצג' : 'הסתר',
            onPressed: _toggleHidden,
            icon: Icon(t.hidden ? Icons.visibility : Icons.visibility_off),
          ),
          if (!t.isMed)
            IconButton(onPressed: _delete, icon: const Icon(Icons.delete)),
        ],
      ),
      body: ListView(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Color(t.color),
              child: Icon(iconFor(t.icon), color: Colors.white),
            ),
            title: Text(t.name),
            subtitle: Text(
              t.intervalReminderHours == null
                  ? 'בלי תזכורת'
                  : 'תזכורת כל ${fmtNum(t.intervalReminderHours!)} שעות מהפעם האחרונה',
            ),
            trailing: const Icon(Icons.edit),
            onTap: _editType,
          ),
          const Divider(),
          if (t.isMed)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'סוג מובנה: הפופאפ מציג את רשימת התרופות שלך ומינון. את התרופות עורכים בהגדרות > תרופות.',
              ),
            )
          else ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'שאלות בפופאפ',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            for (final f in t.fields) _fieldCard(f),
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                onPressed: _addField,
                icon: const Icon(Icons.add),
                label: const Text('הוסף שאלה'),
              ),
            ),
            if (numberFields.isNotEmpty) ...[
              const Divider(),
              ListTile(
                title: const Text('מה להציג בגרף ובסיכום?'),
                subtitle: const Text('שדה מספרי שסוכמים אותו ליום'),
                trailing: DropdownButton<String?>(
                  value: numberFields.any((f) => f.id == t.statFieldId)
                      ? t.statFieldId
                      : null,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('רק ספירה'),
                    ),
                    for (final f in numberFields)
                      DropdownMenuItem<String?>(
                        value: f.id,
                        child: Text(f.label),
                      ),
                  ],
                  onChanged: _setStatField,
                ),
              ),
              if (t.statFieldId != null)
                ListTile(
                  title: const Text('איך לסכם ליום?'),
                  subtitle: const Text(
                    'סכום - למ"ל או דקות; ממוצע - לחום, משקל, לחץ דם',
                  ),
                  trailing: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: StatAgg.sum, label: Text('סכום')),
                      ButtonSegment(value: StatAgg.avg, label: Text('ממוצע')),
                    ],
                    selected: {t.statAgg},
                    onSelectionChanged: (s) => _setStatAgg(s.first),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _fieldCard(EventField f) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text(f.label),
            subtitle: Text(
              [
                FieldKind.label(f.kind),
                if (f.unit != null && f.unit!.isNotEmpty) f.unit!,
                if (f.required) 'חובה',
                if (f.rememberLast) 'זוכר בחירה אחרונה',
              ].join(' · '),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () => _editField(f),
                  icon: const Icon(Icons.edit),
                ),
                IconButton(
                  onPressed: () => _deleteField(f),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
          if (FieldKind.hasOptions(f.kind))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final o in f.options)
                    InputChip(
                      label: Text(o.label),
                      backgroundColor: o.color == null
                          ? null
                          : Color(o.color!).withAlpha(70),
                      onPressed: () => _editOption(o),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: const Text('אפשרות'),
                    onPressed: () => _addOption(f),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// דיאלוג עריכת פרטי הסוג: שם, אייקון, צבע, תזכורת.
class _TypeDialog extends StatefulWidget {
  final EventType type;
  const _TypeDialog({required this.type});

  @override
  State<_TypeDialog> createState() => _TypeDialogState();
}

class _TypeDialogState extends State<_TypeDialog> {
  late final TextEditingController name;
  late final TextEditingController interval;
  late String icon;
  late int color;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.type.name);
    interval = TextEditingController(
      text: widget.type.intervalReminderHours == null
          ? ''
          : fmtNum(widget.type.intervalReminderHours!),
    );
    icon = widget.type.icon;
    color = widget.type.color;
  }

  @override
  void dispose() {
    name.dispose();
    interval.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.type;
    return AlertDialog(
      title: Text(t.name.isEmpty ? 'סוג אירוע חדש' : 'עריכת סוג'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: name,
              autofocus: t.name.isEmpty,
              decoration: const InputDecoration(labelText: 'שם הכפתור'),
            ),
            const SizedBox(height: 12),
            const Text('אייקון'),
            Wrap(
              spacing: 4,
              children: [
                for (final e in appIcons.entries)
                  IconButton(
                    isSelected: icon == e.key,
                    selectedIcon: Icon(e.value, color: Color(color)),
                    onPressed: () => setState(() => icon = e.key),
                    icon: Icon(e.value),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('צבע'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in palette)
                  GestureDetector(
                    onTap: () => setState(() => color = c),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color == c ? Colors.black : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (!t.isMed)
              TextField(
                controller: interval,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'תזכורת כל כמה שעות מהפעם האחרונה (ריק = בלי)',
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
              EventType(
                id: t.id,
                name: n,
                icon: icon,
                color: color,
                sortOrder: t.sortOrder,
                builtinKind: t.builtinKind,
                intervalReminderHours: double.tryParse(interval.text.trim()),
                statFieldId: t.statFieldId,
                statAgg: t.statAgg,
                hidden: t.hidden,
                fields: t.fields,
              ),
            );
          },
          child: const Text('שמור'),
        ),
      ],
    );
  }
}

/// דיאלוג עריכת שאלה: תווית, סוג, יחידה, חובה, זכור אחרון.
class _FieldDialog extends StatefulWidget {
  final EventField field;
  const _FieldDialog({required this.field});

  @override
  State<_FieldDialog> createState() => _FieldDialogState();
}

class _FieldDialogState extends State<_FieldDialog> {
  late final TextEditingController label;
  late final TextEditingController unit;
  late String kind;
  late bool required;
  late bool rememberLast;

  @override
  void initState() {
    super.initState();
    final f = widget.field;
    label = TextEditingController(text: f.label);
    unit = TextEditingController(text: f.unit ?? '');
    kind = f.kind;
    required = f.required;
    rememberLast = f.rememberLast;
  }

  @override
  void dispose() {
    label.dispose();
    unit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.field;
    return AlertDialog(
      title: Text(f.label.isEmpty ? 'שאלה חדשה' : 'עריכת שאלה'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: label,
              autofocus: f.label.isEmpty,
              decoration: const InputDecoration(
                labelText: 'השאלה (למשל: מה היה בו?)',
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: kind,
              decoration: const InputDecoration(labelText: 'סוג תשובה'),
              items: [
                for (final k in FieldKind.all)
                  DropdownMenuItem(value: k, child: Text(FieldKind.label(k))),
              ],
              onChanged: (v) => setState(() => kind = v ?? kind),
            ),
            if (kind == FieldKind.number)
              TextField(
                controller: unit,
                decoration: const InputDecoration(
                  labelText: 'יחידה (מ"ל, גרם...)',
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('חובה'),
              value: required,
              onChanged: (v) => setState(() => required = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('זכור את הבחירה האחרונה'),
              value: rememberLast,
              onChanged: (v) => setState(() => rememberLast = v),
            ),
            if (FieldKind.hasOptions(kind) && f.label.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'את האפשרויות מוסיפים אחרי השמירה.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
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
            final l = label.text.trim();
            if (l.isEmpty) return;
            Navigator.pop(
              context,
              EventField(
                id: f.id,
                typeId: f.typeId,
                label: l,
                kind: kind,
                unit: kind == FieldKind.number
                    ? (unit.text.trim().isEmpty ? null : unit.text.trim())
                    : (kind == FieldKind.duration ? 'דקות' : null),
                required: required,
                rememberLast: rememberLast,
                sortOrder: f.sortOrder,
                options: f.options,
              ),
            );
          },
          child: const Text('שמור'),
        ),
      ],
    );
  }
}

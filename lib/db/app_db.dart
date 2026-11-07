import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models.dart';
import '../util/ids.dart';
import 'templates.dart';

/// שכבת הנתונים: SQLite דרך sqflite, SQL גולמי.
///
/// סכימה v2 (D-11): לכל טבלה מסונכרנת יש id טקסטואלי גלובלי, updated_at
/// ו-deleted. מחיקה = סימון deleted=1 (tombstone) כדי שתעבור בסנכרון.
/// כל כתיבה מקומית מעדכנת updated_at; מיזוג מרחוק שומר את updated_at שהגיע.
class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();

  static const schemaVersion = 2;

  Database? _db;
  final Map<String, Set<String>> _columns = {};

  Future<Database> get db async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'event_log.db'),
      version: schemaVersion,
      onCreate: _create,
    );
    return _db!;
  }

  static const _sync = '''
        updated_at INTEGER NOT NULL DEFAULT 0,
        deleted INTEGER NOT NULL DEFAULT 0''';

  Future<void> _create(Database d, int version) async {
    await d.execute('''
      CREATE TABLE subjects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        start_date INTEGER,
        start_kind TEXT,$_sync
      )''');
    await d.execute('''
      CREATE TABLE event_types (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        icon TEXT NOT NULL,
        color INTEGER NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        builtin_kind TEXT,
        interval_reminder_hours REAL,
        stat_field_id TEXT,
        stat_agg TEXT NOT NULL DEFAULT 'sum',
        hidden INTEGER NOT NULL DEFAULT 0,$_sync
      )''');
    await d.execute('''
      CREATE TABLE event_fields (
        id TEXT PRIMARY KEY,
        type_id TEXT NOT NULL,
        label TEXT NOT NULL,
        kind TEXT NOT NULL,
        unit TEXT,
        required INTEGER NOT NULL DEFAULT 0,
        remember_last INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0,$_sync
      )''');
    await d.execute('''
      CREATE TABLE field_options (
        id TEXT PRIMARY KEY,
        field_id TEXT NOT NULL,
        label TEXT NOT NULL,
        color INTEGER,
        sort_order INTEGER NOT NULL DEFAULT 0,
        hidden INTEGER NOT NULL DEFAULT 0,$_sync
      )''');
    await d.execute('''
      CREATE TABLE meds (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        default_dose REAL,
        unit TEXT,
        interval_hours REAL,
        active INTEGER NOT NULL DEFAULT 1,$_sync
      )''');
    await d.execute('''
      CREATE TABLE events (
        id TEXT PRIMARY KEY,
        subject_id TEXT NOT NULL,
        type_id TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        vals TEXT,
        note TEXT,$_sync
      )''');
    await d.execute(
      'CREATE INDEX idx_events_type_ts ON events(type_id, timestamp)',
    );
    await d.execute('CREATE INDEX idx_events_ts ON events(timestamp)');
    await d.execute('''
      CREATE TABLE appointments (
        id TEXT PRIMARY KEY,
        subject_id TEXT NOT NULL,
        title TEXT NOT NULL,
        category TEXT NOT NULL,
        scheduled_at INTEGER NOT NULL,
        location TEXT,
        remind_before_min TEXT,
        note TEXT,
        summary TEXT,
        done INTEGER NOT NULL DEFAULT 0,
        follow_up_asked INTEGER NOT NULL DEFAULT 0,$_sync
      )''');
    await d.execute('''
      CREATE TABLE follow_ups (
        id TEXT PRIMARY KEY,
        appointment_id TEXT,
        kind TEXT NOT NULL,
        title TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        remind_daily_at TEXT NOT NULL DEFAULT '10:00',
        done_at INTEGER,$_sync
      )''');
    // הגדרות מקומיות למכשיר - לא מסונכרנות.
    await d.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )''');
    // אין seed כאן: מסך הפתיחה מבקש לבחור תבנית (או מתחבר לדרייב קיים).
    await d.insert('settings', {'key': 'day_start_hour', 'value': '7'});
    await d.insert('settings', {'key': 'device_id', 'value': newId()});
  }

  // ---------- כתיבה גנרית ----------

  /// כתיבה מקומית: insert או replace, updated_at = עכשיו, deleted = 0.
  Future<void> upsert(String table, Map<String, Object?> row) async {
    final m = Map<String, Object?>.from(row);
    m['updated_at'] = nowMs();
    m['deleted'] = 0;
    await (await db).insert(
      table,
      m,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// מחיקה רכה: נשאר tombstone כדי שהמחיקה תעבור לשאר המכשירים.
  Future<void> softDelete(String table, String id) async {
    await (await db).update(
      table,
      {'deleted': 1, 'updated_at': nowMs()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> restore(String table, String id) async {
    await (await db).update(
      table,
      {'deleted': 0, 'updated_at': nowMs()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Set<String>> _columnsOf(String table) async {
    final cached = _columns[table];
    if (cached != null) return cached;
    final info = await (await db).rawQuery('PRAGMA table_info($table)');
    final cols = info.map((r) => r['name'] as String).toSet();
    _columns[table] = cols;
    return cols;
  }

  // ---------- סנכרון: snapshot ומיזוג ----------

  /// כל השורות של כל הטבלאות המסונכרנות, כולל tombstones.
  Future<Map<String, dynamic>> snapshot() async {
    final d = await db;
    final tables = <String, dynamic>{};
    for (final t in syncedTables) {
      tables[t] = await d.query(t);
    }
    return {
      'format': 'event-log',
      'schema': schemaVersion,
      'device': await deviceId,
      'written_at': nowMs(),
      'tables': tables,
    };
  }

  /// מיזוג snapshot שהגיע (מדרייב או מקובץ גיבוי): לכל שורה, הגרסה עם
  /// updated_at הגבוה מנצחת. מחזיר כמה שורות השתנו מקומית.
  Future<int> merge(Map<String, dynamic> snap) async {
    if (snap['format'] != 'event-log') {
      throw const FormatException('זה לא קובץ של יומן אירועים');
    }
    final tables = (snap['tables'] as Map?) ?? {};
    final d = await db;
    var changed = 0;
    await d.transaction((txn) async {
      for (final t in syncedTables) {
        final rows = tables[t];
        if (rows is! List) continue;
        final cols = await _columnsOf(t);
        for (final raw in rows) {
          if (raw is! Map) continue;
          final row = <String, Object?>{};
          raw.forEach((k, v) {
            if (cols.contains(k)) row[k as String] = v as Object?;
          });
          final id = row['id'];
          if (id is! String) continue;
          final remoteTs = (row['updated_at'] as num?)?.toInt() ?? 0;
          final local = await txn.query(
            t,
            columns: ['updated_at'],
            where: 'id = ?',
            whereArgs: [id],
          );
          final localTs = local.isEmpty
              ? -1
              : (local.first['updated_at'] as int? ?? 0);
          if (remoteTs > localTs) {
            await txn.insert(
              t,
              row,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            changed++;
          }
        }
      }
    });
    return changed;
  }

  // ---------- settings ----------

  Future<String?> getSetting(String key) async {
    final rows = await (await db).query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String? value) async {
    final d = await db;
    if (value == null) {
      await d.delete('settings', where: 'key = ?', whereArgs: [key]);
      return;
    }
    await d.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> get dayStartHour async =>
      int.tryParse(await getSetting('day_start_hour') ?? '7') ?? 7;

  Future<String> get deviceId async {
    var id = await getSetting('device_id');
    if (id == null) {
      id = newId();
      await setSetting('device_id', id);
    }
    return id;
  }

  // ---------- נושא היומן ----------

  /// null = עוד לא הוגדר (מסך הפתיחה לא הושלם ולא הגיע כלום מהדרייב).
  Future<Subject?> currentSubject() async {
    final rows = await (await db).query(
      'subjects',
      where: 'deleted = 0',
      orderBy: 'id',
      limit: 1,
    );
    return rows.isEmpty ? null : Subject.fromMap(rows.first);
  }

  Future<void> saveSubject(Subject s) => upsert('subjects', s.toMap());

  /// יוצר יומן חדש מתבנית: נושא + סוגי האירועים שלה.
  Future<Subject> createFromTemplate(Template tpl, {String? name}) async {
    final d = await db;
    await applyTemplate(d, tpl);
    final existing = await currentSubject();
    if (existing != null) return existing;
    final s = Subject(
      id: newId(),
      name: (name == null || name.trim().isEmpty) ? tpl.subjectName : name,
      startKind: tpl.startKind,
    );
    await saveSubject(s);
    return s;
  }

  Future<void> addTemplateTypes(Template tpl) async =>
      applyTemplate(await db, tpl);

  // ---------- סוגי אירועים ----------

  Future<List<EventType>> eventTypes() async {
    final d = await db;
    final types = (await d.query(
      'event_types',
      where: 'deleted = 0',
      orderBy: 'sort_order, name',
    )).map(EventType.fromMap).toList();
    final fields = (await d.query(
      'event_fields',
      where: 'deleted = 0',
      orderBy: 'sort_order, label',
    )).map(EventField.fromMap).toList();
    final opts = (await d.query(
      'field_options',
      where: 'deleted = 0',
      orderBy: 'sort_order, label',
    )).map(FieldOption.fromMap).toList();
    for (final f in fields) {
      f.options = opts.where((o) => o.fieldId == f.id).toList();
    }
    for (final t in types) {
      t.fields = fields.where((f) => f.typeId == t.id).toList();
    }
    return types;
  }

  Future<void> saveEventType(EventType t) => upsert('event_types', t.toMap());

  /// מחיקת סוג: אם יש לו אירועים - רק מוסתר; אחרת tombstone.
  Future<void> deleteEventType(EventType t) async {
    final count =
        Sqflite.firstIntValue(
          await (await db).rawQuery(
            'SELECT COUNT(*) FROM events WHERE type_id = ? AND deleted = 0',
            [t.id],
          ),
        ) ??
        0;
    if (count > 0) {
      t.hidden = true;
      await saveEventType(t);
    } else {
      await softDelete('event_types', t.id);
    }
  }

  Future<void> reorderEventTypes(List<EventType> inOrder) async {
    for (var i = 0; i < inOrder.length; i++) {
      if (inOrder[i].sortOrder == i) continue;
      inOrder[i].sortOrder = i;
      await saveEventType(inOrder[i]);
    }
  }

  Future<void> saveField(EventField f) => upsert('event_fields', f.toMap());

  Future<void> deleteField(EventField f) async {
    for (final o in f.options) {
      await softDelete('field_options', o.id);
    }
    await softDelete('event_fields', f.id);
  }

  Future<void> saveOption(FieldOption o) => upsert('field_options', o.toMap());

  Future<void> deleteOption(String id) => softDelete('field_options', id);

  // ---------- אירועים ----------

  Future<void> saveEvent(LogEvent e) => upsert('events', e.toMap());

  Future<void> deleteEvent(String id) => softDelete('events', id);

  Future<void> restoreEvent(String id) => restore('events', id);

  Future<List<LogEvent>> events({
    DateTime? from,
    DateTime? to,
    Set<String>? typeIds,
    int? limit,
  }) async {
    final where = <String>['deleted = 0'];
    final args = <Object?>[];
    if (from != null) {
      where.add('timestamp >= ?');
      args.add(from.millisecondsSinceEpoch);
    }
    if (to != null) {
      where.add('timestamp < ?');
      args.add(to.millisecondsSinceEpoch);
    }
    if (typeIds != null && typeIds.isNotEmpty) {
      where.add('type_id IN (${List.filled(typeIds.length, '?').join(',')})');
      args.addAll(typeIds);
    }
    final rows = await (await db).query(
      'events',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows.map(LogEvent.fromMap).toList();
  }

  Future<LogEvent?> lastEventOfType(String typeId) async {
    final rows = await (await db).query(
      'events',
      where: 'type_id = ? AND deleted = 0',
      whereArgs: [typeId],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : LogEvent.fromMap(rows.first);
  }

  Future<LogEvent?> lastMedEvent(String medId) async {
    final rows = await (await db).rawQuery(
      'SELECT * FROM events WHERE deleted = 0 AND vals LIKE ? '
      'ORDER BY timestamp DESC LIMIT 1',
      ['%"med_id":"$medId"%'],
    );
    return rows.isEmpty ? null : LogEvent.fromMap(rows.first);
  }

  // ---------- תרופות ----------

  Future<List<Med>> meds() async {
    final rows = await (await db).query(
      'meds',
      where: 'deleted = 0',
      orderBy: 'name',
    );
    return rows.map(Med.fromMap).toList();
  }

  Future<void> saveMed(Med m) => upsert('meds', m.toMap());

  /// תרופה לא נמחקת כדי שאירועים ישנים ימשיכו להציג את שמה.
  Future<void> deactivateMed(Med m) async {
    m.active = false;
    await saveMed(m);
  }

  // ---------- תורים ----------

  Future<List<Appointment>> appointments({
    bool upcomingOnly = false,
    DateTime? from,
  }) async {
    final where = <String>['deleted = 0'];
    final args = <Object?>[];
    if (upcomingOnly) {
      where.add('scheduled_at >= ? AND done = 0');
      args.add(
        DateTime.now()
            .subtract(const Duration(hours: 3))
            .millisecondsSinceEpoch,
      );
    }
    if (from != null) {
      where.add('scheduled_at >= ?');
      args.add(from.millisecondsSinceEpoch);
    }
    final rows = await (await db).query(
      'appointments',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: upcomingOnly ? 'scheduled_at ASC' : 'scheduled_at DESC',
    );
    return rows.map(Appointment.fromMap).toList();
  }

  Future<Appointment?> appointment(String id) async {
    final rows = await (await db).query(
      'appointments',
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : Appointment.fromMap(rows.first);
  }

  /// תורים שעברו ועדיין לא נשאל עליהם שאלון הסיכום.
  Future<List<Appointment>> appointmentsAwaitingFollowUp() async {
    final rows = await (await db).query(
      'appointments',
      where: 'deleted = 0 AND scheduled_at < ? AND follow_up_asked = 0',
      whereArgs: [DateTime.now().millisecondsSinceEpoch],
      orderBy: 'scheduled_at DESC',
    );
    return rows.map(Appointment.fromMap).toList();
  }

  Future<void> saveAppointment(Appointment a) =>
      upsert('appointments', a.toMap());

  Future<void> deleteAppointment(String id) => softDelete('appointments', id);

  // ---------- מעקב (follow-ups) ----------

  Future<List<FollowUp>> openFollowUps() async {
    final rows = await (await db).query(
      'follow_ups',
      where: 'deleted = 0 AND done_at IS NULL',
      orderBy: 'created_at',
    );
    return rows.map(FollowUp.fromMap).toList();
  }

  Future<FollowUp?> followUp(String id) async {
    final rows = await (await db).query(
      'follow_ups',
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : FollowUp.fromMap(rows.first);
  }

  Future<void> saveFollowUp(FollowUp f) => upsert('follow_ups', f.toMap());

  Future<void> deleteFollowUp(String id) => softDelete('follow_ups', id);

  // ---------- ייצוא CSV ----------

  Future<String> exportCsv(List<EventType> types, List<Med> meds) async {
    final all = await events();
    final typeById = {for (final t in types) t.id: t};
    final medById = {for (final m in meds) m.id: m};
    final sb = StringBuffer();
    sb.writeln('﻿תאריך,שעה,סוג,פרטים,הערה');
    String q(String? s) => '"${(s ?? '').replaceAll('"', '""')}"';
    for (final e in all) {
      final t = typeById[e.typeId];
      final details = t == null
          ? jsonEncode(e.values)
          : describeValues(t, e.values, medById);
      final ts = e.timestamp;
      sb.writeln(
        [
          '${ts.year}-${_two(ts.month)}-${_two(ts.day)}',
          '${_two(ts.hour)}:${_two(ts.minute)}',
          q(t?.name ?? e.typeId),
          q(details),
          q(e.note),
        ].join(','),
      );
    }
    for (final a in await appointments()) {
      final ts = a.scheduledAt;
      sb.writeln(
        [
          '${ts.year}-${_two(ts.month)}-${_two(ts.day)}',
          '${_two(ts.hour)}:${_two(ts.minute)}',
          q('תור: ${a.category}'),
          q([a.title, if (a.location != null) a.location!].join(' · ')),
          q(
            [
              if (a.note != null) a.note!,
              if (a.summary != null) a.summary!,
            ].join(' | '),
          ),
        ].join(','),
      );
    }
    return sb.toString();
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}

/// תיאור קצר של ערכי אירוע, לפי השדות של הסוג. משמש ביומן, במסך הבית ובייצוא.
String describeValues(
  EventType t,
  Map<String, dynamic> values,
  Map<String, Med> medById,
) {
  if (t.isMed) {
    final med = medById[values['med_id']];
    final dose = values['dose'];
    final parts = <String>[];
    if (med != null) parts.add(med.name);
    if (dose != null) {
      parts.add('${_fmtNum(dose)} ${med?.unit ?? ''}'.trim());
    }
    return parts.join(' · ');
  }
  final parts = <String>[];
  for (final f in t.fields) {
    final v = values[f.id];
    if (v == null) continue;
    switch (f.kind) {
      case FieldKind.single:
        final o = f.options.where((o) => o.id == v);
        if (o.isNotEmpty) parts.add(o.first.label);
        break;
      case FieldKind.multi:
        final ids = (v as List).map((x) => x.toString()).toSet();
        final labels = f.options
            .where((o) => ids.contains(o.id))
            .map((o) => o.label);
        if (labels.isNotEmpty) parts.add(labels.join('+'));
        break;
      case FieldKind.number:
        parts.add('${_fmtNum(v)} ${f.unit ?? ''}'.trim());
        break;
      case FieldKind.duration:
        parts.add('${_fmtNum(v)} דק\'');
        break;
      case FieldKind.text:
        if ((v as String).trim().isNotEmpty) parts.add(v.trim());
        break;
      case FieldKind.boolean:
        if (v == true) parts.add(f.label);
        break;
    }
  }
  return parts.join(' · ');
}

String _fmtNum(dynamic v) {
  if (v is num) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }
  return v.toString();
}

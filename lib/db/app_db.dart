import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models.dart';

/// שכבת הנתונים: SQLite דרך sqflite, SQL גולמי, בלי code-gen.
class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'baby_log.db'),
      version: 1,
      onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
      onCreate: _create,
    );
    return _db!;
  }

  Future<void> _create(Database d, int version) async {
    await d.execute('''
      CREATE TABLE babies (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        birth_date INTEGER
      )''');
    await d.execute('''
      CREATE TABLE event_types (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        icon TEXT NOT NULL,
        color INTEGER NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        builtin_kind TEXT,
        interval_reminder_hours REAL,
        stat_field_id INTEGER,
        hidden INTEGER NOT NULL DEFAULT 0
      )''');
    await d.execute('''
      CREATE TABLE event_fields (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type_id INTEGER NOT NULL REFERENCES event_types(id) ON DELETE CASCADE,
        label TEXT NOT NULL,
        kind TEXT NOT NULL,
        unit TEXT,
        required INTEGER NOT NULL DEFAULT 0,
        remember_last INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0
      )''');
    await d.execute('''
      CREATE TABLE field_options (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        field_id INTEGER NOT NULL REFERENCES event_fields(id) ON DELETE CASCADE,
        label TEXT NOT NULL,
        color INTEGER,
        sort_order INTEGER NOT NULL DEFAULT 0,
        hidden INTEGER NOT NULL DEFAULT 0
      )''');
    await d.execute('''
      CREATE TABLE events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        baby_id INTEGER NOT NULL,
        type_id INTEGER NOT NULL,
        timestamp INTEGER NOT NULL,
        values TEXT,
        note TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )''');
    await d.execute(
      'CREATE INDEX idx_events_baby_type_ts ON events(baby_id, type_id, timestamp)',
    );
    await d.execute('''
      CREATE TABLE meds (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        default_dose REAL,
        unit TEXT,
        interval_hours REAL,
        active INTEGER NOT NULL DEFAULT 1
      )''');
    await d.execute('''
      CREATE TABLE appointments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        baby_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        category TEXT NOT NULL,
        scheduled_at INTEGER NOT NULL,
        location TEXT,
        remind_before_min TEXT,
        note TEXT,
        summary TEXT,
        done INTEGER NOT NULL DEFAULT 0,
        follow_up_asked INTEGER NOT NULL DEFAULT 0
      )''');
    await d.execute('''
      CREATE TABLE follow_ups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        appointment_id INTEGER,
        kind TEXT NOT NULL,
        title TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        remind_daily_at TEXT NOT NULL DEFAULT '10:00',
        done_at INTEGER
      )''');
    await d.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )''');
    await _seed(d);
  }

  /// ברירות מחדל בעברית. הכל ניתן לעריכה אחר כך.
  Future<void> _seed(Database d) async {
    await d.insert('babies', {'name': 'התינוק/ת'});

    Future<int> type(
      String name,
      String icon,
      int color,
      int order, {
      String? builtin,
      double? interval,
    }) {
      return d.insert('event_types', {
        'name': name,
        'icon': icon,
        'color': color,
        'sort_order': order,
        'builtin_kind': builtin,
        'interval_reminder_hours': interval,
      });
    }

    Future<int> field(
      int typeId,
      String label,
      String kind,
      int order, {
      String? unit,
      bool required = false,
      bool remember = true,
    }) {
      return d.insert('event_fields', {
        'type_id': typeId,
        'label': label,
        'kind': kind,
        'unit': unit,
        'required': required ? 1 : 0,
        'remember_last': remember ? 1 : 0,
        'sort_order': order,
      });
    }

    Future<void> options(int fieldId, List<String> labels) async {
      for (var i = 0; i < labels.length; i++) {
        await d.insert('field_options', {
          'field_id': fieldId,
          'label': labels[i],
          'sort_order': i,
        });
      }
    }

    // טיטול
    final diaper = await type('טיטול', 'diaper', 0xFFF9A825, 0);
    final what = await field(
      diaper,
      'מה היה בו?',
      FieldKind.multi,
      0,
      required: true,
      remember: false,
    );
    await options(what, ['פיפי', 'קקי']);
    final color = await field(
      diaper,
      'צבע',
      FieldKind.single,
      1,
      remember: false,
    );
    await options(color, ['צהוב', 'ירוק', 'חום', 'שחור', 'אדום']);
    final texture = await field(
      diaper,
      'מרקם',
      FieldKind.single,
      2,
      remember: false,
    );
    await options(texture, ['נוזלי', 'רך', 'קשה']);

    // בקבוק
    final bottle = await type('בקבוק', 'bottle', 0xFF42A5F5, 1, interval: 3);
    final ml = await field(
      bottle,
      'כמות',
      FieldKind.number,
      0,
      unit: 'מ"ל',
      required: true,
    );
    final kind = await field(bottle, 'סוג', FieldKind.single, 1);
    await options(kind, ['פורמולה', 'חלב שאוב']);
    await d.update(
      'event_types',
      {'stat_field_id': ml},
      where: 'id = ?',
      whereArgs: [bottle],
    );

    // הנקה
    final nursing = await type('הנקה', 'nursing', 0xFFEC407A, 2, interval: 3);
    final side = await field(
      nursing,
      'צד',
      FieldKind.single,
      0,
      remember: false,
    );
    await options(side, ['ימין', 'שמאל', 'שניהם']);
    final dur = await field(
      nursing,
      'משך',
      FieldKind.duration,
      1,
      unit: 'דקות',
    );
    await d.update(
      'event_types',
      {'stat_field_id': dur},
      where: 'id = ?',
      whereArgs: [nursing],
    );

    // תרופה (מובנה)
    await type('תרופה', 'med', 0xFF7E57C2, 3, builtin: BuiltinKind.med);

    // שינה
    final sleep = await type('שינה', 'sleep', 0xFF5C6BC0, 4);
    final sleepDur = await field(
      sleep,
      'משך',
      FieldKind.duration,
      0,
      unit: 'דקות',
    );
    await d.update(
      'event_types',
      {'stat_field_id': sleepDur},
      where: 'id = ?',
      whereArgs: [sleep],
    );

    // הערה
    final note = await type('הערה', 'note', 0xFF8D6E63, 5);
    await field(note, 'מה קרה?', FieldKind.text, 0, remember: false);

    await d.insert('settings', {'key': 'day_start_hour', 'value': '7'});
  }

  // ---------- עזרי settings ----------

  Future<String?> getSetting(String key) async {
    final rows = await (await db).query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    await (await db).insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> get dayStartHour async =>
      int.tryParse(await getSetting('day_start_hour') ?? '7') ?? 7;

  // ---------- תינוק ----------

  Future<Baby> currentBaby() async {
    final rows = await (await db).query('babies', orderBy: 'id', limit: 1);
    return Baby.fromMap(rows.first);
  }

  Future<void> updateBaby(int id, String name, DateTime? birth) async {
    await (await db).update(
      'babies',
      {'name': name, 'birth_date': birth?.millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------- סוגי אירועים ----------

  Future<List<EventType>> eventTypes({bool includeHidden = false}) async {
    final d = await db;
    final types = (await d.query(
      'event_types',
      where: includeHidden ? null : 'hidden = 0',
      orderBy: 'sort_order, id',
    )).map(EventType.fromMap).toList();
    final fields = (await d.query(
      'event_fields',
      orderBy: 'sort_order, id',
    )).map(EventField.fromMap).toList();
    final opts = (await d.query(
      'field_options',
      orderBy: 'sort_order, id',
    )).map(FieldOption.fromMap).toList();
    for (final f in fields) {
      f.options = opts.where((o) => o.fieldId == f.id).toList();
    }
    for (final t in types) {
      t.fields = fields.where((f) => f.typeId == t.id).toList();
    }
    return types;
  }

  Future<EventType?> eventType(int id) async {
    final all = await eventTypes(includeHidden: true);
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<int> insertEventType(EventType t) async =>
      (await db).insert('event_types', t.toMap());

  Future<void> updateEventType(EventType t) async => (await db).update(
    'event_types',
    t.toMap(),
    where: 'id = ?',
    whereArgs: [t.id],
  );

  Future<void> deleteEventType(int id) async {
    final d = await db;
    // אירועים ישנים נשארים; הסוג רק מוסתר אם יש לו אירועים.
    final count =
        Sqflite.firstIntValue(
          await d.rawQuery('SELECT COUNT(*) FROM events WHERE type_id = ?', [
            id,
          ]),
        ) ??
        0;
    if (count > 0) {
      await d.update(
        'event_types',
        {'hidden': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      await d.delete('event_types', where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<void> reorderEventTypes(List<int> idsInOrder) async {
    final d = await db;
    final batch = d.batch();
    for (var i = 0; i < idsInOrder.length; i++) {
      batch.update(
        'event_types',
        {'sort_order': i},
        where: 'id = ?',
        whereArgs: [idsInOrder[i]],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<int> insertField(EventField f) async =>
      (await db).insert('event_fields', f.toMap());

  Future<void> updateField(EventField f) async => (await db).update(
    'event_fields',
    f.toMap(),
    where: 'id = ?',
    whereArgs: [f.id],
  );

  Future<void> deleteField(int id) async =>
      (await db).delete('event_fields', where: 'id = ?', whereArgs: [id]);

  Future<int> insertOption(FieldOption o) async =>
      (await db).insert('field_options', o.toMap());

  Future<void> updateOption(FieldOption o) async => (await db).update(
    'field_options',
    o.toMap(),
    where: 'id = ?',
    whereArgs: [o.id],
  );

  Future<void> deleteOption(int id) async =>
      (await db).delete('field_options', where: 'id = ?', whereArgs: [id]);

  // ---------- אירועים ----------

  Future<int> insertEvent(LogEvent e) async {
    final m = e.toMap();
    m['created_at'] = DateTime.now().millisecondsSinceEpoch;
    return (await db).insert('events', m);
  }

  Future<void> updateEvent(LogEvent e) async => (await db).update(
    'events',
    e.toMap(),
    where: 'id = ?',
    whereArgs: [e.id],
  );

  Future<void> deleteEvent(int id) async =>
      (await db).delete('events', where: 'id = ?', whereArgs: [id]);

  Future<LogEvent?> event(int id) async {
    final rows = await (await db).query(
      'events',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : LogEvent.fromMap(rows.first);
  }

  Future<List<LogEvent>> events({
    DateTime? from,
    DateTime? to,
    Set<int>? typeIds,
    int? limit,
  }) async {
    final where = <String>[];
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
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows.map(LogEvent.fromMap).toList();
  }

  Future<LogEvent?> lastEventOfType(int typeId) async {
    final rows = await (await db).query(
      'events',
      where: 'type_id = ?',
      whereArgs: [typeId],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : LogEvent.fromMap(rows.first);
  }

  Future<LogEvent?> lastMedEvent(int medId) async {
    final rows = await (await db).rawQuery(
      "SELECT * FROM events WHERE values LIKE ? ORDER BY timestamp DESC LIMIT 1",
      ['%"med_id":$medId%'],
    );
    return rows.isEmpty ? null : LogEvent.fromMap(rows.first);
  }

  // ---------- תרופות ----------

  Future<List<Med>> meds({bool activeOnly = true}) async {
    final rows = await (await db).query(
      'meds',
      where: activeOnly ? 'active = 1' : null,
      orderBy: 'name',
    );
    return rows.map(Med.fromMap).toList();
  }

  Future<Med?> med(int id) async {
    final rows = await (await db).query(
      'meds',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : Med.fromMap(rows.first);
  }

  Future<int> insertMed(Med m) async => (await db).insert('meds', m.toMap());

  Future<void> updateMed(Med m) async =>
      (await db).update('meds', m.toMap(), where: 'id = ?', whereArgs: [m.id]);

  Future<void> deleteMed(int id) async => (await db).update(
    'meds',
    {'active': 0},
    where: 'id = ?',
    whereArgs: [id],
  );

  // ---------- תורים ----------

  Future<List<Appointment>> appointments({
    bool upcomingOnly = false,
    DateTime? from,
    DateTime? to,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (upcomingOnly) {
      where.add('scheduled_at >= ?');
      args.add(
        DateTime.now()
            .subtract(const Duration(hours: 3))
            .millisecondsSinceEpoch,
      );
      where.add('done = 0');
    }
    if (from != null) {
      where.add('scheduled_at >= ?');
      args.add(from.millisecondsSinceEpoch);
    }
    if (to != null) {
      where.add('scheduled_at < ?');
      args.add(to.millisecondsSinceEpoch);
    }
    final rows = await (await db).query(
      'appointments',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: upcomingOnly ? 'scheduled_at ASC' : 'scheduled_at DESC',
    );
    return rows.map(Appointment.fromMap).toList();
  }

  Future<Appointment?> appointment(int id) async {
    final rows = await (await db).query(
      'appointments',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : Appointment.fromMap(rows.first);
  }

  /// תורים שעברו ועדיין לא נשאל עליהם שאלון הסיכום.
  Future<List<Appointment>> appointmentsAwaitingFollowUp() async {
    final rows = await (await db).query(
      'appointments',
      where: 'scheduled_at < ? AND follow_up_asked = 0',
      whereArgs: [DateTime.now().millisecondsSinceEpoch],
      orderBy: 'scheduled_at DESC',
    );
    return rows.map(Appointment.fromMap).toList();
  }

  Future<int> insertAppointment(Appointment a) async =>
      (await db).insert('appointments', a.toMap());

  Future<void> updateAppointment(Appointment a) async => (await db).update(
    'appointments',
    a.toMap(),
    where: 'id = ?',
    whereArgs: [a.id],
  );

  Future<void> deleteAppointment(int id) async =>
      (await db).delete('appointments', where: 'id = ?', whereArgs: [id]);

  // ---------- מעקב (follow-ups) ----------

  Future<List<FollowUp>> openFollowUps() async {
    final rows = await (await db).query(
      'follow_ups',
      where: 'done_at IS NULL',
      orderBy: 'created_at',
    );
    return rows.map(FollowUp.fromMap).toList();
  }

  Future<FollowUp?> followUp(int id) async {
    final rows = await (await db).query(
      'follow_ups',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : FollowUp.fromMap(rows.first);
  }

  Future<int> insertFollowUp(FollowUp f) async =>
      (await db).insert('follow_ups', f.toMap());

  Future<void> updateFollowUp(FollowUp f) async => (await db).update(
    'follow_ups',
    f.toMap(),
    where: 'id = ?',
    whereArgs: [f.id],
  );

  Future<void> deleteFollowUp(int id) async =>
      (await db).delete('follow_ups', where: 'id = ?', whereArgs: [id]);

  // ---------- ייצוא ----------

  Future<String> exportCsv(List<EventType> types, List<Med> meds) async {
    final all = await events();
    final typeById = {for (final t in types) t.id: t};
    final medById = {for (final m in meds) m.id: m};
    final sb = StringBuffer();
    sb.writeln('﻿תאריך,שעה,סוג,פרטים,הערה');
    for (final e in all) {
      final t = typeById[e.typeId];
      final details = t == null
          ? jsonEncode(e.values)
          : describeValues(t, e.values, medById);
      String q(String? s) => '"${(s ?? '').replaceAll('"', '""')}"';
      final ts = e.timestamp;
      sb.writeln(
        [
          '${ts.year}-${_two(ts.month)}-${_two(ts.day)}',
          '${_two(ts.hour)}:${_two(ts.minute)}',
          q(t?.name ?? e.typeId.toString()),
          q(details),
          q(e.note),
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
  Map<int, Med> medById,
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
    final v = values[f.id.toString()];
    if (v == null) continue;
    switch (f.kind) {
      case FieldKind.single:
        final o = f.options.where((o) => o.id == v);
        if (o.isNotEmpty) parts.add(o.first.label);
        break;
      case FieldKind.multi:
        final ids = (v as List).cast<int>();
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

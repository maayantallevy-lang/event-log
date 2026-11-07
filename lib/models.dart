import 'dart:convert';

/// סוגי שאלות בפופאפ של סוג אירוע.
class FieldKind {
  static const single = 'single'; // בחירה אחת
  static const multi = 'multi'; // בחירה מרובה
  static const number = 'number'; // מספר + יחידה
  static const duration = 'duration'; // משך בדקות
  static const text = 'text'; // טקסט חופשי
  static const boolean = 'bool'; // כן/לא

  static const all = [single, multi, number, duration, text, boolean];

  static String label(String kind) {
    switch (kind) {
      case single:
        return 'בחירה אחת';
      case multi:
        return 'בחירה מרובה';
      case number:
        return 'מספר';
      case duration:
        return 'משך (דקות)';
      case text:
        return 'טקסט חופשי';
      case boolean:
        return 'כן / לא';
    }
    return kind;
  }

  static bool hasOptions(String kind) => kind == single || kind == multi;
}

class BuiltinKind {
  static const med = 'med';
  static const appointment = 'appointment';
}

/// כל הטבלאות המסונכרנות. לכל שורה: id (TEXT), updated_at, deleted.
const syncedTables = [
  'subjects',
  'event_types',
  'event_fields',
  'field_options',
  'meds',
  'events',
  'appointments',
  'follow_ups',
];

bool _b(Object? v) => (v as int? ?? 0) == 1;

/// איך להציג את הזמן שעבר מתאריך ההתחלה של היומן.
class StartKind {
  static const birth = 'birth'; // גיל: ימים / שבועות / חודשים
  static const pregnancy = 'pregnancy'; // שבוע הריון: 12+3
  static const start = 'start'; // יום N / שבוע N מתחילת המעקב

  static const all = [birth, pregnancy, start];

  static String label(String? kind) {
    switch (kind) {
      case birth:
        return 'תאריך לידה';
      case pregnancy:
        return 'תחילת הריון (וסת אחרונה)';
      case start:
        return 'תחילת מעקב';
    }
    return 'בלי תאריך';
  }
}

/// איך מסכמים שדה מספרי ליום בגרף: סכום (מ"ל, דקות) או ממוצע (חום, משקל).
class StatAgg {
  static const sum = 'sum';
  static const avg = 'avg';
}

/// נושא היומן: על מי / על מה מתעדים (תינוק, הריון, טיפול...).
class Subject {
  final String id;
  final String name;
  final DateTime? startDate;
  final String? startKind;
  Subject({
    required this.id,
    required this.name,
    this.startDate,
    this.startKind,
  });

  factory Subject.fromMap(Map<String, Object?> m) => Subject(
    id: m['id'] as String,
    name: m['name'] as String,
    startDate: m['start_date'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(m['start_date'] as int),
    startKind: m['start_kind'] as String?,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'start_date': startDate?.millisecondsSinceEpoch,
    'start_kind': startKind,
  };
}

class EventType {
  final String id;
  String name;
  String icon;
  int color;
  int sortOrder;
  final String? builtinKind;
  double? intervalReminderHours;
  String? statFieldId;
  String statAgg;
  bool hidden;
  List<EventField> fields;

  EventType({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.sortOrder,
    this.builtinKind,
    this.intervalReminderHours,
    this.statFieldId,
    this.statAgg = StatAgg.sum,
    this.hidden = false,
    List<EventField>? fields,
  }) : fields = fields ?? [];

  bool get isMed => builtinKind == BuiltinKind.med;

  factory EventType.fromMap(Map<String, Object?> m) => EventType(
    id: m['id'] as String,
    name: m['name'] as String,
    icon: m['icon'] as String,
    color: m['color'] as int,
    sortOrder: m['sort_order'] as int? ?? 0,
    builtinKind: m['builtin_kind'] as String?,
    intervalReminderHours: (m['interval_reminder_hours'] as num?)?.toDouble(),
    statFieldId: m['stat_field_id'] as String?,
    statAgg: m['stat_agg'] as String? ?? StatAgg.sum,
    hidden: _b(m['hidden']),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'icon': icon,
    'color': color,
    'sort_order': sortOrder,
    'builtin_kind': builtinKind,
    'interval_reminder_hours': intervalReminderHours,
    'stat_field_id': statFieldId,
    'stat_agg': statAgg,
    'hidden': hidden ? 1 : 0,
  };
}

class EventField {
  final String id;
  final String typeId;
  String label;
  String kind;
  String? unit;
  bool required;
  bool rememberLast;
  int sortOrder;
  List<FieldOption> options;

  EventField({
    required this.id,
    required this.typeId,
    required this.label,
    required this.kind,
    this.unit,
    this.required = false,
    this.rememberLast = true,
    this.sortOrder = 0,
    List<FieldOption>? options,
  }) : options = options ?? [];

  factory EventField.fromMap(Map<String, Object?> m) => EventField(
    id: m['id'] as String,
    typeId: m['type_id'] as String,
    label: m['label'] as String,
    kind: m['kind'] as String,
    unit: m['unit'] as String?,
    required: _b(m['required']),
    rememberLast: (m['remember_last'] as int? ?? 1) == 1,
    sortOrder: m['sort_order'] as int? ?? 0,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'type_id': typeId,
    'label': label,
    'kind': kind,
    'unit': unit,
    'required': required ? 1 : 0,
    'remember_last': rememberLast ? 1 : 0,
    'sort_order': sortOrder,
  };
}

class FieldOption {
  final String id;
  final String fieldId;
  String label;
  int? color;
  int sortOrder;
  bool hidden;

  FieldOption({
    required this.id,
    required this.fieldId,
    required this.label,
    this.color,
    this.sortOrder = 0,
    this.hidden = false,
  });

  factory FieldOption.fromMap(Map<String, Object?> m) => FieldOption(
    id: m['id'] as String,
    fieldId: m['field_id'] as String,
    label: m['label'] as String,
    color: m['color'] as int?,
    sortOrder: m['sort_order'] as int? ?? 0,
    hidden: _b(m['hidden']),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'field_id': fieldId,
    'label': label,
    'color': color,
    'sort_order': sortOrder,
    'hidden': hidden ? 1 : 0,
  };
}

/// אירוע ביומן. `values` ממופה לפי מזהה שדה -> ערך:
/// single -> מזהה אפשרות (String), multi -> List<String>, number -> double,
/// duration -> int דקות, text -> String, bool -> bool.
/// לתרופה (built-in): {'med_id': String, 'dose': double}.
class LogEvent {
  final String id;
  final String subjectId;
  final String typeId;
  DateTime timestamp;
  Map<String, dynamic> values;
  String? note;

  LogEvent({
    required this.id,
    required this.subjectId,
    required this.typeId,
    required this.timestamp,
    Map<String, dynamic>? values,
    this.note,
  }) : values = values ?? {};

  factory LogEvent.fromMap(Map<String, Object?> m) => LogEvent(
    id: m['id'] as String,
    subjectId: m['subject_id'] as String,
    typeId: m['type_id'] as String,
    timestamp: DateTime.fromMillisecondsSinceEpoch(m['timestamp'] as int),
    values: m['vals'] == null
        ? {}
        : (jsonDecode(m['vals'] as String) as Map<String, dynamic>),
    note: m['note'] as String?,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'subject_id': subjectId,
    'type_id': typeId,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'vals': jsonEncode(values),
    'note': note,
  };
}

class Med {
  final String id;
  String name;
  double? defaultDose;
  String? unit;
  double? intervalHours;
  bool active;

  Med({
    required this.id,
    required this.name,
    this.defaultDose,
    this.unit,
    this.intervalHours,
    this.active = true,
  });

  factory Med.fromMap(Map<String, Object?> m) => Med(
    id: m['id'] as String,
    name: m['name'] as String,
    defaultDose: (m['default_dose'] as num?)?.toDouble(),
    unit: m['unit'] as String?,
    intervalHours: (m['interval_hours'] as num?)?.toDouble(),
    active: (m['active'] as int? ?? 1) == 1,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'default_dose': defaultDose,
    'unit': unit,
    'interval_hours': intervalHours,
    'active': active ? 1 : 0,
  };
}

class AppointmentCategory {
  static const all = ['רופא', 'בדיקה', 'טיפול', 'חיסון', 'אחר'];
}

class Appointment {
  final String id;
  final String subjectId;
  String title;
  String category;
  DateTime scheduledAt;
  String? location;
  List<int> remindBeforeMin; // דקות לפני התור
  String? note;
  String? summary;
  bool done;
  bool followUpAsked;

  Appointment({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.category,
    required this.scheduledAt,
    this.location,
    List<int>? remindBeforeMin,
    this.note,
    this.summary,
    this.done = false,
    this.followUpAsked = false,
  }) : remindBeforeMin = remindBeforeMin ?? [];

  factory Appointment.fromMap(Map<String, Object?> m) => Appointment(
    id: m['id'] as String,
    subjectId: m['subject_id'] as String,
    title: m['title'] as String,
    category: m['category'] as String,
    scheduledAt: DateTime.fromMillisecondsSinceEpoch(m['scheduled_at'] as int),
    location: m['location'] as String?,
    remindBeforeMin: (m['remind_before_min'] as String? ?? '')
        .split(',')
        .where((s) => s.trim().isNotEmpty)
        .map((s) => int.parse(s.trim()))
        .toList(),
    note: m['note'] as String?,
    summary: m['summary'] as String?,
    done: _b(m['done']),
    followUpAsked: _b(m['follow_up_asked']),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'subject_id': subjectId,
    'title': title,
    'category': category,
    'scheduled_at': scheduledAt.millisecondsSinceEpoch,
    'location': location,
    'remind_before_min': remindBeforeMin.join(','),
    'note': note,
    'summary': summary,
    'done': done ? 1 : 0,
    'follow_up_asked': followUpAsked ? 1 : 0,
  };
}

class FollowUpKind {
  static const buyMed = 'buy_med';
  static const bookAppointment = 'book_appointment';
  static const other = 'other';
}

class FollowUp {
  final String id;
  final String? appointmentId;
  final String kind;
  String title;
  final DateTime createdAt;
  String remindDailyAt; // "HH:mm"
  DateTime? doneAt;

  FollowUp({
    required this.id,
    this.appointmentId,
    required this.kind,
    required this.title,
    required this.createdAt,
    this.remindDailyAt = '10:00',
    this.doneAt,
  });

  bool get isOpen => doneAt == null;

  factory FollowUp.fromMap(Map<String, Object?> m) => FollowUp(
    id: m['id'] as String,
    appointmentId: m['appointment_id'] as String?,
    kind: m['kind'] as String,
    title: m['title'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
    remindDailyAt: m['remind_daily_at'] as String? ?? '10:00',
    doneAt: m['done_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(m['done_at'] as int),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'appointment_id': appointmentId,
    'kind': kind,
    'title': title,
    'created_at': createdAt.millisecondsSinceEpoch,
    'remind_daily_at': remindDailyAt,
    'done_at': doneAt?.millisecondsSinceEpoch,
  };
}

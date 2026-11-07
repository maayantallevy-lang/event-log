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

class Baby {
  final int id;
  final String name;
  final DateTime? birthDate;
  Baby({required this.id, required this.name, this.birthDate});

  factory Baby.fromMap(Map<String, Object?> m) => Baby(
    id: m['id'] as int,
    name: m['name'] as String,
    birthDate: m['birth_date'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(m['birth_date'] as int),
  );
}

class EventType {
  final int id;
  String name;
  String icon;
  int color;
  int sortOrder;
  final String? builtinKind;
  double? intervalReminderHours;
  int? statFieldId;
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
    this.hidden = false,
    List<EventField>? fields,
  }) : fields = fields ?? [];

  bool get isMed => builtinKind == BuiltinKind.med;

  factory EventType.fromMap(Map<String, Object?> m) => EventType(
    id: m['id'] as int,
    name: m['name'] as String,
    icon: m['icon'] as String,
    color: m['color'] as int,
    sortOrder: m['sort_order'] as int,
    builtinKind: m['builtin_kind'] as String?,
    intervalReminderHours: (m['interval_reminder_hours'] as num?)?.toDouble(),
    statFieldId: m['stat_field_id'] as int?,
    hidden: (m['hidden'] as int? ?? 0) == 1,
  );

  Map<String, Object?> toMap() => {
    'name': name,
    'icon': icon,
    'color': color,
    'sort_order': sortOrder,
    'builtin_kind': builtinKind,
    'interval_reminder_hours': intervalReminderHours,
    'stat_field_id': statFieldId,
    'hidden': hidden ? 1 : 0,
  };
}

class EventField {
  final int id;
  final int typeId;
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
    id: m['id'] as int,
    typeId: m['type_id'] as int,
    label: m['label'] as String,
    kind: m['kind'] as String,
    unit: m['unit'] as String?,
    required: (m['required'] as int? ?? 0) == 1,
    rememberLast: (m['remember_last'] as int? ?? 1) == 1,
    sortOrder: m['sort_order'] as int? ?? 0,
  );

  Map<String, Object?> toMap() => {
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
  final int id;
  final int fieldId;
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
    id: m['id'] as int,
    fieldId: m['field_id'] as int,
    label: m['label'] as String,
    color: m['color'] as int?,
    sortOrder: m['sort_order'] as int? ?? 0,
    hidden: (m['hidden'] as int? ?? 0) == 1,
  );

  Map<String, Object?> toMap() => {
    'field_id': fieldId,
    'label': label,
    'color': color,
    'sort_order': sortOrder,
    'hidden': hidden ? 1 : 0,
  };
}

/// אירוע ביומן. `values` ממופה לפי מזהה שדה (כמחרוזת) -> ערך:
/// single -> option id (int), multi -> List<int>, number -> double,
/// duration -> int דקות, text -> String, bool -> bool.
/// לתרופה (built-in): {'med_id': int, 'dose': double}.
class LogEvent {
  final int id;
  final int babyId;
  final int typeId;
  DateTime timestamp;
  Map<String, dynamic> values;
  String? note;

  LogEvent({
    required this.id,
    required this.babyId,
    required this.typeId,
    required this.timestamp,
    Map<String, dynamic>? values,
    this.note,
  }) : values = values ?? {};

  factory LogEvent.fromMap(Map<String, Object?> m) => LogEvent(
    id: m['id'] as int,
    babyId: m['baby_id'] as int,
    typeId: m['type_id'] as int,
    timestamp: DateTime.fromMillisecondsSinceEpoch(m['timestamp'] as int),
    values: m['values'] == null
        ? {}
        : (jsonDecode(m['values'] as String) as Map<String, dynamic>),
    note: m['note'] as String?,
  );

  Map<String, Object?> toMap() => {
    'baby_id': babyId,
    'type_id': typeId,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'values': jsonEncode(values),
    'note': note,
    'updated_at': DateTime.now().millisecondsSinceEpoch,
  };
}

class Med {
  final int id;
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
    id: m['id'] as int,
    name: m['name'] as String,
    defaultDose: (m['default_dose'] as num?)?.toDouble(),
    unit: m['unit'] as String?,
    intervalHours: (m['interval_hours'] as num?)?.toDouble(),
    active: (m['active'] as int? ?? 1) == 1,
  );

  Map<String, Object?> toMap() => {
    'name': name,
    'default_dose': defaultDose,
    'unit': unit,
    'interval_hours': intervalHours,
    'active': active ? 1 : 0,
  };
}

class AppointmentCategory {
  static const all = [
    'טיפת חלב',
    'רופא ילדים',
    'קופת חולים',
    'בדיקה',
    'חיסון',
    'אחר',
  ];
}

class Appointment {
  final int id;
  final int babyId;
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
    required this.babyId,
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
    id: m['id'] as int,
    babyId: m['baby_id'] as int,
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
    done: (m['done'] as int? ?? 0) == 1,
    followUpAsked: (m['follow_up_asked'] as int? ?? 0) == 1,
  );

  Map<String, Object?> toMap() => {
    'baby_id': babyId,
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
  final int id;
  final int? appointmentId;
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
    id: m['id'] as int,
    appointmentId: m['appointment_id'] as int?,
    kind: m['kind'] as String,
    title: m['title'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
    remindDailyAt: m['remind_daily_at'] as String? ?? '10:00',
    doneAt: m['done_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(m['done_at'] as int),
  );

  Map<String, Object?> toMap() => {
    'appointment_id': appointmentId,
    'kind': kind,
    'title': title,
    'created_at': createdAt.millisecondsSinceEpoch,
    'remind_daily_at': remindDailyAt,
    'done_at': doneAt?.millisecondsSinceEpoch,
  };
}

import 'package:sqflite/sqflite.dart';

import '../models.dart';

/// תבניות פתיחה. הכל ניתן לעריכה אחר כך - תבנית היא רק נקודת התחלה.
///
/// מזהים קבועים (לא אקראיים) ו-updated_at=1: שני טלפונים שבוחרים אותה
/// תבנית ומסתנכרנים לאותו דרייב לא יוצרים כפילויות, וכל עריכה של המשתמש
/// (updated_at = עכשיו) גוברת על ברירת המחדל.
class Template {
  final String key;
  final String title;
  final String description;
  final String subjectName;
  final String? startKind;
  final List<_T> types;
  const Template(
    this.key,
    this.title,
    this.description,
    this.subjectName,
    this.startKind,
    this.types,
  );
}

class _F {
  final String id;
  final String label;
  final String kind;
  final String? unit;
  final bool required;
  final bool remember;
  final List<String> options;
  const _F(
    this.id,
    this.label,
    this.kind, {
    this.unit,
    this.required = false,
    this.remember = true,
    this.options = const [],
  });
}

class _T {
  final String id;
  final String name;
  final String icon;
  final int color;
  final String? builtin;
  final double? interval;
  final String? statField;
  final String statAgg;
  final bool hidden;
  final List<_F> fields;
  const _T(
    this.id,
    this.name,
    this.icon,
    this.color, {
    this.builtin,
    this.interval,
    this.statField,
    this.statAgg = StatAgg.sum,
    this.hidden = false,
    this.fields = const [],
  });
}

// ---------- סוגים משותפים לכמה תבניות ----------

const _med = _T(
  'tpl-med',
  'תרופה',
  'med',
  0xFF7E57C2,
  builtin: BuiltinKind.med,
);
const _medHidden = _T(
  'tpl-med',
  'תרופה',
  'med',
  0xFF7E57C2,
  builtin: BuiltinKind.med,
  hidden: true,
);
const _note = _T(
  'tpl-note',
  'הערה',
  'note',
  0xFF8D6E63,
  fields: [_F('tpl-note-text', 'מה קרה?', FieldKind.text, remember: false)],
);
const _bp = _T(
  'tpl-bp',
  'לחץ דם',
  'heart',
  0xFFEF5350,
  statField: 'tpl-bp-sys',
  statAgg: StatAgg.avg,
  fields: [
    _F('tpl-bp-sys', 'סיסטולי', FieldKind.number, unit: 'mmHg', required: true),
    _F('tpl-bp-dia', 'דיאסטולי', FieldKind.number, unit: 'mmHg'),
    _F('tpl-bp-pulse', 'דופק', FieldKind.number, unit: 'לדקה'),
  ],
);
const _weight = _T(
  'tpl-weight',
  'משקל',
  'weight',
  0xFF26A69A,
  statField: 'tpl-weight-kg',
  statAgg: StatAgg.avg,
  fields: [
    _F('tpl-weight-kg', 'משקל', FieldKind.number, unit: 'ק"ג', required: true),
  ],
);

const templates = <Template>[
  Template(
    'baby',
    'תינוק',
    'טיטולים, בקבוק, הנקה, שינה, תרופות',
    'התינוק/ת',
    StartKind.birth,
    [
      _T(
        'tpl-baby-diaper',
        'טיטול',
        'diaper',
        0xFFF9A825,
        fields: [
          _F(
            'tpl-baby-diaper-what',
            'מה היה בו?',
            FieldKind.multi,
            required: true,
            remember: false,
            options: ['פיפי', 'קקי'],
          ),
          _F(
            'tpl-baby-diaper-color',
            'צבע',
            FieldKind.single,
            remember: false,
            options: ['צהוב', 'ירוק', 'חום', 'שחור', 'אדום'],
          ),
          _F(
            'tpl-baby-diaper-texture',
            'מרקם',
            FieldKind.single,
            remember: false,
            options: ['נוזלי', 'רך', 'קשה'],
          ),
        ],
      ),
      _T(
        'tpl-baby-bottle',
        'בקבוק',
        'bottle',
        0xFF42A5F5,
        interval: 3,
        statField: 'tpl-baby-bottle-ml',
        fields: [
          _F(
            'tpl-baby-bottle-ml',
            'כמות',
            FieldKind.number,
            unit: 'מ"ל',
            required: true,
          ),
          _F(
            'tpl-baby-bottle-kind',
            'סוג',
            FieldKind.single,
            options: ['פורמולה', 'חלב שאוב'],
          ),
        ],
      ),
      _T(
        'tpl-baby-nursing',
        'הנקה',
        'nursing',
        0xFFEC407A,
        interval: 3,
        statField: 'tpl-baby-nursing-min',
        fields: [
          _F(
            'tpl-baby-nursing-side',
            'צד',
            FieldKind.single,
            remember: false,
            options: ['ימין', 'שמאל', 'שניהם'],
          ),
          _F('tpl-baby-nursing-min', 'משך', FieldKind.duration, unit: 'דקות'),
        ],
      ),
      _med,
      _T(
        'tpl-baby-sleep',
        'שינה',
        'sleep',
        0xFF5C6BC0,
        statField: 'tpl-baby-sleep-min',
        fields: [
          _F('tpl-baby-sleep-min', 'משך', FieldKind.duration, unit: 'דקות'),
        ],
      ),
      _note,
    ],
  ),
  Template(
    'pregnancy',
    'הריון',
    'בחילות, תנועות עובר, לחץ דם, משקל, ויטמינים',
    'ההריון',
    StartKind.pregnancy,
    [
      _T(
        'tpl-preg-nausea',
        'בחילה',
        'sick',
        0xFF9CCC65,
        fields: [
          _F(
            'tpl-preg-nausea-level',
            'עוצמה',
            FieldKind.single,
            remember: false,
            options: ['קלה', 'בינונית', 'חזקה'],
          ),
          _F('tpl-preg-nausea-vomit', 'הקאה', FieldKind.boolean),
        ],
      ),
      _T(
        'tpl-preg-kicks',
        'תנועות עובר',
        'baby',
        0xFFFFB74D,
        statField: 'tpl-preg-kicks-count',
        fields: [
          _F('tpl-preg-kicks-count', 'כמה תנועות', FieldKind.number),
          _F('tpl-preg-kicks-min', 'במשך', FieldKind.duration, unit: 'דקות'),
        ],
      ),
      _bp,
      _weight,
      _med,
      _T(
        'tpl-preg-symptom',
        'תסמין',
        'warning',
        0xFFFF7043,
        fields: [
          _F(
            'tpl-preg-symptom-what',
            'מה?',
            FieldKind.multi,
            remember: false,
            options: [
              'כאב ראש',
              'צרבת',
              'כאבי גב',
              'נפיחות',
              'התכווצויות',
              'אחר',
            ],
          ),
          _F(
            'tpl-preg-symptom-level',
            'עוצמה',
            FieldKind.single,
            remember: false,
            options: ['קלה', 'בינונית', 'חזקה'],
          ),
        ],
      ),
      _note,
    ],
  ),
  Template(
    'health',
    'תרופות ובריאות',
    'תרופות, חום, לחץ דם, סוכר, כאב',
    'מעקב בריאות',
    StartKind.start,
    [
      _med,
      _T(
        'tpl-h-temp',
        'חום',
        'temp',
        0xFFEF5350,
        statField: 'tpl-h-temp-c',
        statAgg: StatAgg.avg,
        fields: [
          _F(
            'tpl-h-temp-c',
            'חום',
            FieldKind.number,
            unit: '°C',
            required: true,
          ),
        ],
      ),
      _bp,
      _T(
        'tpl-h-sugar',
        'סוכר',
        'drop',
        0xFF26C6DA,
        statField: 'tpl-h-sugar-mg',
        statAgg: StatAgg.avg,
        fields: [
          _F(
            'tpl-h-sugar-mg',
            'ערך',
            FieldKind.number,
            unit: 'mg/dL',
            required: true,
          ),
          _F(
            'tpl-h-sugar-when',
            'מתי',
            FieldKind.single,
            options: ['בצום', 'לפני ארוחה', 'אחרי ארוחה'],
          ),
        ],
      ),
      _T(
        'tpl-h-pain',
        'כאב / תסמין',
        'warning',
        0xFFFF7043,
        fields: [
          _F('tpl-h-pain-where', 'מה ואיפה?', FieldKind.text, remember: false),
          _F(
            'tpl-h-pain-level',
            'עוצמה',
            FieldKind.single,
            remember: false,
            options: ['קלה', 'בינונית', 'חזקה'],
          ),
        ],
      ),
      _weight,
      _note,
    ],
  ),
  Template(
    'empty',
    'ריק',
    'מתחילים מאפס ובונים כפתורים בעצמי',
    'היומן שלי',
    null,
    [_note, _medHidden],
  ),
];

Template templateByKey(String key) =>
    templates.firstWhere((t) => t.key == key, orElse: () => templates.last);

const _ts = 1;

/// מוסיף את סוגי התבנית למסד (סוג שכבר קיים - לא נדרס).
Future<void> applyTemplate(DatabaseExecutor d, Template tpl) async {
  Future<void> row(String table, Map<String, Object?> m) => d.insert(table, {
    ...m,
    'updated_at': _ts,
    'deleted': 0,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);

  final existing = await d.query('event_types', columns: ['sort_order']);
  var order = existing.length;
  for (final t in tpl.types) {
    await row('event_types', {
      'id': t.id,
      'name': t.name,
      'icon': t.icon,
      'color': t.color,
      'sort_order': order++,
      'builtin_kind': t.builtin,
      'interval_reminder_hours': t.interval,
      'stat_field_id': t.statField,
      'stat_agg': t.statAgg,
      'hidden': t.hidden ? 1 : 0,
    });
    for (var i = 0; i < t.fields.length; i++) {
      final f = t.fields[i];
      await row('event_fields', {
        'id': f.id,
        'type_id': t.id,
        'label': f.label,
        'kind': f.kind,
        'unit': f.unit,
        'required': f.required ? 1 : 0,
        'remember_last': f.remember ? 1 : 0,
        'sort_order': i,
      });
      for (var j = 0; j < f.options.length; j++) {
        await row('field_options', {
          'id': '${f.id}-o$j',
          'field_id': f.id,
          'label': f.options[j],
          'sort_order': j,
          'hidden': 0,
        });
      }
    }
  }
}

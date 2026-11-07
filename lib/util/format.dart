import 'package:flutter/material.dart';

String two(int n) => n.toString().padLeft(2, '0');

String fmtTime(DateTime t) => '${two(t.hour)}:${two(t.minute)}';

String fmtDate(DateTime t) => '${two(t.day)}.${two(t.month)}.${t.year}';

String fmtDateTime(DateTime t) => '${fmtDate(t)} ${fmtTime(t)}';

const _weekdays = ['שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת', 'ראשון'];

String weekdayName(DateTime t) => _weekdays[t.weekday - 1];

/// "לפני 1:40" / "לפני 25 דק'" / "עכשיו"
String ago(DateTime t, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final d = n.difference(t);
  if (d.inMinutes < 1) return 'עכשיו';
  if (d.inMinutes < 60) return "לפני ${d.inMinutes} דק'";
  if (d.inHours < 24) {
    return 'לפני ${d.inHours}:${two(d.inMinutes % 60)}';
  }
  if (d.inDays == 1) return 'אתמול ${fmtTime(t)}';
  return 'לפני ${d.inDays} ימים';
}

/// "בעוד 2:10" / "בעוד 3 ימים" / "עבר"
String until(DateTime t, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final d = t.difference(n);
  if (d.isNegative) return 'עבר';
  if (d.inMinutes < 60) return "בעוד ${d.inMinutes} דק'";
  if (d.inHours < 24) return 'בעוד ${d.inHours}:${two(d.inMinutes % 60)}';
  final days = d.inDays;
  if (days == 1) return 'מחר ${fmtTime(t)}';
  return 'בעוד $days ימים';
}

/// כותרת יום ביומן: "היום · שבת 7.11" וכו'.
String dayTitle(DateTime day, DateTime today) {
  final d0 = DateTime(day.year, day.month, day.day);
  final t0 = DateTime(today.year, today.month, today.day);
  final diff = t0.difference(d0).inDays;
  final base = '${weekdayName(day)} ${day.day}.${day.month}';
  if (diff == 0) return 'היום · $base';
  if (diff == 1) return 'אתמול · $base';
  return base;
}

/// תחילת "היום הלוגי" (לפי שעת תחילת יום) שבו נמצא t.
DateTime logicalDayStart(DateTime t, int dayStartHour) {
  var d = DateTime(t.year, t.month, t.day, dayStartHour);
  if (t.isBefore(d)) d = d.subtract(const Duration(days: 1));
  return d;
}

String fmtNum(num v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(1);
}

/// כמה זמן עבר מתאריך ההתחלה של היומן, לפי סוג ההתחלה.
/// לידה: "גיל 5 ימים" / "גיל 3 שבועות ו-2 ימים" / "גיל 4 חודשים".
/// הריון: "שבוע 12+3" (מהוסת האחרונה). תחילת מעקב: "יום 9" / "שבוע 6".
String elapsedText(DateTime start, String? kind, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final days = DateTime(
    n.year,
    n.month,
    n.day,
  ).difference(DateTime(start.year, start.month, start.day)).inDays;
  if (days < 0) return '';
  switch (kind) {
    case 'birth':
      if (days < 14) return 'גיל $days ימים';
      if (days < 90) {
        final d = days % 7;
        return 'גיל ${days ~/ 7} שבועות${d == 0 ? '' : ' ו-$d ימים'}';
      }
      if (days < 730) return 'גיל ${(days / 30.44).floor()} חודשים';
      return 'גיל ${(days / 365.25).toStringAsFixed(1)} שנים';
    case 'pregnancy':
      final w = days ~/ 7;
      final tri = w < 14 ? 1 : (w < 28 ? 2 : 3);
      return 'שבוע $w+${days % 7} · טרימסטר $tri';
    default:
      if (days < 14) return 'יום ${days + 1}';
      return 'שבוע ${days ~/ 7 + 1}';
  }
}

/// אייקונים קבועים לבחירה (שם -> אייקון). שם נשמר במסד.
const Map<String, IconData> appIcons = {
  'diaper': Icons.baby_changing_station,
  'bottle': Icons.local_drink,
  'nursing': Icons.favorite,
  'med': Icons.medication,
  'sleep': Icons.bedtime,
  'note': Icons.edit_note,
  'bath': Icons.bathtub,
  'temp': Icons.thermostat,
  'weight': Icons.monitor_weight,
  'food': Icons.restaurant,
  'pump': Icons.water_drop,
  'play': Icons.toys,
  'walk': Icons.stroller,
  'vaccine': Icons.vaccines,
  'doctor': Icons.medical_services,
  'star': Icons.star,
  'warning': Icons.warning_amber,
  'smile': Icons.sentiment_satisfied,
  'cry': Icons.sentiment_very_dissatisfied,
  'poop': Icons.cloud,
  'heart': Icons.favorite_border,
  'sick': Icons.sick,
  'baby': Icons.child_friendly,
  'drop': Icons.bloodtype,
  'run': Icons.directions_run,
  'water': Icons.local_cafe,
  'pill': Icons.medication_liquid,
  'mood': Icons.mood,
  'calendar': Icons.event_note,
};

IconData iconFor(String name) => appIcons[name] ?? Icons.circle;

const List<int> palette = [
  0xFFF9A825,
  0xFF42A5F5,
  0xFFEC407A,
  0xFF7E57C2,
  0xFF5C6BC0,
  0xFF8D6E63,
  0xFF26A69A,
  0xFFEF5350,
  0xFF66BB6A,
  0xFFFF7043,
  0xFF78909C,
  0xFFAB47BC,
];

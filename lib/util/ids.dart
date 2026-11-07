import 'dart:math';

final _rand = Random.secure();

/// מזהה גלובלי לשורה (32 תווי hex). נוצר במכשיר, ייחודי בין מכשירים,
/// כדי שסנכרון בין טלפונים לא ייצור התנגשויות מזהים.
String newId() {
  final b = List<int>.generate(16, (_) => _rand.nextInt(256));
  return b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
}

/// hash יציב (FNV-1a, 31 ביט) - String.hashCode לא מובטח יציב בין הרצות,
/// ומזהי התראות חייבים להישאר זהים כדי שאפשר יהיה לבטל אותן.
int stableHash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h & 0x7fffffff;
}

int nowMs() => DateTime.now().millisecondsSinceEpoch;

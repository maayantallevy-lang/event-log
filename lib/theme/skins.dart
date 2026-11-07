import 'package:flutter/material.dart';

/// מראה האפליקציה: סקין + פונט. נשמר בהגדרות המקומיות (לא מסונכרן),
/// כי כל אחד שמשתף יומן יכול להעדיף מראה אחר בטלפון שלו.

/// איך נראים כפתורי התיעוד הגדולים בסקין.
enum ButtonLook { tinted, outlined, filled, darkTinted }

class Skin {
  final String key;
  final String label;
  final String description;
  final Color seed;
  final Brightness brightness;
  final ButtonLook buttons;
  final double radius;

  const Skin({
    required this.key,
    required this.label,
    required this.description,
    required this.seed,
    required this.brightness,
    required this.buttons,
    required this.radius,
  });

  static const pastel = Skin(
    key: 'pastel',
    label: 'רך ופסטלי',
    description: 'כפתורים בצבעי פסטל, פינות עגולות',
    seed: Color(0xFF4A5BD4),
    brightness: Brightness.light,
    buttons: ButtonLook.tinted,
    radius: 20,
  );
  static const minimal = Skin(
    key: 'minimal',
    label: 'נקי ומינימלי',
    description: 'לבן ואפור, צבע רק באייקונים',
    seed: Color(0xFF3F4350),
    brightness: Brightness.light,
    buttons: ButtonLook.outlined,
    radius: 14,
  );
  static const dark = Skin(
    key: 'dark',
    label: 'כהה',
    description: 'רקע כהה, נוח בלילה',
    seed: Color(0xFF7C8CFF),
    brightness: Brightness.dark,
    buttons: ButtonLook.darkTinted,
    radius: 18,
  );
  static const colorful = Skin(
    key: 'colorful',
    label: 'צבעוני ושמח',
    description: 'כפתורים מלאים בצבעים חזקים',
    seed: Color(0xFFFF7043),
    brightness: Brightness.light,
    buttons: ButtonLook.filled,
    radius: 22,
  );

  static const all = [pastel, minimal, dark, colorful];

  static Skin byKey(String? key) =>
      all.firstWhere((s) => s.key == key, orElse: () => pastel);

  ThemeData theme(AppFont font) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: buttons == ButtonLook.outlined
          ? DynamicSchemeVariant.neutral
          : DynamicSchemeVariant.tonalSpot,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: font.family,
      scaffoldBackgroundColor: buttons == ButtonLook.outlined
          ? Colors.white
          : scheme.surface,
      cardTheme: CardThemeData(
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: buttons == ButtonLook.outlined
            ? shape.copyWith(side: BorderSide(color: scheme.outlineVariant))
            : shape,
        elevation: buttons == ButtonLook.outlined ? 0 : null,
        color: buttons == ButtonLook.outlined ? Colors.white : null,
      ),
      dialogTheme: DialogThemeData(shape: shape),
      bottomSheetTheme: BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radius + 6)),
        ),
      ),
      appBarTheme: buttons == ButtonLook.outlined
          ? const AppBarTheme(backgroundColor: Colors.white)
          : null,
    );
  }

  /// צבעי כפתור תיעוד לפי צבע הסוג.
  TypeButtonColors buttonColors(Color c) {
    switch (buttons) {
      case ButtonLook.filled:
        return TypeButtonColors(c, Colors.white, null);
      case ButtonLook.tinted:
        return TypeButtonColors(
          Color.alphaBlend(c.withAlpha(60), Colors.white),
          _darker(c),
          null,
        );
      case ButtonLook.outlined:
        return TypeButtonColors(
          Colors.white,
          c,
          const Color(0xFFE1E2EA),
          text: const Color(0xFF1B1B21),
        );
      case ButtonLook.darkTinted:
        return TypeButtonColors(
          Color.alphaBlend(c.withAlpha(70), const Color(0xFF1E1F26)),
          Color.lerp(c, Colors.white, 0.35)!,
          null,
        );
    }
  }

  static Color _darker(Color c) => Color.lerp(c, Colors.black, 0.45)!;
}

class TypeButtonColors {
  final Color background;
  final Color icon;
  final Color text;
  final Color? border;
  TypeButtonColors(this.background, this.icon, this.border, {Color? text})
    : text = text ?? icon;
}

class AppFont {
  final String key;
  final String label;
  final String? family;
  final String description;
  const AppFont(this.key, this.label, this.family, this.description);

  static const heebo = AppFont('heebo', 'Heebo', 'Heebo', 'מודרני ונקי');
  static const rubik = AppFont('rubik', 'Rubik', 'Rubik', 'מעוגל קצת, ידידותי');
  static const assistant = AppFont(
    'assistant',
    'Assistant',
    'Assistant',
    'קליל וקריא מאוד',
  );
  static const varela = AppFont(
    'varela',
    'Varela Round',
    'VarelaRound',
    'עגול ורך',
  );
  static const system = AppFont('system', 'פונט המכשיר', null, 'כמו בטלפון');

  static const all = [heebo, rubik, assistant, varela, system];

  static AppFont byKey(String? key) =>
      all.firstWhere((f) => f.key == key, orElse: () => heebo);
}

class Appearance {
  final Skin skin;
  final AppFont font;
  const Appearance(this.skin, this.font);
  static const initial = Appearance(Skin.pastel, AppFont.heebo);
}

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme/skins.dart';
import '../util/format.dart';

/// בחירת סקין ופונט. כל בחירה מוחלת מיד, כדי לראות איך זה נראה.
class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    return ValueListenableBuilder<Appearance>(
      valueListenable: state.appearance,
      builder: (context, look, _) => Scaffold(
        appBar: AppBar(title: const Text('מראה')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _Header('סקין'),
            for (final s in Skin.all)
              _SkinCard(
                skin: s,
                selected: s.key == look.skin.key,
                onTap: () => state.setSkin(s),
              ),
            const SizedBox(height: 12),
            const _Header('פונט'),
            for (final f in AppFont.all)
              Card(
                child: ListTile(
                  onTap: () => state.setFont(f),
                  trailing: f.key == look.font.key
                      ? Icon(
                          Icons.check_circle,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : const Icon(Icons.circle_outlined),
                  title: Text(
                    'יומנון - בקבוק לפני 2:15 שעות',
                    style: TextStyle(fontFamily: f.family, fontSize: 17),
                  ),
                  subtitle: Text('${f.label} · ${f.description}'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
    child: Text(
      text,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

/// כרטיס סקין עם תצוגה מקדימה זעירה של שלושה כפתורים.
class _SkinCard extends StatelessWidget {
  final Skin skin;
  final bool selected;
  final VoidCallback onTap;
  const _SkinCard({
    required this.skin,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = skin.brightness == Brightness.dark;
    final bg = dark
        ? const Color(0xFF15161B)
        : (skin.buttons == ButtonLook.outlined
              ? Colors.white
              : const Color(0xFFF6F6FA));
    const samples = [
      (0xFFF9A825, 'diaper'),
      (0xFF42A5F5, 'bottle'),
      (0xFF7E57C2, 'med'),
    ];
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x1F000000)),
                ),
                child: Row(
                  children: [
                    for (final (color, icon) in samples)
                      Padding(
                        padding: const EdgeInsets.all(3),
                        child: _mini(Color(color), iconFor(icon)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      skin.label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      skin.description,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (selected) Icon(Icons.check_circle, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mini(Color color, IconData icon) {
    final c = skin.buttonColors(color);
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(skin.radius / 2),
        border: c.border == null ? null : Border.all(color: c.border!),
      ),
      child: Icon(icon, size: 18, color: c.icon),
    );
  }
}

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../screens/onboarding_screen.dart';
import '../util/format.dart';

/// אייקון ליומן לפי התבנית שממנה נוצר.
IconData journalIcon(Subject s) => switch (s.template) {
  'baby' => Icons.child_care,
  'pregnancy' => Icons.pregnant_woman,
  'health' => Icons.medication_outlined,
  _ => Icons.menu_book_outlined,
};

/// חלונית בחירת יומן: מעבר בין יומנים והוספת יומן חדש.
Future<void> showJournalPicker(BuildContext context) {
  final state = AppState.instance;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final scheme = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'היומנים שלי',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            for (final s in state.subjects)
              ListTile(
                leading: CircleAvatar(child: Icon(journalIcon(s))),
                title: Text(s.name),
                subtitle: s.startDate == null
                    ? null
                    : Text(elapsedText(s.startDate!, s.startKind)),
                trailing: s.id == state.subject?.id
                    ? Icon(Icons.check_circle, color: scheme.primary)
                    : null,
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await state.switchJournal(s.id);
                },
              ),
            const Divider(),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.add)),
              title: const Text('יומן חדש'),
              subtitle: const Text('למשל תינוק, הריון ותרופות - כל אחד בנפרד'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const OnboardingScreen(addJournal: true),
                  ),
                );
              },
            ),
          ],
        ),
      );
    },
  );
}

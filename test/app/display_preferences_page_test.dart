import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/pages/display_preferences_page.dart';
import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';

void main() {
  testWidgets('toggles and saves a display preference', (tester) async {
    final data = await AssetAppDataRepository().load();
    final account = data.accounts.first;
    List<DisplayPreference>? saved;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: DisplayPreferencesPage(
          title: 'Accounts',
          entityType: 'account',
          data: data,
          preferences: [
            DisplayPreference(
              entityType: 'account',
              entityId: account.id,
              displayOrder: 1001,
              showInApp: true,
              showInEntryForms: true,
            ),
          ],
          onSave: (preferences) async => saved = preferences,
        ),
      ),
    );
    await tester.pump();

    expect(find.text(account.name), findsOneWidget);
    expect(find.text('Visible'), findsOneWidget);
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(find.text('Hidden'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved?.single.showInApp, isFalse);
  });
}

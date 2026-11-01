import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/pages/display_preferences_page.dart';
import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';

void main() {
  testWidgets('preference rows adapt across entity types and widths', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final data = await AssetAppDataRepository().load();
    final cases = [
      ('account', data.accounts.first.id, data.accounts.first.name, 1001),
      ('category', data.categories.first.id, data.categories.first.name, 2000),
      ('tag', data.tags.first.id, data.tags.first.name, 3000),
    ];

    for (final width in [320.0, 360.0, 390.0, 430.0, 600.0, 1280.0]) {
      for (final (type, id, name, order) in cases) {
        await tester.binding.setSurfaceSize(Size(width, 844));
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: DisplayPreferencesPage(
                key: ValueKey(type),
                title: type,
                entityType: type,
                data: data,
                preferences: [
                  DisplayPreference(
                    entityType: type,
                    entityId: id,
                    displayOrder: order,
                    showInApp: true,
                    showInEntryForms: true,
                  ),
                ],
                onSave: (_) async {},
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text(name), findsOneWidget, reason: '$type at $width px');
        expect(
          find.byType(Switch),
          findsNWidgets(2),
          reason: '$type at $width px',
        );
        expect(
          tester.getRect(find.text(name)).width,
          greaterThan(type == 'account' ? 100 : 20),
          reason: '$type at $width px',
        );
        expect(tester.takeException(), isNull, reason: '$type at $width px');
      }
    }

    for (final (width, textScale) in [(320.0, 1.3), (1280.0, 2.0)]) {
      await tester.binding.setSurfaceSize(Size(width, 844));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: DisplayPreferencesPage(
              title: 'Accounts',
              entityType: 'account',
              data: data,
              preferences: [
                DisplayPreference(
                  entityType: 'account',
                  entityId: data.accounts.first.id,
                  displayOrder: 1001,
                  showInApp: true,
                  showInEntryForms: true,
                ),
              ],
              onSave: (_) async {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text(data.accounts.first.name), findsOneWidget);
      expect(
        tester.getRect(find.text('Show in app')).top,
        greaterThan(tester.getRect(find.text(data.accounts.first.name)).top),
        reason: '$width px at text scale $textScale',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: '$width px at text scale $textScale',
      );
    }
  });
}

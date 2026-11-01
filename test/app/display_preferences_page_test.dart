import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/pages/display_preferences_page.dart';
import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';

void main() {
  testWidgets(
    'compact rows preserve names and contextual visibility controls',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();
      final data = await AssetAppDataRepository().load();
      final account = data.accounts.first;
      final otherAccount = data.accounts[1];
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
              DisplayPreference(
                entityType: 'account',
                entityId: otherAccount.id,
                displayOrder: 1002,
                showInApp: false,
                showInEntryForms: false,
              ),
            ],
            onSave: (preferences) async => saved = preferences,
          ),
        ),
      );
      await tester.pump();

      expect(find.text(account.name), findsOneWidget);
      expect(find.text('Visible'), findsOneWidget);
      expect(find.text('Show in app'), findsNWidgets(2));
      expect(find.text('Use in entry forms'), findsNWidgets(2));
      expect(
        find.bySemanticsLabel('Show ${account.name} in app'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Use ${account.name} in entry forms'),
        findsOneWidget,
      );
      expect(
        tester.getRect(find.text(account.name)).width,
        greaterThan(150),
        reason:
            'The name should receive useful width instead of sharing it '
            'with both switches.',
      );
      expect(
        tester.getRect(find.text('Show in app').first).top,
        greaterThan(tester.getRect(find.text(account.name)).top),
      );

      tester
          .widget<ReorderableListView>(find.byType(ReorderableListView))
          .onReorderItem!(0, 1);
      await tester.pump();
      expect(
        tester.getTopLeft(find.text(otherAccount.name)).dy,
        lessThan(tester.getTopLeft(find.text(account.name)).dy),
      );

      await tester.tap(find.bySemanticsLabel('Show ${account.name} in app'));
      await tester.pump();
      expect(find.text('Hidden'), findsNWidgets(2));
      expect(
        tester.widgetList<Switch>(find.byType(Switch)).last.onChanged,
        isNull,
      );

      await tester.tap(find.bySemanticsLabel('Show ${account.name} in app'));
      await tester.pump();
      expect(find.text('Visible'), findsOneWidget);
      expect(
        tester.widgetList<Switch>(find.byType(Switch)).last.value,
        isFalse,
      );
      await tester.tap(
        find.bySemanticsLabel('Use ${account.name} in entry forms'),
      );
      await tester.pump();
      expect(tester.widgetList<Switch>(find.byType(Switch)).last.value, isTrue);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved!.map((preference) => preference.entityId), [
        otherAccount.id,
        account.id,
      ]);
      expect(saved!.map((preference) => preference.displayOrder), [1001, 1002]);
      expect(saved!.map((preference) => preference.showInApp), [false, true]);
      expect(saved!.map((preference) => preference.showInEntryForms), [
        false,
        true,
      ]);

      var saveAttempts = 0;
      List<DisplayPreference>? retrySaved;
      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey('retry-editor'),
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
                showInApp: false,
                showInEntryForms: false,
              ),
            ],
            onSave: (preferences) async {
              saveAttempts++;
              if (saveAttempts == 1) throw StateError('temporary failure');
              retrySaved = preferences;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Something went wrong'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Hidden'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(saveAttempts, 2);
      expect(retrySaved?.single.showInApp, isFalse);
      expect(retrySaved?.single.showInEntryForms, isFalse);
      semantics.dispose();
    },
  );
}

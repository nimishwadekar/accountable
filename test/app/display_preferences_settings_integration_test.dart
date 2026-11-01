import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/pages/settings_page.dart';
import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';

void main() {
  testWidgets('saving display order submits a complete preference set', (
    tester,
  ) async {
    final data = await AssetAppDataRepository().load();
    List<DisplayPreference>? saved;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SettingsPage(
            data: data,
            onReloadData: () async {},
            onSaveDisplayPreferences: (preferences) async {
              saved = preferences;
            },
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Categories'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Categories'), findsNWidgets(2));

    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(saved, isNotNull);
    expect(
      saved!.where((preference) => preference.entityType == 'account'),
      hasLength(data.accounts.length),
    );
    expect(
      saved!.where((preference) => preference.entityType == 'category'),
      hasLength(data.categories.length),
    );
    expect(
      saved!.where((preference) => preference.entityType == 'tag'),
      hasLength(data.tags.length),
    );
  });
}

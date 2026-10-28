import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/pages/settings_page.dart';
import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';

void main() {
  testWidgets('renders data-backed settings controls and refreshes data', (
    tester,
  ) async {
    final data = await AssetAppDataRepository().load();
    var refreshCount = 0;
    var rebuildCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SettingsPage(
            data: data,
            onReloadData: () async => refreshCount++,
            onRebuildDailyTables: () async => rebuildCount++,
            onSaveDisplayPreferences: (_) async {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Customize Display Order'), findsOneWidget);
    expect(find.text('Derived daily tables'), findsOneWidget);
    await tester.ensureVisible(find.text('Refresh data'));
    await tester.tap(find.text('Refresh data'));
    await tester.pump();
    expect(refreshCount, 1);
    expect(rebuildCount, 0);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/pages/settings_page.dart';
import 'package:accountable/app/theme/app_theme.dart';

void main() {
  testWidgets('shows refresh data action', (tester) async {
    var reloaded = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SettingsPage(onReloadData: () async => reloaded = true),
        ),
      ),
    );

    expect(find.text('Refresh data'), findsOneWidget);
    await tester.tap(find.text('Refresh data'));
    await tester.pump();
    expect(reloaded, isTrue);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/app_shell.dart';
import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('keeps transaction visibility through an in-app data refresh', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = AssetAppDataRepository();
    await repository.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AppShell(dataRepository: repository),
      ),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pump();
    await tester.tap(find.text('Show balances'));
    await tester.pump();
    expect(find.textContaining('Balance:'), findsWidgets);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.text('Refresh data'));
    await tester.tap(find.text('Refresh data'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Hide balances'), findsOneWidget);
    expect(find.textContaining('Balance:'), findsWidgets);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:accountable/app/app_shell.dart';
import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/app/session_ui_preferences.dart';
import 'package:accountable/data/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  setUp(() => SessionUiPreferences.instance.startSession());

  testWidgets('filters transactions through the desktop filter flow', (
    tester,
  ) async {
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

    expect(find.text('8 of 8 transactions'), findsOneWidget);
    expect(find.text('All Types'), findsOneWidget);

    await tester.tap(find.text('All Types'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expense').last);
    await tester.pumpAndSettle();

    expect(find.text('5 of 8 transactions'), findsOneWidget);
    expect(find.text('Clear Filters'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.insights_outlined));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Analysis'), findsWidgets);
    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('5 of 8 transactions'), findsOneWidget);

    await tester.tap(find.text('Clear Filters'));
    await tester.pumpAndSettle();
    expect(find.text('8 of 8 transactions'), findsOneWidget);
  });
}

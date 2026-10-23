import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:accountable/app/app_shell.dart';
import 'package:accountable/app/session_ui_preferences.dart';
import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();

  testWidgets('opens compact filters, applies a type, and clears it', (
    tester,
  ) async {
    await SessionUiPreferences.instance.startSession();
    final repository = AssetAppDataRepository();
    await repository.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: AppShell(dataRepository: repository),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pump();
    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();

    expect(find.text('Apply filters'), findsOneWidget);
    await tester.tap(find.text('All Types').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expense').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();

    expect(find.text('Filters (1)'), findsOneWidget);
    expect(find.text('5 pending local transactions'), findsNothing);
    expect(find.text('5 of 8 transactions'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('Filters'), findsOneWidget);
  });
}

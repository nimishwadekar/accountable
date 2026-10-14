import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/app_shell.dart';
import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';

void main() {
  testWidgets('switches sections from compact navigation', (
    WidgetTester tester,
  ) async {
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

    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byIcon(Icons.receipt_long_outlined),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Transactions'), findsWidgets);
    expect(find.text('8 of 8 transactions'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/pages/transaction_form.dart';
import 'package:accountable/app/pages/transactions_page.dart';
import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opens the expense form from the chooser', (tester) async {
    final repository = AssetAppDataRepository();
    final data = await repository.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: TransactionsPage(data: data, onTransactionAdded: (_) async {}),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Expense'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(TransactionFormSheet), findsOneWidget);
    expect(find.text('Source account'), findsOneWidget);
    expect(find.text('Source amount'), findsOneWidget);
    expect(find.text('Add transaction'), findsWidgets);
    Navigator.of(tester.element(find.byType(TransactionFormSheet))).pop();
    await tester.pump(const Duration(milliseconds: 300));
  });
}

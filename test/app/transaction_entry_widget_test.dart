import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/pages/transaction_form.dart';
import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('type chooser displays all supported transaction types', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: TransactionTypeChooser()),
      ),
    );

    expect(find.text('Add Transaction'), findsOneWidget);
    expect(find.text('Expense'), findsOneWidget);
    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Reimbursement'), findsOneWidget);
    expect(find.text('Transfer'), findsOneWidget);
  });

  testWidgets('expense form places description first and requires tag', (
    tester,
  ) async {
    final data = await AssetAppDataRepository().load();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: TransactionFormSheet(type: TransactionType.expense, data: data),
        ),
      ),
    );

    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Tag'), findsOneWidget);
    expect(find.text('Source Account'), findsOneWidget);
    expect(find.text('Source Amount'), findsOneWidget);
    expect(find.text('Tag (optional)'), findsNothing);
  });
}

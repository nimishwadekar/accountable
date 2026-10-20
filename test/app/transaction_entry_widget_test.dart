import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/pages/transaction_form.dart';
import 'package:accountable/app/pages/transaction_form_selectors.dart';
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

  test('category icon mapping uses category semantics', () {
    const dining = Category(
      id: 'dining',
      name: 'Dining',
      allowedTransactionTypes: {},
    );
    const personalCare = Category(
      id: 'personal_care',
      name: 'Personal Care',
      allowedTransactionTypes: {},
    );

    expect(categoryIcon(dining), Icons.restaurant);
    expect(categoryIcon(personalCare), Icons.spa);
    expect(
      categoryIcon(
        const Category(id: 'bills', name: 'Bills', allowedTransactionTypes: {}),
      ),
      Icons.note_alt,
    );
    expect(
      categoryIcon(
        const Category(
          id: 'travel',
          name: 'Travel',
          allowedTransactionTypes: {},
        ),
      ),
      Icons.directions_car,
    );
    expect(
      categoryIcon(
        const Category(
          id: 'nightlife',
          name: 'Nightlife',
          allowedTransactionTypes: {},
        ),
      ),
      Icons.wine_bar,
    );
    expect(
      categoryIcon(
        const Category(id: 'gifts', name: 'Gifts', allowedTransactionTypes: {}),
      ),
      Icons.card_giftcard,
    );
    expect(
      categoryIcon(
        const Category(
          id: 'groceries',
          name: 'Groceries',
          allowedTransactionTypes: {},
        ),
      ),
      Icons.eco,
    );
    expect(categoryColor(dining), isNot(equals(categoryColor(personalCare))));
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
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('Source Account'), findsNothing);
    expect(find.text('Source Amount'), findsNothing);
    expect(find.text('Tag (optional)'), findsNothing);
  });
}

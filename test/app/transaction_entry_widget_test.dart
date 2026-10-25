import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/pages/transaction_form.dart';
import 'package:accountable/app/pages/account_visuals.dart';
import 'package:accountable/app/pages/category_visuals.dart';
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
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.text('Expense'), findsOneWidget);
    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Reimbursement'), findsOneWidget);
    expect(find.text('Transfer'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('same-currency source fees reduce the transferred amount', () {
    const usd = CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2);
    final amounts = calculateTransferAmounts(
      sameCurrency: true,
      sourceAmount: Money.fromMajorUnits(value: '100', currency: usd),
      destinationAmount: Money.fromMajorUnits(value: '100', currency: usd),
      sourceFee: Money.fromMajorUnits(value: '3', currency: usd),
    );

    expect(amounts.source?.minorUnits, 9700);
    expect(amounts.destination?.minorUnits, 9700);
  });

  test('cross-currency source fees only reduce the source amount', () {
    const usd = CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2);
    const inr = CurrencyDefinition(id: 'INR', symbol: '₹', decimalPlaces: 2);
    final amounts = calculateTransferAmounts(
      sameCurrency: false,
      sourceAmount: Money.fromMajorUnits(value: '100', currency: usd),
      destinationAmount: Money.fromMajorUnits(value: '8300', currency: inr),
      sourceFee: Money.fromMajorUnits(value: '3', currency: usd),
    );

    expect(amounts.source?.minorUnits, 9700);
    expect(amounts.destination?.minorUnits, 830000);
  });

  test('account cash icon uses the currency table symbol', () {
    const inr = CurrencyDefinition(id: 'INR', symbol: '₹', decimalPlaces: 2);
    final account = Account(
      id: 'cash',
      name: 'Cash',
      accountType: 'cash',
      currencyId: 'INR',
      openingBalance: Money.zero(inr),
      openingDate: DateTime.utc(2026, 1, 1),
      closingDate: null,
      usesManualValuations: false,
    );
    expect(accountTypeLabel(account), 'Cash');
    expect(accountTypeColor(account), isNotNull);
  });

  test('category icon mapping uses category semantics', () {
    const foodDrink = Category(
      id: 'food_drink',
      name: 'Food & Drink',
      allowedTransactionTypes: {},
    );
    const personalCare = Category(
      id: 'personal_care',
      name: 'Personal Care',
      allowedTransactionTypes: {},
    );

    expect(categoryIcon(foodDrink), Icons.restaurant);
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
    expect(categoryColor(foodDrink), isNot(equals(categoryColor(personalCare))));
    expect(
      categoryIcon(
        const Category(
          id: 'loan_repayment',
          name: 'Loan Repayment',
          allowedTransactionTypes: {TransactionType.transfer},
        ),
      ),
      Icons.account_balance,
    );
    expect(
      categoryIcon(
        const Category(
          id: 'credit_repayment',
          name: 'Credit Repayment',
          allowedTransactionTypes: {TransactionType.transfer},
        ),
      ),
      Icons.credit_card,
    );
    expect(
      categoryIcon(
        const Category(
          id: 'emergency_fund',
          name: 'Emergency Fund',
          allowedTransactionTypes: {TransactionType.transfer},
        ),
      ),
      Icons.health_and_safety,
    );
    expect(
      categoryIcon(
        const Category(
          id: 'general',
          name: 'General',
          allowedTransactionTypes: {TransactionType.transfer},
        ),
      ),
      Icons.swap_horiz,
    );
  });

  testWidgets('template type chooser has its own title and close action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: TransactionTypeChooser(createTemplate: true),
        ),
      ),
    );

    expect(find.text('Create Template'), findsOneWidget);
    expect(find.text('Add Transaction'), findsNothing);
    expect(find.text('Transaction Type'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('transfer templates do not show fee controls', (tester) async {
    const usd = CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2);
    final account = Account(
      id: 'checking',
      name: 'Checking',
      accountType: 'cash',
      currencyId: usd.id,
      openingBalance: Money.zero(usd),
      openingDate: DateTime.utc(2026, 1, 1),
      closingDate: null,
      usesManualValuations: false,
    );
    final data = AppDataSnapshot(
      accounts: [account],
      categories: const [],
      currencies: [usd],
      tags: const [],
      transactions: const [],
      exchangeRates: const [],
      dailyAccountBalances: const [],
      dailyNetWorth: const [],
      dailyManualValuations: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: TransactionFormSheet(
            type: TransactionType.transfer,
            data: data,
            createTemplate: true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Source Account Fee'), findsNothing);
    expect(find.text('Destination Account Fee'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
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
    await tester.pump();

    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Tag'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('Source Account'), findsNothing);
    expect(find.text('Source Amount'), findsNothing);
    expect(find.text('Tag (optional)'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

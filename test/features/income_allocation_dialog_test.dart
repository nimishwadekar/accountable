import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';
import 'package:accountable/features/analysis/income_allocation_dialog.dart';
import 'package:accountable/app/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders income allocation fields', (tester) async {
    const usd = CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2);
    final checking = Account(
      id: 'checking',
      name: 'Checking',
      accountType: 'cash',
      currencyId: 'USD',
      openingBalance: Money.zero(usd),
      openingDate: DateTime.utc(2026, 1, 1),
      closingDate: null,
      usesManualValuations: false,
    );
    final data = AppDataSnapshot(
      accounts: [checking],
      categories: const [
        Category(
          id: 'salary',
          name: 'Salary',
          allowedTransactionTypes: {TransactionType.income},
        ),
      ],
      currencies: const [usd],
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
        home: IncomeAllocationDialog(data: data),
      ),
    );
    await tester.pump();

    expect(find.text('Add Income Allocation'), findsOneWidget);
    expect(find.text('Income Category'), findsOneWidget);
    expect(find.text('Expected Amount per Income (USD)'), findsOneWidget);
    expect(find.text('Description Keyword (optional)'), findsOneWidget);
  });

  testWidgets('validates allocation source and destination accounts', (
    tester,
  ) async {
    const usd = CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2);
    final account = Account(
      id: 'checking',
      name: 'Checking',
      accountType: 'cash',
      currencyId: 'USD',
      openingBalance: Money.zero(usd),
      openingDate: DateTime.utc(2026, 1, 1),
      closingDate: null,
      usesManualValuations: false,
    );
    final data = AppDataSnapshot(
      accounts: [account],
      categories: const [
        Category(
          id: 'salary',
          name: 'Salary',
          allowedTransactionTypes: {TransactionType.income},
        ),
      ],
      currencies: const [usd],
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
        home: Scaffold(body: IncomeAllocationDialog(data: data)),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextFormField).at(0), 'Allocation');
    await tester.enterText(find.byType(TextFormField).at(1), '100');

    final dropdowns = find.byType(DropdownButtonFormField<String>);
    for (var index = 0; index < dropdowns.evaluate().length; index++) {
      await tester.ensureVisible(dropdowns.at(index));
      await tester.tap(dropdowns.at(index));
      await tester.pump();
      await tester.tap(find.text(index == 0 ? 'Salary' : 'Checking').last);
      await tester.pump();
    }
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Source and destination must differ.'), findsOneWidget);
  });
}

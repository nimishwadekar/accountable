import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/pages/transaction_list_widgets.dart';
import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';

void main() {
  testWidgets('shows post-transaction balances for both sides of transfers', (
    tester,
  ) async {
    const usd = CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2);
    Account account(String id, String name, String openingBalance) => Account(
      id: id,
      name: name,
      accountType: 'cash',
      currencyId: usd.id,
      openingBalance: Money.fromMajorUnits(
        value: openingBalance,
        currency: usd,
      ),
      openingDate: DateTime.utc(2026, 1, 1),
      closingDate: null,
      usesManualValuations: false,
    );
    final checking = account('checking', 'Checking', '1000');
    final savings = account('savings', 'Savings', '500');
    final transaction = Transaction(
      id: 'transfer-1',
      createdAt: DateTime.utc(2026, 1, 2),
      date: DateTime.utc(2026, 1, 2),
      type: TransactionType.transfer,
      sourceAmount: Money.fromMajorUnits(value: '20', currency: usd),
      sourceAccountId: checking.id,
      destinationAmount: Money.fromMajorUnits(value: '20', currency: usd),
      destinationAccountId: savings.id,
      categoryId: null,
      tagId: null,
      description: 'Move money',
    );
    final data = AppDataSnapshot(
      accounts: [checking, savings],
      categories: const [],
      currencies: [usd],
      tags: const [],
      transactions: [transaction],
      exchangeRates: const [],
      dailyAccountBalances: const [],
      dailyNetWorth: const [],
      dailyManualValuations: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: TransactionListRow(
            transaction: transaction,
            data: data,
            onTap: () {},
            showAccountBalances: true,
          ),
        ),
      ),
    );

    expect(find.text(r'Balance: $ 980.00'), findsOneWidget);
    expect(find.text(r'Balance: $ 520.00'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/pages/assets_liabilities_page.dart';
import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';

void main() {
  testWidgets('shows valuation accounts and add form in order', (tester) async {
    final usd = const CurrencyDefinition(
      id: 'USD',
      symbol: r'$',
      decimalPlaces: 2,
    );
    final account = Account(
      id: 'brokerage',
      name: 'Brokerage',
      accountType: 'asset',
      currencyId: 'USD',
      openingBalance: Money.zero(usd),
      openingDate: DateTime.utc(2026, 1, 1),
      closingDate: null,
      usesManualValuations: true,
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
          body: AccountsPage(data: data, onValuationsAdded: (_) async {}),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Brokerage'), findsOneWidget);
    expect(find.text('Cash Accounts'), findsOneWidget);
    expect(find.text('Assets & Liabilities'), findsOneWidget);
    await tester.tap(find.text('Add valuation'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Add Daily Valuations'), findsOneWidget);
    expect(find.text('Brokerage'), findsWidgets);
    expect(find.text('Save Valuations'), findsOneWidget);
  });
}

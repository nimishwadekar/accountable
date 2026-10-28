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
    final secondAccount = Account(
      id: 'property',
      name: 'Property',
      accountType: 'asset',
      currencyId: 'USD',
      openingBalance: Money.zero(usd),
      openingDate: DateTime.utc(2026, 1, 1),
      closingDate: null,
      usesManualValuations: true,
    );
    final data = AppDataSnapshot(
      accounts: [account, secondAccount],
      categories: const [],
      currencies: [usd],
      tags: const [],
      transactions: const [],
      exchangeRates: const [],
      dailyAccountBalances: const [],
      dailyNetWorth: const [],
      dailyManualValuations: const [],
    );
    List<DailyManualValuation>? savedValuations;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AccountsPage(
            data: data,
            onValuationsAdded: (valuations) async {
              savedValuations = valuations;
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Brokerage'), findsOneWidget);
    expect(find.text('Cash Accounts'), findsOneWidget);
    expect(find.text('Assets & Liabilities'), findsOneWidget);
    await tester.tap(find.text('Add valuation'));
    await tester.pumpAndSettle();

    expect(find.text('Add Daily Valuations'), findsOneWidget);
    expect(find.text('Brokerage'), findsWidgets);
    expect(find.text('Property'), findsWidgets);
    expect(find.text('Save entered valuations'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, '1234.56');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(FilledButton).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();

    expect(savedValuations, hasLength(1));
    expect(savedValuations!.single.accountId, 'brokerage');
    expect(savedValuations!.single.value.minorUnits, 123456);
  });
}

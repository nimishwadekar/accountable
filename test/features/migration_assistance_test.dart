import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';
import 'package:accountable/features/migration_assistance/migration_assistance_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('calculates reverse balances from migration transaction effects', () {
    const usd = CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2);
    final account = Account(
      id: 'checking',
      name: 'Checking',
      accountType: 'cash',
      currencyId: 'USD',
      openingBalance: Money.fromMajorUnits(value: '1000', currency: usd),
      openingDate: DateTime.utc(2026, 1, 1),
      closingDate: null,
      usesManualValuations: false,
    );
    final migration = Transaction(
      id: 'old-expense',
      createdAt: DateTime.utc(2026, 1, 1),
      date: DateTime.utc(2026, 1, 1),
      type: TransactionType.expense,
      sourceAmount: Money.fromMajorUnits(value: '100', currency: usd),
      sourceAccountId: account.id,
      destinationAmount: null,
      destinationAccountId: null,
      categoryId: 'dining',
      tagId: 'tag',
      description: 'Old expense',
    );
    final data = AppDataSnapshot(
      accounts: [account],
      categories: const [],
      currencies: [usd],
      tags: const [],
      transactions: const [],
      transactionsToMigrate: [migration],
      exchangeRates: const [],
      dailyAccountBalances: const [],
      dailyNetWorth: const [],
      dailyManualValuations: const [],
    );

    final change = calculateMigrationChanges(data).single;

    expect(change.openingBalance.minorUnits, 100000);
    expect(change.netChange.minorUnits, -10000);
    expect(change.preMigrationBalance.minorUnits, 110000);
  });

  testWidgets('opens an account migration transaction drill-down', (
    tester,
  ) async {
    const usd = CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2);
    final account = Account(
      id: 'checking',
      name: 'Checking',
      accountType: 'cash',
      currencyId: 'USD',
      openingBalance: Money.fromMajorUnits(value: '1000', currency: usd),
      openingDate: DateTime.utc(2026, 1, 1),
      closingDate: null,
      usesManualValuations: false,
    );
    final migration = Transaction(
      id: 'old-expense',
      createdAt: DateTime.utc(2026, 1, 1),
      date: DateTime.utc(2026, 1, 1),
      type: TransactionType.expense,
      sourceAmount: Money.fromMajorUnits(value: '100', currency: usd),
      sourceAccountId: account.id,
      destinationAmount: null,
      destinationAccountId: null,
      categoryId: null,
      tagId: null,
      description: 'Old expense',
    );
    final data = AppDataSnapshot(
      accounts: [account],
      categories: const [],
      currencies: [usd],
      tags: const [],
      transactions: const [],
      transactionsToMigrate: [migration],
      exchangeRates: const [],
      dailyAccountBalances: const [],
      dailyNetWorth: const [],
      dailyManualValuations: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: MigrationAssistancePage(data: data)),
      ),
    );
    await tester.pump();

    expect(find.text('Checking'), findsOneWidget);
    await tester.tap(find.text('Checking'));
    await tester.pumpAndSettle();
    expect(find.text('Old expense'), findsOneWidget);
  });
}

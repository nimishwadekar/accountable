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
    final inactiveAccount = Account(
      id: 'savings',
      name: 'Savings',
      accountType: 'cash',
      currencyId: usd.id,
      openingBalance: Money.zero(usd),
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
      categoryId: 'food_drink',
      tagId: 'tag',
      description: 'Old expense',
    );
    final data = AppDataSnapshot(
      accounts: [account, inactiveAccount],
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

    final changes = calculateMigrationChanges(data);
    final change = changes.first;

    expect(change.openingBalance.minorUnits, 100000);
    expect(change.netChange.minorUnits, -10000);
    expect(change.preMigrationBalance.minorUnits, 110000);
    expect(change.transactionCount, 1);
    expect(changes[1].transactionCount, 0);
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
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container && widget.color == const Color(0xFFEAF7EF),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Checking'));
    await tester.pumpAndSettle();
    expect(find.text('Old expense'), findsOneWidget);
  });

  testWidgets('migration confirms manual opening balance updates', (
    tester,
  ) async {
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
    Transaction transaction({
      required String id,
      required DateTime date,
      required DateTime createdAt,
    }) => Transaction(
      id: id,
      createdAt: createdAt,
      date: date,
      type: TransactionType.expense,
      sourceAmount: Money.fromMajorUnits(value: '1', currency: usd),
      sourceAccountId: account.id,
      destinationAmount: null,
      destinationAccountId: null,
      categoryId: null,
      tagId: null,
      description: 'Historical expense',
    );

    final main = transaction(
      id: 'existing',
      date: DateTime.utc(2026, 10, 10),
      createdAt: DateTime.utc(2026, 10, 11),
    );
    final migration = transaction(
      id: 'MIGABC1230001',
      date: DateTime.utc(2026, 10, 10),
      createdAt: DateTime.utc(2026, 10, 29),
    );
    final data = AppDataSnapshot(
      accounts: [account],
      categories: const [],
      currencies: [usd],
      tags: const [],
      transactions: [main],
      transactionsToMigrate: [migration],
      exchangeRates: const [],
      dailyAccountBalances: const [],
      dailyNetWorth: const [],
      dailyManualValuations: const [],
    );
    var migrateCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: MigrationAssistancePage(
            data: data,
            onFinalizeTransactions: () async =>
                MigrationBatchStatus.fromSnapshot(data),
            onMigrateTransactions: () async {
              migrateCalls++;
              return const MigrationExecutionResult(
                transactionCount: 1,
                wasAlreadyMigrated: false,
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Migrate Transactions'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('manually updated the opening balances'),
      findsOneWidget,
    );

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Migration date warning'), findsOneWidget);
    expect(
      find.textContaining('oldest existing transaction (2026-10-10)'),
      findsOneWidget,
    );
    expect(find.textContaining('manually organize'), findsWidgets);

    await tester.tap(find.text('Cancel migration'));
    await tester.pumpAndSettle();
    expect(migrateCalls, 0);

    await tester.tap(find.text('Migrate Transactions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue migration'));
    await tester.pumpAndSettle();
    expect(migrateCalls, 1);
  });
}

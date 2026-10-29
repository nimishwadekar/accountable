import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builds transaction and daily indexes from one snapshot', () async {
    final data = await AssetAppDataRepository().load();

    final expectedTransactions = [...data.transactions]
      ..sort((a, b) {
        final dateComparison = b.date.compareTo(a.date);
        if (dateComparison != 0) return dateComparison;
        final createdAtComparison = b.createdAt.compareTo(a.createdAt);
        return createdAtComparison == 0
            ? b.id.compareTo(a.id)
            : createdAtComparison;
      });

    expect(data.transactionsByDisplayOrder, expectedTransactions);
    expect(data.earliestTransactionDate, DateTime.utc(2026, 10, 10));
    expect(
      data.transactionsByDate.values.expand((items) => items),
      containsAll(data.transactions),
    );
    expect(
      data.transactionsByMonth[DateTime.utc(2026, 10)]?.length,
      data.transactions.length,
    );
    expect(
      data.dailyNetWorthByDate[DateTime.utc(2026, 10, 10)]?.amount,
      isNotNull,
    );
    expect(data.dailyBalancesByAccountId['chase_checking'], isNotEmpty);
    expect(
      data.manualValuationsByAccountId.keys,
      containsAll(data.dailyManualValuations.map((value) => value.accountId)),
    );
    expect(
      data.exchangeRatesByCurrencyId.keys,
      containsAll(data.exchangeRates.map((value) => value.currencyId).toSet()),
    );
  });

  test('caches immutable display collections and ledger balances', () async {
    final data = await AssetAppDataRepository().load();

    expect(identical(data.orderedAccounts, data.orderedAccounts), isTrue);
    expect(identical(data.visibleAccounts, data.visibleAccounts), isTrue);
    expect(identical(data.visibleCategories, data.visibleCategories), isTrue);
    expect(identical(data.visibleTags, data.visibleTags), isTrue);

    final expectedBalances = const AccountBalanceCalculator().calculate(
      accounts: data.accounts,
      transactions: data.transactions,
    );
    for (final entry in expectedBalances.entries) {
      expect(
        data.ledgerBalances[entry.key]?.minorUnits,
        entry.value.minorUnits,
      );
      expect(
        data.ledgerBalances[entry.key]?.currencyId,
        entry.value.currencyId,
      );
    }
  });

  test('indexes account balances immediately after each transaction', () {
    const usd = CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2);
    final checking = Account(
      id: 'checking',
      name: 'Checking',
      accountType: 'cash',
      currencyId: usd.id,
      openingBalance: Money.fromMajorUnits(value: '1000', currency: usd),
      openingDate: DateTime.utc(2026, 1, 1),
      closingDate: null,
      usesManualValuations: false,
    );
    Transaction expense(String id, DateTime date, String amount) => Transaction(
      id: id,
      createdAt: date,
      date: date,
      type: TransactionType.expense,
      sourceAmount: Money.fromMajorUnits(value: amount, currency: usd),
      sourceAccountId: checking.id,
      destinationAmount: null,
      destinationAccountId: null,
      categoryId: null,
      tagId: null,
      description: id,
    );
    final later = expense('later', DateTime.utc(2026, 1, 2), '20');
    final earlier = expense('earlier', DateTime.utc(2026, 1, 1), '10');
    final data = AppDataSnapshot(
      accounts: [checking],
      categories: const [],
      currencies: [usd],
      tags: const [],
      transactions: [later, earlier],
      exchangeRates: const [],
      dailyAccountBalances: const [],
      dailyNetWorth: const [],
      dailyManualValuations: const [],
    );

    expect(
      data.balanceAfterTransaction(checking.id, earlier.id)?.minorUnits,
      99000,
    );
    expect(
      data.balanceAfterTransaction(checking.id, later.id)?.minorUnits,
      97000,
    );
  });
}

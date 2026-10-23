import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builds transaction and daily indexes from one snapshot', () async {
    final data = await AssetAppDataRepository().load();

    final expectedTransactions = [...data.transactions]
      ..sort((a, b) {
        final dateComparison = b.date.compareTo(a.date);
        return dateComparison == 0
            ? b.createdAt.compareTo(a.createdAt)
            : dateComparison;
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
      expect(data.ledgerBalances[entry.key]?.minorUnits, entry.value.minorUnits);
      expect(data.ledgerBalances[entry.key]?.currencyId, entry.value.currencyId);
    }
  });
}

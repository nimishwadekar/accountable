import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';
import 'package:accountable/features/analysis/income_allocation_analysis.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('applies allocation date bounds as local calendar dates', () async {
    final source = await AssetAppDataRepository().load();
    final usd = source.currenciesById['USD']!;
    final checking = source.accountsById['chase_checking']!;
    final credit = source.accountsById['chase_freedom_rise']!;
    final amount = Money.fromMajorUnits(value: '100', currency: usd);
    final allocationDate = DateTime(2026, 10, 10);
    final allocation = IncomeAllocation(
      id: 'allocation-test',
      name: 'Test allocation',
      incomeCategoryId: 'salary',
      incomeAccountId: checking.id,
      transferCategoryId: 'general',
      expectedAmountPerIncome: amount,
      startDate: allocationDate,
      endDate: allocationDate,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
    final transactions = [
      Transaction(
        id: 'income-before-start',
        createdAt: DateTime.utc(2026, 10, 5),
        date: DateTime.utc(2026, 10, 5),
        type: TransactionType.income,
        sourceAmount: null,
        sourceAccountId: null,
        destinationAmount: amount,
        destinationAccountId: checking.id,
        categoryId: 'salary',
        tagId: null,
        description: 'Before allocation',
      ),
      Transaction(
        id: 'income-on-start',
        createdAt: DateTime.utc(2026, 10, 10),
        date: DateTime.utc(2026, 10, 10),
        type: TransactionType.income,
        sourceAmount: null,
        sourceAccountId: null,
        destinationAmount: amount,
        destinationAccountId: checking.id,
        categoryId: 'salary',
        tagId: null,
        description: 'On allocation date',
      ),
      Transaction(
        id: 'transfer-on-start',
        createdAt: DateTime.utc(2026, 10, 10),
        date: DateTime.utc(2026, 10, 10),
        type: TransactionType.transfer,
        sourceAmount: amount,
        sourceAccountId: checking.id,
        destinationAmount: amount,
        destinationAccountId: credit.id,
        categoryId: 'general',
        tagId: null,
        description: 'On allocation date',
      ),
    ];
    final data = AppDataSnapshot(
      accounts: source.accounts,
      categories: source.categories,
      currencies: source.currencies,
      tags: source.tags,
      transactions: transactions,
      exchangeRates: source.exchangeRates,
      dailyAccountBalances: source.dailyAccountBalances,
      dailyNetWorth: source.dailyNetWorth,
      dailyManualValuations: source.dailyManualValuations,
      incomeAllocations: [allocation],
    );

    final progress = IncomeAllocationAnalyzer(data)
        .analyze(month: DateTime.utc(2026, 10, 1), incomeCategoryId: 'salary')
        .single;

    expect(progress.expectedAmount.minorUnits, 10000);
    expect(progress.actualAmount.minorUnits, 10000);
  });

  test('keeps allocation amounts in the income account currency', () async {
    final source = await AssetAppDataRepository().load();
    const chf = CurrencyDefinition(id: 'CHF', symbol: 'CHF', decimalPlaces: 2);
    final originalChecking = source.accountsById['chase_checking']!;
    final checking = Account(
      id: originalChecking.id,
      name: originalChecking.name,
      accountType: originalChecking.accountType,
      currencyId: chf.id,
      openingBalance: Money.zero(chf),
      openingDate: originalChecking.openingDate,
      closingDate: originalChecking.closingDate,
      usesManualValuations: originalChecking.usesManualValuations,
    );
    final incomeAmount = Money.fromMajorUnits(value: '1', currency: chf);
    final transferAmount = Money.fromMajorUnits(value: '1', currency: chf);
    final date = DateTime.utc(2026, 10, 10);
    final allocation = IncomeAllocation(
      id: 'precision-allocation',
      name: 'Precision allocation',
      incomeCategoryId: 'salary',
      incomeAccountId: checking.id,
      transferCategoryId: 'general',
      expectedAmountPerIncome: incomeAmount,
      startDate: date,
      endDate: date,
      createdAt: date,
      updatedAt: date,
    );
    final data = AppDataSnapshot(
      accounts: [
        for (final account in source.accounts)
          account.id == checking.id ? checking : account,
      ],
      categories: source.categories,
      currencies: [...source.currencies, chf],
      tags: source.tags,
      transactions: [
        Transaction(
          id: 'precision-income',
          createdAt: date,
          date: date,
          type: TransactionType.income,
          sourceAmount: null,
          sourceAccountId: null,
          destinationAmount: incomeAmount,
          destinationAccountId: checking.id,
          categoryId: 'salary',
          tagId: null,
          description: 'Income',
        ),
        Transaction(
          id: 'precision-transfer',
          createdAt: date,
          date: date,
          type: TransactionType.transfer,
          sourceAmount: transferAmount,
          sourceAccountId: checking.id,
          destinationAmount: incomeAmount,
          destinationAccountId: checking.id,
          categoryId: 'general',
          tagId: null,
          description: 'Transfer',
        ),
      ],
      exchangeRates: const [],
      dailyAccountBalances: source.dailyAccountBalances,
      dailyNetWorth: source.dailyNetWorth,
      dailyManualValuations: source.dailyManualValuations,
      incomeAllocations: [allocation],
    );

    final progress = IncomeAllocationAnalyzer(data)
        .analyze(month: DateTime.utc(2026, 10, 1), incomeCategoryId: 'salary')
        .single;

    expect(progress.actualAmount.minorUnits, 100);
    expect(progress.expectedAmount.minorUnits, 100);
    expect(progress.actualAmount.currencyId, 'CHF');
  });
}

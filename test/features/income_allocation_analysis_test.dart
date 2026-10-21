import 'package:decimal/decimal.dart';
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
      sourceAccountId: checking.id,
      destinationAccountId: credit.id,
      expectedAmountPerIncome: amount,
      descriptionKeyword: null,
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
        categoryId: null,
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

    expect(progress.expectedUsdMinorUnits, 10000);
    expect(progress.actualUsdMinorUnits, 10000);
  });

  test('uses configured USD decimal precision for converted transfers', () async {
    final source = await AssetAppDataRepository().load();
    const usd = CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 3);
    const inr = CurrencyDefinition(id: 'INR', symbol: '₹', decimalPlaces: 2);
    final checking = source.accountsById['chase_checking']!;
    final sbi = source.accountsById['sbi_nro']!;
    final incomeAmount = Money.fromMajorUnits(value: '1', currency: usd);
    final transferAmount = Money.fromMajorUnits(value: '100', currency: inr);
    final date = DateTime.utc(2026, 10, 10);
    final allocation = IncomeAllocation(
      id: 'precision-allocation',
      name: 'Precision allocation',
      incomeCategoryId: 'salary',
      incomeAccountId: checking.id,
      sourceAccountId: sbi.id,
      destinationAccountId: checking.id,
      expectedAmountPerIncome: incomeAmount,
      descriptionKeyword: null,
      startDate: date,
      endDate: date,
      createdAt: date,
      updatedAt: date,
    );
    final data = AppDataSnapshot(
      accounts: source.accounts,
      categories: source.categories,
      currencies: [usd, inr],
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
          sourceAccountId: sbi.id,
          destinationAmount: incomeAmount,
          destinationAccountId: checking.id,
          categoryId: null,
          tagId: null,
          description: 'Transfer',
        ),
      ],
      exchangeRates: [
        ExchangeRate(
          id: 'precision-rate',
          date: date,
          currencyId: 'INR',
          rateToUsd: Decimal.parse('0.123456'),
          sourceRateDate: date,
          retrievedAt: date,
        ),
      ],
      dailyAccountBalances: source.dailyAccountBalances,
      dailyNetWorth: source.dailyNetWorth,
      dailyManualValuations: source.dailyManualValuations,
      incomeAllocations: [allocation],
    );

    final progress = IncomeAllocationAnalyzer(data).analyze(
      month: DateTime.utc(2026, 10, 1),
      incomeCategoryId: 'salary',
    ).single;

    expect(progress.actualUsdMinorUnits, 12346);
  });
}

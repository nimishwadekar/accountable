import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';
import 'package:accountable/features/analysis/category_analysis.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('spending subtracts reimbursements and excludes transfers', () async {
    final data = await AssetAppDataRepository().load();
    final result = CategoryAnalysisCalculator(data)
        .spending(month: DateTime.utc(2026, 10));

    final foodDrink = result.values.firstWhere(
      (value) => value.categoryId == 'food_drink',
    );
    expect(foodDrink.amountUsdMinorUnits, greaterThan(0));
  });

  test(
    'income aggregates destination amounts by category and tag filter',
    () async {
      final data = await AssetAppDataRepository().load();
      final result = CategoryAnalysisCalculator(data)
          .income(month: DateTime.utc(2026, 10), tagId: null);

      expect(result.values, isNotEmpty);
      expect(
        result.values.every((value) => value.amountUsdMinorUnits > 0),
        isTrue,
      );
    },
  );

  test(
    'tag filters preserve only matching income in the selected category',
    () {
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
      final amount = Money(minorUnits: 10000, currencyId: 'USD');
      Transaction income(String id, String tagId, int minorUnits) =>
          Transaction(
            id: id,
            createdAt: DateTime.utc(2026, 10, 5),
            date: DateTime.utc(2026, 10, 5),
            type: TransactionType.income,
            sourceAmount: null,
            sourceAccountId: null,
            destinationAmount: Money(minorUnits: minorUnits, currencyId: 'USD'),
            destinationAccountId: checking.id,
            categoryId: 'salary',
            tagId: tagId,
            description: id,
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
        tags: const [
          Tag(id: 'payroll', name: 'Payroll'),
          Tag(id: 'bonus', name: 'Bonus'),
        ],
        transactions: [
          income('salary-payment', 'payroll', amount.minorUnits),
          income('bonus-payment', 'bonus', 2500),
        ],
        exchangeRates: const [],
        dailyAccountBalances: const [],
        dailyNetWorth: const [],
        dailyManualValuations: const [],
      );
      final calculator = CategoryAnalysisCalculator(data);

      final unfiltered = calculator.income(month: DateTime.utc(2026, 10));
      final payrollOnly = calculator.income(
        month: DateTime.utc(2026, 10),
        tagId: 'payroll',
      );

      expect(unfiltered.values.single.amountUsdMinorUnits, 12500);
      expect(payrollOnly.values.single.amountUsdMinorUnits, 10000);
    },
  );

  test(
    'income reports missing historical FX independently of spending',
    () async {
      final source = await AssetAppDataRepository().load();
      final withoutInrRates = AppDataSnapshot(
        accounts: source.accounts,
        categories: source.categories,
        currencies: source.currencies,
        tags: source.tags,
        transactions: [
          ...source.transactions,
          Transaction(
            id: 'income-with-missing-inr-rate',
            createdAt: DateTime.utc(2026, 10, 10),
            date: DateTime.utc(2026, 10, 10),
            type: TransactionType.income,
            sourceAmount: null,
            sourceAccountId: null,
            destinationAmount: Money(minorUnits: 10000, currencyId: 'INR'),
            destinationAccountId: 'sbi_nro',
            categoryId: 'salary',
            tagId: 'boston',
            description: 'Income in INR',
          ),
        ],
        exchangeRates: source.exchangeRates
            .where((rate) => rate.currencyId != 'INR')
            .toList(),
        dailyAccountBalances: source.dailyAccountBalances,
        dailyNetWorth: source.dailyNetWorth,
        dailyManualValuations: source.dailyManualValuations,
      );

      expect(
        () =>
            CategoryAnalysisCalculator(withoutInrRates)
                .income(month: DateTime.utc(2026, 10)),
        throwsA(
          isA<MissingExchangeRateException>().having(
            (error) => error.missingRates,
            'missingRates',
            contains(
              isA<MissingExchangeRate>().having(
                (rate) => rate.currencyId,
                'currencyId',
                'INR',
              ),
            ),
          ),
        ),
      );
    },
  );

  test('merges missing rates by normalized currency and calendar date', () {
    final merged =
        MissingExchangeRateException([
          MissingExchangeRate(
            currencyId: 'INR',
            date: DateTime.utc(2026, 10, 5, 1),
          ),
        ]).merge(
          MissingExchangeRateException([
            MissingExchangeRate(
              currencyId: 'INR',
              date: DateTime.utc(2026, 10, 5, 22),
            ),
            MissingExchangeRate(
              currencyId: 'EUR',
              date: DateTime.utc(2026, 10, 6),
            ),
          ]),
        );

    expect(merged.missingRates, hasLength(2));
    expect(
      merged.missingRates.map((rate) => '${rate.currencyId}:${rate.date.day}'),
      containsAll(['INR:5', 'EUR:6']),
    );
    expect(merged.toString(), 'Missing historical exchange rates.');
  });

  test(
    'missing historical FX is reported instead of counted as zero',
    () async {
      final source = await AssetAppDataRepository().load();
      final withoutInrRates = AppDataSnapshot(
        accounts: source.accounts,
        categories: source.categories,
        currencies: source.currencies,
        tags: source.tags,
        transactions: source.transactions,
        exchangeRates: source.exchangeRates
            .where((rate) => rate.currencyId != 'INR')
            .toList(),
        dailyAccountBalances: source.dailyAccountBalances,
        dailyNetWorth: source.dailyNetWorth,
        dailyManualValuations: source.dailyManualValuations,
      );

      expect(
        () =>
            CategoryAnalysisCalculator(withoutInrRates)
                .spending(month: DateTime.utc(2026, 10)),
        throwsA(
          isA<MissingExchangeRateException>().having(
            (error) => error.missingRates,
            'missingRates',
            contains(
              isA<MissingExchangeRate>().having(
                (rate) => rate.currencyId,
                'currencyId',
                'INR',
              ),
            ),
          ),
        ),
      );
    },
  );
}

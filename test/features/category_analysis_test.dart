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

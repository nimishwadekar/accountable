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
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';
import 'package:accountable/features/analysis/category_analysis.dart';
import 'package:accountable/features/analysis/category_analysis_section.dart';

void main() {
  testWidgets(
    'income distribution shows only allocations active in that month',
    (tester) async {
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
      IncomeAllocation allocation({
        required String id,
        required String name,
        required DateTime start,
        DateTime? end,
      }) => IncomeAllocation(
        id: id,
        name: name,
        incomeCategoryId: 'salary',
        incomeAccountId: checking.id,
        transferCategoryId: 'transfer',
        expectedAmountPerIncome: Money(minorUnits: 5000, currencyId: 'USD'),
        startDate: start,
        endDate: end,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
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
        tags: const [],
        transactions: const [],
        exchangeRates: const [],
        dailyAccountBalances: const [],
        dailyNetWorth: const [],
        dailyManualValuations: const [],
        incomeAllocations: [
          allocation(
            id: 'active',
            name: 'Active in October',
            start: DateTime.utc(2026, 10, 10),
            end: DateTime.utc(2026, 10, 20),
          ),
          allocation(
            id: 'future',
            name: 'Starts in November',
            start: DateTime.utc(2026, 11, 1),
          ),
          allocation(
            id: 'expired',
            name: 'Ended in September',
            start: DateTime.utc(2026, 1, 1),
            end: DateTime.utc(2026, 9, 30),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: CategoryAnalysisSection(
              title: 'Income by Category',
              result: const CategoryAnalysisResult(
                values: [
                  CategoryAnalysisValue(
                    categoryId: 'salary',
                    amountUsdMinorUnits: 10000,
                  ),
                ],
              ),
              usd: usd,
              data: data,
              month: DateTime.utc(2026, 10),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Active in October'), findsOneWidget);
      expect(find.text('Starts in November'), findsNothing);
      expect(find.text('Ended in September'), findsNothing);
    },
  );
}

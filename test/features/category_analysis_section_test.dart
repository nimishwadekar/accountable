import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';

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

  testWidgets('compact pie paint stays inside the chart card border', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: CategoryAnalysisSection(
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
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    final pieFinder = find.byType(PieChart);
    final pie = tester.widget<PieChart>(pieFinder);
    final pieSize = tester.getSize(pieFinder);
    final outerRadius =
        pie.data.centerSpaceRadius +
        pie.data.sections.fold<double>(
          0,
          (largest, section) =>
              section.radius > largest ? section.radius : largest,
        );
    final cardRect = tester.getRect(find.byType(Card));
    final pieRect = tester.getRect(pieFinder);
    final paintedTop = pieRect.center.dy - outerRadius;
    final paintedBottom = pieRect.center.dy + outerRadius;

    expect(pieSize.width, pieSize.height);
    expect(outerRadius, lessThanOrEqualTo(pieSize.shortestSide / 2));
    expect(paintedTop, greaterThanOrEqualTo(cardRect.top));
    expect(paintedBottom, lessThanOrEqualTo(cardRect.bottom));
  });

  testWidgets(
    '320px category rows retain full amounts and allocation details',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const usd = CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2);
      const categoryName = 'Employment and other recurring income';
      const allocationName =
          'Emergency savings allocation for the next several months';
      final data = _analysisData(
        allocations: [
          IncomeAllocation(
            id: 'savings',
            name: allocationName,
            incomeCategoryId: 'salary',
            incomeAccountId: 'checking',
            transferCategoryId: 'transfer',
            expectedAmountPerIncome: Money(minorUnits: 5000, currencyId: 'USD'),
            startDate: DateTime.utc(2026, 10, 1),
            endDate: null,
            createdAt: DateTime.utc(2026, 10, 1),
            updatedAt: DateTime.utc(2026, 10, 1),
          ),
        ],
        transactions: [
          Transaction(
            id: 'salary',
            createdAt: DateTime.utc(2026, 10, 2),
            date: DateTime.utc(2026, 10, 2),
            type: TransactionType.income,
            sourceAmount: null,
            sourceAccountId: null,
            destinationAmount: Money(minorUnits: 12000, currencyId: 'USD'),
            destinationAccountId: 'checking',
            categoryId: 'salary',
            tagId: null,
            description: 'Pay day',
          ),
          Transaction(
            id: 'allocation-transfer',
            createdAt: DateTime.utc(2026, 10, 4),
            date: DateTime.utc(2026, 10, 4),
            type: TransactionType.transfer,
            sourceAmount: Money(minorUnits: 3500, currencyId: 'USD'),
            sourceAccountId: 'checking',
            destinationAmount: Money(minorUnits: 3500, currencyId: 'USD'),
            destinationAccountId: 'checking',
            categoryId: 'transfer',
            tagId: null,
            description: 'Savings transfer',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: CategoryAnalysisSection(
                title: 'Income by Category',
                result: const CategoryAnalysisResult(
                  values: [
                    CategoryAnalysisValue(
                      categoryId: 'salary',
                      amountUsdMinorUnits: 12345678901,
                    ),
                    CategoryAnalysisValue(
                      categoryId: 'salary',
                      amountUsdMinorUnits: -1250,
                    ),
                  ],
                ),
                usd: usd,
                data: data,
                month: DateTime.utc(2026, 10),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(categoryName), findsOneWidget);
      expect(find.text(allocationName), findsOneWidget);
      expect(find.text(r'$ 123,456,789.01'), findsNWidgets(2));
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        ),
        findsNothing,
      );
      expect(find.text(r'$ 35.00'), findsOneWidget);
      expect(find.text(r'$ 50.00'), findsOneWidget);
      expect(find.text('Net reimbursement adjustment:'), findsOneWidget);
      expect(find.text(r'$ -12.50'), findsOneWidget);
      expect(find.text('Actual'), findsOneWidget);
      expect(find.text('Expected'), findsOneWidget);
      expect(find.text('70%'), findsOneWidget);
      expect(
        tester.getRect(find.byType(LinearProgressIndicator)).width,
        greaterThan(180),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('extreme compact monetary values remain available by scrolling', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const usd = CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2);
    const amount = r'$ 123,456,789,012,345.67';
    final data = _analysisData();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: CategoryAnalysisSection(
                title: 'Income by Category',
                result: const CategoryAnalysisResult(
                  values: [
                    CategoryAnalysisValue(
                      categoryId: 'salary',
                      amountUsdMinorUnits: 12345678901234567,
                    ),
                  ],
                ),
                usd: usd,
                data: data,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(amount), findsNWidgets(2));
    final horizontalAmountScrolls = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    );
    expect(horizontalAmountScrolls, findsAtLeastNWidgets(2));
    final categoryAmountScroll = horizontalAmountScrolls.first;
    final categoryAmountScrollable = find
        .descendant(of: categoryAmountScroll, matching: find.byType(Scrollable))
        .first;
    final scrollPosition = tester
        .state<ScrollableState>(categoryAmountScrollable)
        .position;
    expect(scrollPosition.maxScrollExtent, greaterThan(0));
    await tester.drag(categoryAmountScroll, const Offset(-80, 0));
    await tester.pump();
    expect(scrollPosition.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('complete category amounts fit throughout phone widths', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const usd = CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2);
    const amount = r'$ 123,456,789.01';
    final data = _analysisData();
    for (final width in [320.0, 360.0, 390.0, 430.0, 600.0, 1280.0]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: CategoryAnalysisSection(
                title: 'Income by Category',
                result: const CategoryAnalysisResult(
                  values: [
                    CategoryAnalysisValue(
                      categoryId: 'salary',
                      amountUsdMinorUnits: 12345678901,
                    ),
                  ],
                ),
                usd: usd,
                data: data,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text(amount), findsAtLeastNWidgets(2), reason: '$width px');
      expect(tester.takeException(), isNull, reason: '$width px');
    }
  });
}

AppDataSnapshot _analysisData({
  List<IncomeAllocation> allocations = const [],
  List<Transaction> transactions = const [],
}) {
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
  return AppDataSnapshot(
    accounts: [checking],
    categories: const [
      Category(
        id: 'salary',
        name: 'Employment and other recurring income',
        allowedTransactionTypes: {TransactionType.income},
      ),
      Category(
        id: 'transfer',
        name: 'Savings transfer',
        allowedTransactionTypes: {TransactionType.transfer},
      ),
    ],
    currencies: const [usd],
    tags: const [],
    transactions: transactions,
    exchangeRates: const [],
    dailyAccountBalances: const [],
    dailyNetWorth: const [],
    dailyManualValuations: const [],
    incomeAllocations: allocations,
  );
}

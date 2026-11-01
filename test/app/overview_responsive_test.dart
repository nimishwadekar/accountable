import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/formatters.dart';
import 'package:accountable/app/pages/app_pages.dart';
import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/app/theme/design_tokens.dart';
import 'package:accountable/data/data.dart';

void main() {
  late final AppDataSnapshot source;

  setUpAll(() async {
    source = await AssetAppDataRepository().load();
  });

  testWidgets('Overview metrics stack with complete values on a phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final data = _withNetWorth(source, _twoMonthHistory());
    final expectedNetWorth = formatMoney(
      Money(minorUnits: 600000, currencyId: 'USD'),
      data.currenciesById,
    );
    final expectedAverage = formatMoney(
      Money(minorUnits: 500000, currencyId: 'USD'),
      data.currenciesById,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(320, 900)),
          child: Scaffold(body: OverviewPage(data: data)),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(MetricCard), findsNWidgets(3));
    expect(find.text('Net worth'), findsOneWidget);
    expect(find.text('Cash balances'), findsOneWidget);
    expect(find.text('Assets & liabilities'), findsOneWidget);
    expect(find.text(expectedNetWorth), findsOneWidget);
    expect(find.text(expectedAverage), findsOneWidget);
    expect(find.textContaining('Average'), findsNWidgets(2));
    expect(
      tester.widget<Text>(find.text(expectedAverage)).style?.color,
      AppColors.success,
    );
    expect(tester.takeException(), isNull);

    final metricCards = find.byType(MetricCard);
    final rects = [
      for (
        var index = 0;
        index < tester.widgetList(metricCards).length;
        index++
      )
        tester.getRect(metricCards.at(index)),
    ];
    for (final rect in rects) {
      expect(rect.left, greaterThanOrEqualTo(16));
      expect(rect.right, lessThanOrEqualTo(304));
      expect(rect.width, 288);
      expect(
        rect.height,
        lessThanOrEqualTo(136),
        reason: 'Retain metric content while trimming excess card padding.',
      );
    }

    final horizontalScrollViews = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    );
    expect(horizontalScrollViews, findsNothing);

    final now = DateTime.now().toUtc();
    final previousMonth = DateTime.utc(now.year, now.month - 1);
    final currentMonth = DateTime.utc(now.year, now.month);
    final huge = Money(minorUnits: 987654321012345678, currencyId: 'USD');
    final hugeData = _withNetWorth(source, [
      DailyNetWorth(
        id: 'p2-huge-prev',
        date: previousMonth,
        amount: Money(minorUnits: huge.minorUnits - 1000, currencyId: 'USD'),
        retrievedAt: now,
      ),
      DailyNetWorth(
        id: 'p2-huge-current',
        date: currentMonth,
        amount: huge,
        retrievedAt: now,
      ),
    ]);
    final completeLabel = formatMoney(huge, hugeData.currenciesById);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(320, 900)),
          child: Scaffold(body: OverviewPage(data: hugeData)),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(completeLabel), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text(completeLabel),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        ),
      ),
      findsOneWidget,
      reason: 'Only an extreme value uses the full-value scroll fallback.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('net-worth summary uses red/green/gray by signed value', (
    tester,
  ) async {
    const size = Size(390, 844);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now().toUtc();
    final previousMonth = DateTime.utc(now.year, now.month - 1, 1);
    final currentMonth = DateTime.utc(now.year, now.month, 1);

    for (final (currentMinorUnits, expectedColor) in [
      (-2000, AppColors.danger),
      (0, AppColors.mutedText),
    ]) {
      final data = _withNetWorth(source, [
        DailyNetWorth(
          id: 'previous-month',
          date: previousMonth,
          amount: const Money(minorUnits: 1000, currencyId: 'USD'),
          retrievedAt: now,
        ),
        DailyNetWorth(
          id: 'current-month',
          date: currentMonth,
          amount: Money(minorUnits: currentMinorUnits, currencyId: 'USD'),
          retrievedAt: now,
        ),
      ]);
      final expectedValue = formatMoney(
        Money(minorUnits: currentMinorUnits, currencyId: 'USD'),
        data.currenciesById,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(size: size),
            child: Scaffold(body: NetWorthSummarySection(data: data)),
          ),
        ),
      );
      await tester.pump();

      final values = tester.widgetList<Text>(find.text(expectedValue));
      expect(values, hasLength(2));
      expect(
        values.map((text) => text.style?.color),
        everyElement(expectedColor),
      );
      expect(tester.takeException(), isNull);
    }
  });
}

List<DailyNetWorth> _twoMonthHistory() {
  final now = DateTime.now().toUtc();
  final currentMonth = DateTime.utc(now.year, now.month);
  final previousMonth = DateTime.utc(now.year, now.month - 1);
  return [
    DailyNetWorth(
      id: 'p2-net-worth-prev-a',
      date: previousMonth,
      amount: Money(minorUnits: 100000, currencyId: 'USD'),
      retrievedAt: now,
    ),
    DailyNetWorth(
      id: 'p2-net-worth-prev-b',
      date: previousMonth.add(const Duration(days: 1)),
      amount: Money(minorUnits: 200000, currencyId: 'USD'),
      retrievedAt: now,
    ),
    DailyNetWorth(
      id: 'p2-net-worth-current-a',
      date: currentMonth,
      amount: Money(minorUnits: 400000, currencyId: 'USD'),
      retrievedAt: now,
    ),
    DailyNetWorth(
      id: 'p2-net-worth-current-b',
      date: currentMonth.add(const Duration(days: 1)),
      amount: Money(minorUnits: 600000, currencyId: 'USD'),
      retrievedAt: now,
    ),
  ];
}

AppDataSnapshot _withNetWorth(
  AppDataSnapshot source,
  List<DailyNetWorth> dailyNetWorth,
) => AppDataSnapshot(
  accounts: source.accounts,
  categories: source.categories,
  currencies: source.currencies,
  tags: source.tags,
  transactions: source.transactions,
  transactionsToMigrate: source.transactionsToMigrate,
  exchangeRates: source.exchangeRates,
  dailyAccountBalances: source.dailyAccountBalances,
  dailyNetWorth: dailyNetWorth,
  dailyManualValuations: source.dailyManualValuations,
  displayPreferences: source.displayPreferences,
  transactionTemplates: source.transactionTemplates,
  incomeAllocations: source.incomeAllocations,
  achievements: source.achievements,
  achievementStartDate: source.achievementStartDate,
);

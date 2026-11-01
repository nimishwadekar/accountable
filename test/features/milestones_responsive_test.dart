import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';
import 'package:accountable/features/milestones/milestones_page.dart';

void main() {
  testWidgets(
    'short enlarged celebration remains readable, static, and actionable',
    (tester) async {
      const size = Size(320, 520);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final source = await AssetAppDataRepository().load();
      final now = DateTime.now();
      final previousMonth = DateTime.utc(now.year, now.month - 1);
      final data = AppDataSnapshot(
        accounts: source.accounts,
        categories: source.categories,
        currencies: source.currencies,
        tags: source.tags,
        transactions: source.transactions,
        transactionsToMigrate: source.transactionsToMigrate,
        exchangeRates: source.exchangeRates,
        dailyAccountBalances: source.dailyAccountBalances,
        dailyNetWorth: _fullMonth(previousMonth, 10000),
        dailyManualValuations: source.dailyManualValuations,
        displayPreferences: source.displayPreferences,
        transactionTemplates: source.transactionTemplates,
        incomeAllocations: source.incomeAllocations,
        achievements: [
          NetWorthAchievement(
            id: 'P2-RESPONSIVE',
            name: 'A long-term financial foundation',
            target: Money(minorUnits: 5000, currencyId: 'USD'),
            earned: false,
          ),
        ],
        achievementStartDate: previousMonth,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                size: size,
                textScaler: const TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: Scaffold(
                body: MilestonesPage(
                  data: data,
                  onAchievementAcknowledged: (_) async {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('You did it!'), findsOneWidget);
      expect(find.text('A long-term financial foundation'), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome), findsNothing);
      final animation = find.byWidgetPredicate(
        (widget) => widget is TweenAnimationBuilder<double>,
      );
      expect(
        tester.widget<TweenAnimationBuilder<double>>(animation).duration,
        Duration.zero,
      );
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Continue'));
      expect(
        tester.getRect(find.text('Continue')).bottom,
        lessThanOrEqualTo(520),
      );
      expect(tester.takeException(), isNull);
    },
  );
}

List<DailyNetWorth> _fullMonth(DateTime month, int minorUnits) {
  final dayCount = DateTime.utc(month.year, month.month + 1, 0).day;
  final retrievedAt = DateTime.now().toUtc();
  return [
    for (var day = 1; day <= dayCount; day++)
      DailyNetWorth(
        id: 'p2-responsive-${month.year}-${month.month}-$day',
        date: DateTime.utc(month.year, month.month, day),
        amount: Money(minorUnits: minorUnits, currencyId: 'USD'),
        retrievedAt: retrievedAt,
      ),
  ];
}

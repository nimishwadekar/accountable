import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';
import 'package:accountable/features/milestones/milestones_page.dart';
import 'package:accountable/app/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('celebrates retroactive milestones one at a time', (
    tester,
  ) async {
    final source = await AssetAppDataRepository().load();
    final now = DateTime.now();
    final currentMonth = DateTime.utc(now.year, now.month);
    final previousMonth = DateTime.utc(
      currentMonth.year,
      currentMonth.month - 1,
    );
    final data = _snapshotWithAchievements(
      source,
      startDate: previousMonth,
      dailyNetWorth: [
        ..._month(previousMonth.year, previousMonth.month, 10000),
        for (var day = 1; day < now.day; day++)
          DailyNetWorth(
            id: 'current-$day',
            date: DateTime.utc(now.year, now.month, day),
            amount: Money(minorUnits: 7500, currencyId: 'USD'),
            retrievedAt: DateTime.now().toUtc(),
          ),
      ],
      achievements: [
        _achievement('ACH001', 'A fresh start', 50),
        _achievement('ACH002', 'A stronger foundation', 100),
        _achievement('ACH003', 'A new frontier', 150),
      ],
    );
    final acknowledged = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: MilestonesPage(
            data: data,
            onAchievementAcknowledged: (id) async => acknowledged.add(id),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('You did it!'), findsOneWidget);
    expect(find.text('A fresh start'), findsOneWidget);
    expect(find.text('A stronger foundation'), findsNothing);
    expect(find.text('A new frontier'), findsNothing);

    await tester.ensureVisible(find.text('Celebrate next'));
    await tester.tap(find.text('Celebrate next'));
    await tester.pump();
    expect(acknowledged, ['ACH001']);
    expect(find.text('A stronger foundation'), findsOneWidget);

    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(acknowledged, ['ACH001', 'ACH002']);
    expect(find.text('Last completed month average'), findsOneWidget);
    expect(find.textContaining('Provisional'), findsNothing);
    expect(find.text('A fresh start'), findsOneWidget);
    expect(find.text('A stronger foundation'), findsOneWidget);
    expect(find.text('PROGRESS TOWARD'), findsOneWidget);
    expect(find.text('A new frontier'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

AppDataSnapshot _snapshotWithAchievements(
  AppDataSnapshot source, {
  required DateTime startDate,
  required List<DailyNetWorth> dailyNetWorth,
  required List<NetWorthAchievement> achievements,
}) => AppDataSnapshot(
  accounts: source.accounts,
  categories: source.categories,
  currencies: source.currencies,
  tags: source.tags,
  transactions: source.transactions,
  exchangeRates: source.exchangeRates,
  dailyAccountBalances: source.dailyAccountBalances,
  dailyNetWorth: dailyNetWorth,
  dailyManualValuations: source.dailyManualValuations,
  achievements: achievements,
  achievementStartDate: startDate,
);

NetWorthAchievement _achievement(String id, String name, int targetDollars) =>
    NetWorthAchievement(
      id: id,
      name: name,
      target: Money(minorUnits: targetDollars * 100, currencyId: 'USD'),
      earned: false,
    );

List<DailyNetWorth> _month(int year, int month, int minorUnits) {
  final dayCount = DateTime.utc(year, month + 1, 0).day;
  return [
    for (var day = 1; day <= dayCount; day++)
      DailyNetWorth(
        id: 'earned-$year-$month-$day',
        date: DateTime.utc(year, month, day),
        amount: Money(minorUnits: minorUnits, currencyId: 'USD'),
        retrievedAt: DateTime.now().toUtc(),
      ),
  ];
}

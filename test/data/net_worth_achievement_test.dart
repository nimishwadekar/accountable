import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';

void main() {
  const usd = CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2);

  test('parses signed targets, earned booleans, and the settings date', () {
    final achievements = ModelParsers.parseAchievements(
      'achievement_id,name,target_usd,earned\n'
      'ACH001,Recovery One,-12000,FALSE\n'
      'ACH002,Break Even,0,TRUE\n',
      currencies: {'USD': usd},
    );
    final settings = ModelParsers.parseAchievementSettings(
      'tracking_start_date\n2026-10-01\n',
    );

    expect(achievements.map((item) => item.target.minorUnits), [-1200000, 0]);
    expect(achievements.map((item) => item.earned), [false, true]);
    expect(settings.trackingStartDate, DateTime.utc(2026, 10, 1));
  });

  test('validates target order and uniqueness', () {
    final descending = ModelParsers.parseAchievementsWithIssues(
      'achievement_id,name,target_usd,earned\n'
      'ACH001,First,100,FALSE\n'
      'ACH002,Second,50,FALSE\n',
      currencies: {'USD': usd},
    );
    final duplicate = ModelParsers.parseAchievementsWithIssues(
      'achievement_id,name,target_usd,earned\n'
      'ACH001,First,100,FALSE\n'
      'ACH002,Second,100,FALSE\n',
      currencies: {'USD': usd},
    );

    expect(descending.issues, isNotEmpty);
    expect(duplicate.issues, isNotEmpty);
  });

  test('uses only full months after the effective tracking start', () {
    final points = <DailyNetWorth>[
      ..._month(2025, 1, -500000), // Partial start month must not qualify.
      ..._month(2025, 2, -1200000),
      ..._month(2025, 3, -800000),
    ];
    final result = NetWorthAchievementCalculator.evaluate(
      dailyNetWorth: points,
      trackingStartDate: DateTime.utc(2025, 1, 15),
      achievements: [
        _achievement('lower', -14000),
        _achievement('upper', -10000),
        _achievement('break-even', 0),
      ],
      today: DateTime.utc(2025, 4, 1),
    );

    expect(result.firstEligibleMonth, DateTime.utc(2025, 2, 1));
    expect(result.firstEligibleMonthAverage?.minorUnits, -1200000);
    expect(result.progress[0].qualifyingMonth, DateTime.utc(2025, 2, 1));
    expect(result.progress[1].qualifyingMonth, DateTime.utc(2025, 3, 1));
    expect(result.progress[2].qualifies, isFalse);
  });

  test(
    'clamps a start before history to the first available daily snapshot',
    () {
      final result = NetWorthAchievementCalculator.evaluate(
        dailyNetWorth: _month(2025, 1, -1200000),
        trackingStartDate: DateTime.utc(2024, 1, 1),
        achievements: [_achievement('target', -14000)],
        today: DateTime.utc(2025, 3, 1),
      );

      expect(result.effectiveStartDate, DateTime.utc(2025, 1, 1));
      expect(result.firstEligibleMonth, DateTime.utc(2025, 1, 1));
      expect(result.progress.single.qualifyingMonth, DateTime.utc(2025, 1, 1));
    },
  );

  test('does not qualify a month with a missing daily snapshot', () {
    final points = _month(2025, 1, -800000)
      ..removeWhere((point) => point.date == DateTime.utc(2025, 1, 12));
    final result = NetWorthAchievementCalculator.evaluate(
      dailyNetWorth: points,
      trackingStartDate: DateTime.utc(2025, 1, 1),
      achievements: [_achievement('target', -14000)],
      today: DateTime.utc(2025, 2, 1),
    );

    expect(result.incompleteCompletedMonths, [DateTime.utc(2025, 1, 1)]);
    expect(result.progress.single.qualifies, isFalse);
  });

  test('allows several targets to qualify in the same completed month', () {
    final result = NetWorthAchievementCalculator.evaluate(
      dailyNetWorth: _month(2025, 1, 1000000),
      trackingStartDate: DateTime.utc(2025, 1, 1),
      achievements: [_achievement('one', 5000), _achievement('two', 10000)],
      today: DateTime.utc(2025, 2, 1),
    );

    expect(result.progress.map((item) => item.qualifyingMonth), [
      DateTime.utc(2025, 1, 1),
      DateTime.utc(2025, 1, 1),
    ]);
    expect(result.pendingCelebrations, hasLength(2));
  });

  test('resets an earned flag only when complete history disproves it', () {
    final complete = NetWorthAchievementCalculator.evaluate(
      dailyNetWorth: _month(2025, 1, -1200000),
      trackingStartDate: DateTime.utc(2025, 1, 1),
      achievements: [_achievement('target', 1000, earned: true)],
      today: DateTime.utc(2025, 2, 1),
    );
    final incompletePoints = _month(2025, 1, -1200000)
      ..removeWhere((point) => point.date == DateTime.utc(2025, 1, 12));
    final incomplete = NetWorthAchievementCalculator.evaluate(
      dailyNetWorth: incompletePoints,
      trackingStartDate: DateTime.utc(2025, 1, 1),
      achievements: [_achievement('target', 1000, earned: true)],
      today: DateTime.utc(2025, 2, 1),
    );

    expect(complete.earnedFlagsToReset, ['target']);
    expect(incomplete.earnedFlagsToReset, isEmpty);
  });
}

NetWorthAchievement _achievement(
  String id,
  int targetDollars, {
  bool earned = false,
}) => NetWorthAchievement(
  id: id,
  name: id,
  target: Money(minorUnits: targetDollars * 100, currencyId: 'USD'),
  earned: earned,
);

List<DailyNetWorth> _month(int year, int month, int minorUnits) {
  final days = DateTime.utc(year, month + 1, 0).day;
  return [
    for (var day = 1; day <= days; day++)
      DailyNetWorth(
        id: '2025-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}-net',
        date: DateTime.utc(year, month, day),
        amount: Money(minorUnits: minorUnits, currencyId: 'USD'),
        retrievedAt: DateTime.utc(year, month, day),
      ),
  ];
}

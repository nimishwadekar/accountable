import 'models/daily_net_worth.dart';
import 'models/money.dart';
import 'models/net_worth_achievement.dart';

class CompletedNetWorthMonth {
  const CompletedNetWorthMonth({
    required this.month,
    required this.average,
    required this.snapshotCount,
  });

  final DateTime month;
  final Money average;
  final int snapshotCount;
}

class NetWorthAchievementProgress {
  const NetWorthAchievementProgress({
    required this.achievement,
    required this.qualifyingMonth,
    required this.qualifyingAverage,
  });

  final NetWorthAchievement achievement;
  final DateTime? qualifyingMonth;
  final Money? qualifyingAverage;

  bool get qualifies => qualifyingMonth != null;
  bool get celebrationPending => qualifies && !achievement.earned;
}

class NetWorthAchievementEvaluation {
  const NetWorthAchievementEvaluation({
    required this.effectiveStartDate,
    required this.firstEligibleMonth,
    required this.completedMonths,
    required this.incompleteCompletedMonths,
    required this.firstEligibleMonthAverage,
    required this.monthToDateAverage,
    required this.monthToDateAsOf,
    required this.monthToDateSnapshotCount,
    required this.monthToDateExpectedSnapshotCount,
    required this.progress,
    required this.earnedFlagsToReset,
    required this.validationErrors,
  });

  final DateTime? effectiveStartDate;
  final DateTime? firstEligibleMonth;
  final List<CompletedNetWorthMonth> completedMonths;
  final List<DateTime> incompleteCompletedMonths;
  final Money? firstEligibleMonthAverage;
  final Money? monthToDateAverage;
  final DateTime? monthToDateAsOf;
  final int monthToDateSnapshotCount;
  final int monthToDateExpectedSnapshotCount;
  final List<NetWorthAchievementProgress> progress;
  final List<String> earnedFlagsToReset;
  final List<String> validationErrors;

  List<NetWorthAchievementProgress> get pendingCelebrations =>
      incompleteCompletedMonths.isNotEmpty
      ? const []
      : List.unmodifiable(progress.where((item) => item.celebrationPending));

  bool get hasMonthToDateGaps =>
      monthToDateSnapshotCount < monthToDateExpectedSnapshotCount;
}

class NetWorthAchievementCalculator {
  const NetWorthAchievementCalculator._();

  static NetWorthAchievementEvaluation evaluate({
    required List<DailyNetWorth> dailyNetWorth,
    required DateTime trackingStartDate,
    required List<NetWorthAchievement> achievements,
    DateTime? today,
  }) {
    final validationErrors = <String>[];
    final byDate = <DateTime, DailyNetWorth>{};
    for (final point in dailyNetWorth) {
      final date = _dateOnly(point.date);
      if (byDate.containsKey(date)) {
        validationErrors.add(
          'Daily net worth contains more than one snapshot for ${_dateString(date)}.',
        );
      } else {
        byDate[date] = point;
      }
    }

    final achievementIds = <String>{};
    int? previousTarget;
    for (final achievement in achievements) {
      if (achievement.target.currencyId != 'USD') {
        validationErrors.add(
          'Achievement ${achievement.id} must have a USD target.',
        );
      }
      if (previousTarget != null &&
          achievement.target.minorUnits <= previousTarget) {
        validationErrors.add(
          'Achievement targets must be unique and in ascending order.',
        );
      }
      if (!achievementIds.add(achievement.id)) {
        validationErrors.add('Achievement IDs must be unique.');
      }
      previousTarget = achievement.target.minorUnits;
    }

    final dates = byDate.keys.toList()..sort();
    final earliestSnapshot = dates.isEmpty ? null : dates.first;
    final configuredStart = _dateOnly(trackingStartDate);
    final effectiveStart = earliestSnapshot == null
        ? configuredStart
        : configuredStart.isBefore(earliestSnapshot)
        ? earliestSnapshot
        : configuredStart;
    final firstEligibleMonth = _firstFullMonthOnOrAfter(effectiveStart);
    final now = today ?? DateTime.now();
    final todayDate = DateTime.utc(now.year, now.month, now.day);
    final currentMonth = DateTime.utc(now.year, now.month);
    final completedMonths = <CompletedNetWorthMonth>[];
    final incompleteMonths = <DateTime>[];
    final eligibleMonthAverages = <DateTime, Money>{};

    if (dates.isNotEmpty) {
      for (
        var month = firstEligibleMonth;
        month.isBefore(currentMonth);
        month = DateTime.utc(month.year, month.month + 1)
      ) {
        final daysInMonth = DateTime.utc(month.year, month.month + 1, 0).day;
        final monthPoints = [
          for (var day = 1; day <= daysInMonth; day++)
            ?byDate[DateTime.utc(month.year, month.month, day)],
        ];
        if (monthPoints.length != daysInMonth) {
          incompleteMonths.add(month);
          continue;
        }
        final totalMinorUnits = monthPoints.fold<int>(
          0,
          (total, point) => total + point.amount.minorUnits,
        );
        final average = Money(
          minorUnits: (totalMinorUnits / daysInMonth).round(),
          currencyId: 'USD',
        );
        final completed = CompletedNetWorthMonth(
          month: month,
          average: average,
          snapshotCount: monthPoints.length,
        );
        completedMonths.add(completed);
        eligibleMonthAverages[month] = average;
      }
    }

    final progress = <NetWorthAchievementProgress>[];
    final earnedFlagsToReset = <String>[];
    DateTime? previousQualifyingMonth;
    var previousTargetHasCrossing = true;
    for (final achievement in achievements) {
      CompletedNetWorthMonth? qualifyingMonth;
      for (final month in completedMonths) {
        if (month.average.minorUnits >= achievement.target.minorUnits) {
          qualifyingMonth = month;
          break;
        }
      }
      if (qualifyingMonth != null &&
          incompleteMonths.any(
            (incomplete) => !incomplete.isAfter(qualifyingMonth!.month),
          )) {
        qualifyingMonth = null;
      }

      final hasQualifyingMonth = qualifyingMonth != null;
      if (incompleteMonths.isEmpty &&
          hasQualifyingMonth &&
          !previousTargetHasCrossing) {
        validationErrors.add(
          'A higher achievement target qualifies before a lower target.',
        );
      }
      if (incompleteMonths.isEmpty &&
          hasQualifyingMonth &&
          previousQualifyingMonth != null &&
          qualifyingMonth.month.isBefore(previousQualifyingMonth)) {
        validationErrors.add(
          'Achievements must be reached in chronological target order.',
        );
      }
      if (hasQualifyingMonth) {
        previousQualifyingMonth = qualifyingMonth.month;
      }
      previousTargetHasCrossing = hasQualifyingMonth;

      if (achievement.earned &&
          !hasQualifyingMonth &&
          incompleteMonths.isEmpty) {
        earnedFlagsToReset.add(achievement.id);
      }
      progress.add(
        NetWorthAchievementProgress(
          achievement: achievement,
          qualifyingMonth: qualifyingMonth?.month,
          qualifyingAverage: qualifyingMonth?.average,
        ),
      );
    }

    final currentMonthPoints = [
      for (final date in dates)
        if (date.year == currentMonth.year &&
            date.month == currentMonth.month &&
            !date.isAfter(todayDate))
          byDate[date]!,
    ];
    final latestCurrentMonthDate = currentMonthPoints.isEmpty
        ? null
        : currentMonthPoints.last.date;
    final expectedMonthToDateDays = latestCurrentMonthDate == null
        ? 0
        : latestCurrentMonthDate
                  .difference(
                    dates.first.isBefore(currentMonth)
                        ? currentMonth
                        : currentMonthPoints.first.date,
                  )
                  .inDays +
              1;
    final monthToDateAverage = currentMonthPoints.isEmpty
        ? null
        : Money(
            minorUnits:
                (currentMonthPoints.fold<int>(
                          0,
                          (total, point) => total + point.amount.minorUnits,
                        ) /
                        currentMonthPoints.length)
                    .round(),
            currencyId: 'USD',
          );

    return NetWorthAchievementEvaluation(
      effectiveStartDate:
          earliestSnapshot == null || configuredStart.isAfter(earliestSnapshot)
          ? configuredStart
          : earliestSnapshot,
      firstEligibleMonth: dates.isEmpty ? null : firstEligibleMonth,
      completedMonths: List.unmodifiable(completedMonths),
      incompleteCompletedMonths: List.unmodifiable(incompleteMonths),
      firstEligibleMonthAverage: completedMonths.isEmpty
          ? null
          : eligibleMonthAverages[firstEligibleMonth],
      monthToDateAverage: monthToDateAverage,
      monthToDateAsOf: latestCurrentMonthDate,
      monthToDateSnapshotCount: currentMonthPoints.length,
      monthToDateExpectedSnapshotCount: expectedMonthToDateDays,
      progress: List.unmodifiable(progress),
      earnedFlagsToReset: List.unmodifiable(earnedFlagsToReset),
      validationErrors: List.unmodifiable(validationErrors),
    );
  }

  static DateTime _firstFullMonthOnOrAfter(DateTime date) {
    final month = DateTime.utc(date.year, date.month);
    return date.day == 1 ? month : DateTime.utc(month.year, month.month + 1);
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day);

  static String _dateString(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

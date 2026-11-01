// CSV-only entry point for visual audits. Uses the real app/theme/navigation,
// bundled fixture tables, and isolated browser storage; never loads config.json
// or initializes Google authentication/Sheets.
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'package:accountable/app/app.dart';
import 'package:accountable/app/navigation_history.dart';
import 'package:accountable/config/accountable_config.dart';
import 'package:accountable/data/data.dart';

void main() {
  usePathUrlStrategy();
  NavigationHistory.captureInitialPath();
  final milestoneEvidence = Uri.base.queryParameters['milestones'];
  if (milestoneEvidence == 'progress' || milestoneEvidence == 'celebration') {
    runApp(
      AccountableApp(
        dataRepository: _MilestoneEvidenceRepository(
          celebration: milestoneEvidence == 'celebration',
        ),
      ),
    );
    return;
  }
  runApp(
    AccountableApp(
      configLoader: () async => AccountableConfig(
        dataSource: AccountableDataSource.csv,
        migrationAssistance: Uri.base.queryParameters['migration'] == '1',
      ),
    ),
  );
}

/// Adds calendar-relative milestone rows to the isolated CSV audit snapshot.
/// This is visual evidence data only; bundled financial fixtures are untouched.
class _MilestoneEvidenceRepository extends AssetAppDataRepository {
  _MilestoneEvidenceRepository({required this.celebration});

  final bool celebration;
  Future<AppDataSnapshot>? _evidenceSnapshot;

  @override
  Future<AppDataSnapshot> load() =>
      _evidenceSnapshot ??= _withEvidence(super.load());

  @override
  Future<AppDataSnapshot> reload() =>
      _evidenceSnapshot = _withEvidence(super.reload());

  Future<AppDataSnapshot> _withEvidence(Future<AppDataSnapshot> source) async {
    final snapshot = await source;
    final now = DateTime.now();
    final previousMonth = DateTime.utc(now.year, now.month - 1);
    final days = DateTime.utc(
      previousMonth.year,
      previousMonth.month + 1,
      0,
    ).day;
    const monthlyAverage = 150000;
    final achievements = celebration
        ? const [
            NetWorthAchievement(
              id: 'P2-CELEBRATION',
              name: 'A strong financial foundation',
              target: Money(minorUnits: 100000, currencyId: 'USD'),
              earned: false,
            ),
          ]
        : const [
            NetWorthAchievement(
              id: 'P2-EARNED',
              name: 'First milestone achieved',
              target: Money(minorUnits: 100000, currencyId: 'USD'),
              earned: true,
            ),
            NetWorthAchievement(
              id: 'P2-NEXT',
              name: 'Build lasting security',
              target: Money(minorUnits: 250000, currencyId: 'USD'),
              earned: false,
            ),
          ];
    return _copySnapshot(
      snapshot,
      dailyNetWorth: [
        for (var day = 1; day <= days; day++)
          DailyNetWorth(
            id: 'p2-evidence-${previousMonth.year}-${previousMonth.month}-$day',
            date: DateTime.utc(previousMonth.year, previousMonth.month, day),
            amount: const Money(minorUnits: monthlyAverage, currencyId: 'USD'),
            retrievedAt: DateTime.now().toUtc(),
          ),
      ],
      achievements: achievements,
      achievementStartDate: previousMonth,
    );
  }

  @override
  Future<AppDataSnapshot> updateAchievementEarned(
    String achievementId, {
    required bool earned,
  }) async {
    final snapshot = await load();
    final updated = _copySnapshot(
      snapshot,
      achievements: [
        for (final achievement in snapshot.achievements)
          if (achievement.id == achievementId)
            achievement.copyWith(earned: earned)
          else
            achievement,
      ],
      achievementStartDate: snapshot.achievementStartDate,
    );
    _evidenceSnapshot = Future.value(updated);
    return updated;
  }

  AppDataSnapshot _copySnapshot(
    AppDataSnapshot source, {
    List<DailyNetWorth>? dailyNetWorth,
    List<NetWorthAchievement>? achievements,
    required DateTime? achievementStartDate,
  }) => AppDataSnapshot(
    accounts: source.accounts,
    categories: source.categories,
    currencies: source.currencies,
    tags: source.tags,
    transactions: source.transactions,
    transactionsToMigrate: source.transactionsToMigrate,
    exchangeRates: source.exchangeRates,
    dailyAccountBalances: source.dailyAccountBalances,
    dailyNetWorth: dailyNetWorth ?? source.dailyNetWorth,
    dailyManualValuations: source.dailyManualValuations,
    displayPreferences: source.displayPreferences,
    transactionTemplates: source.transactionTemplates,
    incomeAllocations: source.incomeAllocations,
    achievements: achievements ?? source.achievements,
    achievementStartDate: achievementStartDate,
  );
}

import 'package:flutter/material.dart';

import '../../data/data.dart';
import '../../app/formatters.dart';
import '../../app/pages/app_pages.dart';
import '../../app/theme/design_tokens.dart';

const _milestoneGold = Color(0xFFFFD166);
const _milestoneTargetSurface = Color(0xFFFFF4D6);
const _milestoneCoral = Color(0xFFEF7D68);
const _milestoneLavender = Color(0xFFEDE7FF);
const _milestoneMint = Color(0xFFE1F4EC);
const _earnedAchievementSurfaces = [
  _milestoneTargetSurface,
  _milestoneMint,
  _milestoneLavender,
];

class MilestonesPage extends StatefulWidget {
  const MilestonesPage({
    super.key,
    required this.data,
    required this.onAchievementAcknowledged,
  });

  final AppDataSnapshot data;
  final Future<void> Function(String achievementId) onAchievementAcknowledged;

  @override
  State<MilestonesPage> createState() => _MilestonesPageState();
}

class _MilestonesPageState extends State<MilestonesPage> {
  late NetWorthAchievementEvaluation _evaluation;
  late List<String> _celebrationQueue;
  Set<String> _locallyAcknowledgedIds = {};
  int _celebrationTotal = 0;
  bool _acknowledging = false;
  String? _acknowledgementError;

  @override
  void initState() {
    super.initState();
    _recalculate();
  }

  @override
  void didUpdateWidget(covariant MilestonesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) _recalculate();
  }

  void _recalculate() {
    _locallyAcknowledgedIds = {
      for (final achievement in widget.data.achievements)
        if (achievement.earned) achievement.id,
    };
    final startDate = widget.data.achievementStartDate;
    if (startDate == null) {
      _evaluation = NetWorthAchievementEvaluation(
        effectiveStartDate: null,
        firstEligibleMonth: null,
        completedMonths: const [],
        incompleteCompletedMonths: const [],
        firstEligibleMonthAverage: null,
        monthToDateAverage: null,
        monthToDateAsOf: null,
        monthToDateSnapshotCount: 0,
        monthToDateExpectedSnapshotCount: 0,
        progress: const [],
        earnedFlagsToReset: const [],
        validationErrors: const [],
      );
    } else {
      _evaluation = NetWorthAchievementCalculator.evaluate(
        dailyNetWorth: widget.data.dailyNetWorth,
        trackingStartDate: startDate,
        achievements: widget.data.achievements,
      );
    }
    _celebrationQueue = [
      for (final item in _evaluation.pendingCelebrations) item.achievement.id,
    ];
    _celebrationTotal = _celebrationQueue.length;
  }

  @override
  Widget build(BuildContext context) {
    if (_celebrationQueue.isNotEmpty) return _buildCelebration(context);
    if (_evaluation.validationErrors.isNotEmpty) {
      return _buildValidationError(context);
    }
    return _buildMilestonesPage(context);
  }

  Widget _buildCelebration(BuildContext context) {
    final id = _celebrationQueue.first;
    final progress = _evaluation.progress.firstWhere(
      (item) => item.achievement.id == id,
    );
    final achievement = progress.achievement;
    final month = progress.qualifyingMonth!;
    final average = progress.qualifyingAverage!;
    final currency = widget.data.currenciesById['USD'];
    final formattedAverage = currency == null
        ? average.minorUnits.toString()
        : formatMoney(average, widget.data.currenciesById);
    final formattedTarget = currency == null
        ? achievement.target.minorUnits.toString()
        : formatMoney(achievement.target, widget.data.currenciesById);

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF1C9), Color(0xFFE2F4F0), Color(0xFFF1ECFF)],
        ),
      ),
      child: Stack(
        children: [
          const Positioned(
            top: 38,
            left: 32,
            child: Icon(Icons.auto_awesome, color: _milestoneCoral, size: 34),
          ),
          const Positioned(
            top: 92,
            right: 42,
            child: Icon(Icons.star_rounded, color: _milestoneGold, size: 42),
          ),
          const Positioned(
            bottom: 90,
            left: 54,
            child: Icon(Icons.auto_awesome, color: AppColors.teal, size: 28),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.65, end: 1),
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.elasticOut,
                        builder: (context, scale, child) =>
                            Transform.scale(scale: scale, child: child),
                        child: Container(
                          width: 128,
                          height: 128,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [_milestoneGold, _milestoneCoral],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.warning.withValues(
                                  alpha: 0.26,
                                ),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.celebration,
                            size: 76,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'You did it!',
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(
                              color: AppColors.navy,
                              fontWeight: FontWeight.w800,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'A milestone worth celebrating',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: AppColors.teal,
                              fontWeight: FontWeight.w700,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: _milestoneTargetSurface,
                          borderRadius: BorderRadius.circular(AppRadii.card),
                          border: Border.all(color: _milestoneGold, width: 2),
                        ),
                        child: Text(
                          achievement.name,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: AppColors.navy,
                                fontWeight: FontWeight.w800,
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.navy, AppColors.teal],
                          ),
                          borderRadius: BorderRadius.circular(AppRadii.card),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '${_monthLabel(month)} average',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(color: Colors.white70),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              formattedAverage,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.xs,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(
                                  AppRadii.pill,
                                ),
                              ),
                              child: Text(
                                'Target  $formattedTarget',
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'This is something you worked hard for. Take a moment to celebrate.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (_celebrationQueue.length > 1) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Celebration ${_celebrationTotal - _celebrationQueue.length + 1} of $_celebrationTotal',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.mutedText),
                        ),
                      ],
                      if (_acknowledgementError != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Could not save this acknowledgement: $_acknowledgementError',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      FilledButton.icon(
                        onPressed: _acknowledging ? null : _acknowledgeCurrent,
                        icon: Icon(
                          _celebrationQueue.length > 1
                              ? Icons.arrow_forward
                              : Icons.check,
                        ),
                        label: Text(
                          _acknowledging
                              ? 'Saving…'
                              : _celebrationQueue.length > 1
                              ? 'Celebrate next'
                              : 'Continue',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _acknowledgeCurrent() async {
    final id = _celebrationQueue.first;
    setState(() {
      _acknowledging = true;
      _acknowledgementError = null;
    });
    try {
      await widget.onAchievementAcknowledged(id);
      if (!mounted) return;
      setState(() {
        _locallyAcknowledgedIds.add(id);
        final updatedData = widget.data.withAchievements([
          for (final achievement in widget.data.achievements)
            achievement.copyWith(
              earned: _locallyAcknowledgedIds.contains(achievement.id),
            ),
        ]);
        _evaluation = NetWorthAchievementCalculator.evaluate(
          dailyNetWorth: updatedData.dailyNetWorth,
          trackingStartDate: updatedData.achievementStartDate!,
          achievements: updatedData.achievements,
        );
        _celebrationQueue = _celebrationQueue.skip(1).toList();
        _acknowledging = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _acknowledging = false;
        _acknowledgementError = error.toString();
      });
    }
  }

  Widget _buildMilestonesPage(BuildContext context) {
    if (widget.data.achievements.isEmpty) {
      return AppPageFrame(
        title: 'Milestones',
        subtitle: 'A personal record of the progress you have worked for.',
        child: const EmptyState(
          icon: Icons.celebration_outlined,
          message:
              'Add your named milestones to the Achievements Sheet to begin.',
        ),
      );
    }
    final currency = widget.data.currenciesById['USD'];
    final lastMonth = _lastCompletedMonthAverage();
    final currentAverage = lastMonth?.average;
    final achievements = _evaluation.progress;
    final earned =
        achievements.where((item) => item.achievement.earned).toList()
          ..sort((a, b) {
            final aMonth = a.qualifyingMonth;
            final bMonth = b.qualifyingMonth;
            if (aMonth == null) return bMonth == null ? 0 : 1;
            if (bMonth == null) return -1;
            final monthOrder = aMonth.compareTo(bMonth);
            return monthOrder != 0
                ? monthOrder
                : a.achievement.target.minorUnits.compareTo(
                    b.achievement.target.minorUnits,
                  );
          });
    final next = _nextMilestone(currentAverage, achievements);
    final baseline = _evaluation.firstEligibleMonthAverage;

    return AppPageFrame(
      title: 'Milestones',
      subtitle: 'A personal record of the progress you have worked for.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildProgressPanel(
            context,
            lastMonth: lastMonth,
            next: next,
            baseline: baseline,
            currency: currency,
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              const Icon(Icons.workspace_premium, color: AppColors.warning),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Earned milestones',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (earned.isEmpty)
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: _milestoneLavender,
                borderRadius: BorderRadius.circular(AppRadii.card),
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(
                children: [
                  Icon(Icons.favorite, color: AppColors.teal, size: 30),
                  SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'Your first milestone is waiting. Keep going at your pace.',
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              children: [
                for (var index = 0; index < earned.length; index++) ...[
                  if (index > 0) const SizedBox(height: AppSpacing.sm),
                  _EarnedAchievementRow(
                    progress: earned[index],
                    currencies: widget.data.currenciesById,
                    index: index,
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  CompletedNetWorthMonth? _lastCompletedMonthAverage() {
    final now = DateTime.now();
    final lastMonth = DateTime.utc(now.year, now.month - 1);
    for (final month in _evaluation.completedMonths) {
      if (month.month == lastMonth) return month;
    }
    return null;
  }

  Widget _buildProgressPanel(
    BuildContext context, {
    required CompletedNetWorthMonth? lastMonth,
    required NetWorthAchievementProgress? next,
    required Money? baseline,
    required CurrencyDefinition? currency,
  }) {
    final lastMonthStart = DateTime.utc(
      DateTime.now().year,
      DateTime.now().month - 1,
    );
    final lastMonthLabel = _monthLabel(lastMonthStart);
    final lastMonthEnd = DateTime.utc(
      lastMonthStart.year,
      lastMonthStart.month + 1,
      0,
    );
    final lastMonthIsIncomplete = _evaluation.incompleteCompletedMonths
        .contains(lastMonthStart);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.navy, AppColors.teal],
        ),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: _milestoneGold),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Last completed month average',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          Text(
            lastMonthLabel,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.82),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            lastMonth == null || currency == null
                ? lastMonthIsIncomplete
                      ? 'Waiting for missing daily snapshots to be repaired.'
                      : 'A complete month of daily snapshots is needed to show progress.'
                : formatMoney(lastMonth.average, widget.data.currenciesById),
            style: Theme.of(context).textTheme.headlineLarge
                ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
          ),
          if (lastMonth != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'Complete daily average through ${formatDate(lastMonthEnd)}',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: Colors.white.withValues(alpha: 0.82)),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          if (baseline == null)
            Text(
              'Your first full tracked month will establish the starting point for progress.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: Colors.white),
            )
          else if (next == null)
            Text(
              lastMonth == null
                  ? 'Progress will appear when last month’s complete average is available.'
                  : 'You have reached every milestone currently in the Sheet. Add another when you are ready.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: Colors.white),
            )
          else if (lastMonth == null)
            _buildHighlightedMilestone(
              context,
              name: next.achievement.name,
              target: next.achievement.target,
              progress: null,
              lowerBound: null,
            )
          else
            _buildProgress(context, lastMonth.average, baseline, next),
        ],
      ),
    );
  }

  Widget _buildProgress(
    BuildContext context,
    Money current,
    Money baseline,
    NetWorthAchievementProgress next,
  ) {
    final lowerBound = _activeLowerBound(current, baseline);
    final upperBound = next.achievement.target.minorUnits;
    final span = upperBound - lowerBound;
    final fraction = span <= 0
        ? 1.0
        : ((current.minorUnits - lowerBound) / span).clamp(0.0, 1.0);
    return _buildHighlightedMilestone(
      context,
      name: next.achievement.name,
      target: next.achievement.target,
      progress: fraction,
      lowerBound: lowerBound,
    );
  }

  Widget _buildHighlightedMilestone(
    BuildContext context, {
    required String name,
    required Money target,
    required double? progress,
    required int? lowerBound,
  }) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: _milestoneTargetSurface,
      borderRadius: BorderRadius.circular(AppRadii.control),
      border: Border.all(color: _milestoneGold, width: 2),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.flag_rounded, color: AppColors.warning),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'PROGRESS TOWARD',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.navy,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          name,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Target: ${formatMoney(target, widget.data.currenciesById)}',
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.md),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: LinearProgressIndicator(
            value: progress ?? 0,
            minHeight: 18,
            backgroundColor: AppColors.navy.withValues(alpha: 0.16),
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.warning),
          ),
        ),
        if (lowerBound != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatMoney(
                  Money(minorUnits: lowerBound, currencyId: 'USD'),
                  widget.data.currenciesById,
                ),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AppColors.navy),
              ),
              Text(
                formatMoney(target, widget.data.currenciesById),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );

  int _activeLowerBound(Money current, Money baseline) {
    final lowerTargets = _evaluation.progress
        .map((item) => item.achievement.target.minorUnits)
        .where((target) => target <= current.minorUnits)
        .toList();
    if (lowerTargets.isNotEmpty) return lowerTargets.last;
    return baseline.minorUnits;
  }

  NetWorthAchievementProgress? _nextMilestone(
    Money? current,
    List<NetWorthAchievementProgress> progress,
  ) {
    if (current == null) {
      for (final item in progress) {
        if (!item.qualifies) return item;
      }
      return null;
    }
    for (final item in progress) {
      if (item.achievement.target.minorUnits > current.minorUnits) return item;
    }
    return null;
  }

  Widget _buildValidationError(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Text(
        _evaluation.validationErrors.join('\n'),
        style: TextStyle(color: Theme.of(context).colorScheme.error),
        textAlign: TextAlign.center,
      ),
    ),
  );
}

class _EarnedAchievementRow extends StatelessWidget {
  const _EarnedAchievementRow({
    required this.progress,
    required this.currencies,
    required this.index,
  });

  final NetWorthAchievementProgress progress;
  final Map<String, CurrencyDefinition> currencies;
  final int index;

  @override
  Widget build(BuildContext context) {
    final month = progress.qualifyingMonth;
    final average = progress.qualifyingAverage;
    final surface =
        _earnedAchievementSurfaces[index % _earnedAchievementSurfaces.length];
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: surface.withValues(alpha: 0.9)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.white.withValues(alpha: 0.9),
          child: const Icon(Icons.workspace_premium, color: AppColors.teal),
        ),
        title: Text(
          progress.achievement.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          month == null || average == null
              ? 'Earned earlier; full history is currently incomplete.'
              : '${_monthLabel(month)} average: ${formatMoney(average, currencies)}',
        ),
        trailing: const Icon(Icons.check_circle, color: AppColors.success),
      ),
    );
  }
}

String _monthLabel(DateTime date) {
  final month = const [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ][date.month - 1];
  return '$month ${date.year}';
}

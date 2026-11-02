import 'package:flutter/material.dart';

import '../../data/data.dart';
import '../formatters.dart';
import '../theme/design_tokens.dart';
import 'account_balance_row.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key, required this.data});

  final AppDataSnapshot data;

  @override
  Widget build(BuildContext context) {
    final balances = data.ledgerBalances;

    return AppPageFrame(
      title: 'Overview',
      subtitle: 'A clear view of your financial position.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildNetWorthSummary(context, data),
          SizedBox(
            height: usesCompactVerticalSpacing(context)
                ? AppSpacing.md
                : AppPageSpacing.compactSection,
          ),
          Text('Cash balances', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Through the latest transaction.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: AppColors.mutedText),
          ),
          SizedBox(
            height: usesCompactVerticalSpacing(context)
                ? AppSpacing.xs
                : AppSpacing.sm,
          ),
          Card(
            clipBehavior: Clip.hardEdge,
            child: Column(
              children: [
                for (final account in data.visibleAccounts.where(
                  (account) => account.accountTypeKind == AccountType.cash,
                )) ...[
                  if (account !=
                      data.visibleAccounts.firstWhere(
                        (item) => item.accountTypeKind == AccountType.cash,
                      ))
                    const Divider(height: 1),
                  AccountBalanceRow(
                    account: account,
                    amount: balances[account.id]!,
                    currencies: data.currenciesById,
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            height: usesCompactVerticalSpacing(context)
                ? AppSpacing.md
                : AppPageSpacing.compactSection,
          ),
          Builder(
            builder: (context) {
              final assetLiabilityAccounts = data.visibleAccounts
                  .where(
                    (account) => account.accountTypeKind != AccountType.cash,
                  )
                  .toList();
              DateTime? latestDate;
              for (final valuation in data.dailyManualValuations) {
                if (latestDate == null || valuation.date.isAfter(latestDate)) {
                  latestDate = valuation.date;
                }
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Assets & liabilities',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    latestDate == null
                        ? 'No manual valuation available'
                        : 'Latest manual valuation: ${formatDate(latestDate)}',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: AppColors.mutedText),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Card(
                    clipBehavior: Clip.hardEdge,
                    child: assetLiabilityAccounts.isEmpty
                        ? const EmptyState(
                            message: 'No Asset or Liability accounts yet.',
                          )
                        : Column(
                            children: [
                              for (
                                var index = 0;
                                index < assetLiabilityAccounts.length;
                                index++
                              ) ...[
                                if (index > 0) const Divider(height: 1),
                                _ManualValuationRow(
                                  account: assetLiabilityAccounts[index],
                                  data: data,
                                  balances: balances,
                                ),
                              ],
                            ],
                          ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static String _netWorthDetail({
    required DailyNetWorth latestNetWorth,
    required _NetWorthChange? change,
    required Map<String, CurrencyDefinition> currencies,
  }) {
    final asOf = 'As of ${formatDate(latestNetWorth.date)}';
    if (change == null) return asOf;
    final sign = change.amountMinorUnits >= 0 ? '+' : '';
    final amount = formatMoney(
      Money(
        minorUnits: change.amountMinorUnits,
        currencyId: latestNetWorth.amount.currencyId,
      ),
      currencies,
    );
    final percentage = change.baselineMinorUnits == 0
        ? 'n/a'
        : '${(change.amountMinorUnits / change.baselineMinorUnits.abs() * 100).toStringAsFixed(1)}%';
    return '$sign$amount · $sign$percentage over 30 days · $asOf';
  }

  static Widget _monthlyAverageCard({
    required BuildContext context,
    required _MonthlyNetWorthComparison? comparison,
    required Map<String, CurrencyDefinition> currencies,
  }) {
    if (comparison == null) {
      return const MetricCard(
        label: 'Monthly Average',
        value: 'Unavailable',
        detail: 'Not enough monthly data',
      );
    }
    return MetricCard(
      label: '${comparison.currentLabel} Average',
      value: formatMoney(comparison.currentAverage, currencies),
      detail: '${comparison.currentSnapshotCount} daily snapshots',
      accent:
          amountColor(context, comparison.currentAverage.minorUnits) ??
          AppColors.mutedText,
    );
  }

  static Widget _monthlyChangeCard({
    required _MonthlyNetWorthComparison? comparison,
    required Map<String, CurrencyDefinition> currencies,
  }) {
    if (comparison == null || comparison.percentageChange == null) {
      return const MetricCard(
        label: 'Monthly Change',
        value: 'Unavailable',
        detail: 'Not enough monthly data',
      );
    }
    final percentage = comparison.percentageChange!;
    final sign = percentage >= 0 ? '+' : '';
    return MetricCard(
      label: 'vs ${comparison.previousLabel} Average',
      value: '$sign${percentage.toStringAsFixed(1)}%',
      detail:
          '${formatMoney(comparison.currentAverage, currencies)} vs ${formatMoney(comparison.previousAverage, currencies)}',
      accent: percentage > 0
          ? AppColors.success
          : percentage < 0
          ? AppColors.danger
          : AppColors.mutedText,
    );
  }

  static _MonthlyNetWorthComparison? _monthlyNetWorthComparison(
    Iterable<DailyNetWorth> values,
  ) {
    final byMonth = <DateTime, List<DailyNetWorth>>{};
    for (final value in values) {
      final month = DateTime.utc(value.date.year, value.date.month);
      byMonth.putIfAbsent(month, () => []).add(value);
    }
    final months = byMonth.keys.toList()..sort();
    if (months.length < 2) return null;
    final currentMonth = months.last;
    final previousMonth = months[months.length - 2];
    int average(DateTime month) {
      final entries = byMonth[month]!;
      final total = entries.fold<int>(
        0,
        (sum, value) => sum + value.amount.minorUnits,
      );
      return (total / entries.length).round();
    }

    final currentAverage = average(currentMonth);
    final previousAverage = average(previousMonth);
    final percentage = previousAverage == 0
        ? null
        : (currentAverage - previousAverage) / previousAverage.abs() * 100;
    return _MonthlyNetWorthComparison(
      currentLabel: _monthLabel(currentMonth),
      previousLabel: _monthLabel(previousMonth),
      currentAverage: Money(
        minorUnits: currentAverage,
        currencyId: byMonth[currentMonth]!.first.amount.currencyId,
      ),
      previousAverage: Money(
        minorUnits: previousAverage,
        currencyId: byMonth[previousMonth]!.first.amount.currencyId,
      ),
      currentSnapshotCount: byMonth[currentMonth]!.length,
      percentageChange: percentage,
    );
  }

  static String _monthLabel(DateTime month) => const [
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
  ][month.month - 1];

  static _NetWorthChange? _netWorthChangeOver30Days(
    Iterable<DailyNetWorth> values,
    DailyNetWorth? latest,
  ) {
    if (latest == null) return null;
    final target = DateTime.utc(
      latest.date.year,
      latest.date.month,
      latest.date.day,
    ).subtract(const Duration(days: 30));
    DailyNetWorth? baseline;
    for (final value in values) {
      final date = DateTime.utc(
        value.date.year,
        value.date.month,
        value.date.day,
      );
      if (!date.isAfter(target) &&
          (baseline == null || date.isAfter(baseline.date))) {
        baseline = value;
      }
    }
    if (baseline == null) return null;
    return _NetWorthChange(
      amountMinorUnits: latest.amount.minorUnits - baseline.amount.minorUnits,
      baselineMinorUnits: baseline.amount.minorUnits,
    );
  }

  static DailyNetWorth? _latestByDate(
    Iterable<DailyNetWorth> values,
    DateTime Function(DailyNetWorth) dateOf,
  ) {
    DailyNetWorth? latest;
    for (final value in values) {
      if (latest == null || dateOf(value).isAfter(dateOf(latest))) {
        latest = value;
      }
    }
    return latest;
  }
}

class NetWorthSummarySection extends StatelessWidget {
  const NetWorthSummarySection({super.key, required this.data});

  final AppDataSnapshot data;

  @override
  Widget build(BuildContext context) => _buildNetWorthSummary(context, data);
}

Widget _buildNetWorthSummary(BuildContext context, AppDataSnapshot data) {
  final dailyValues = data.materializedDailyNetWorth();
  final latestNetWorth = OverviewPage._latestByDate(
    dailyValues,
    (value) => value.date,
  );
  final netWorthChange = OverviewPage._netWorthChangeOver30Days(
    dailyValues,
    latestNetWorth,
  );
  final monthlyComparison = OverviewPage._monthlyNetWorthComparison(
    dailyValues,
  );

  return LayoutBuilder(
    builder: (context, constraints) {
      final compactSpacing = usesCompactVerticalSpacing(
        context,
        availableWidth: constraints.maxWidth,
      );
      final netWorthCard = MetricCard(
        label: 'Net worth',
        value: latestNetWorth == null
            ? 'Unavailable'
            : formatMoney(latestNetWorth.amount, data.currenciesById),
        detail: latestNetWorth == null
            ? 'No daily snapshot available'
            : OverviewPage._netWorthDetail(
                latestNetWorth: latestNetWorth,
                change: netWorthChange,
                currencies: data.currenciesById,
              ),
        accent: latestNetWorth == null
            ? AppColors.mutedText
            : amountColor(context, latestNetWorth.amount.minorUnits) ??
                  AppColors.mutedText,
      );
      final secondaryCards = [
        OverviewPage._monthlyAverageCard(
          context: context,
          comparison: monthlyComparison,
          currencies: data.currenciesById,
        ),
        OverviewPage._monthlyChangeCard(
          comparison: monthlyComparison,
          currencies: data.currenciesById,
        ),
      ];

      if (constraints.maxWidth >= AppBreakpoints.medium) {
        return Row(
          children: [
            Expanded(child: netWorthCard),
            const SizedBox(width: AppSpacing.md),
            for (var index = 0; index < secondaryCards.length; index++) ...[
              Expanded(child: secondaryCards[index]),
              if (index < secondaryCards.length - 1)
                const SizedBox(width: AppSpacing.md),
            ],
          ],
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          netWorthCard,
          SizedBox(height: compactSpacing ? AppSpacing.xs : AppSpacing.sm),
          LayoutBuilder(
            builder: (context, secondaryConstraints) {
              if (secondaryConstraints.maxWidth >= 520 &&
                  MediaQuery.textScalerOf(context).scale(14) <= 16.8) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: secondaryCards[0]),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: secondaryCards[1]),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  secondaryCards[0],
                  SizedBox(
                    height: compactSpacing ? AppSpacing.xs : AppSpacing.sm,
                  ),
                  secondaryCards[1],
                ],
              );
            },
          ),
        ],
      );
    },
  );
}

class _MonthlyNetWorthComparison {
  const _MonthlyNetWorthComparison({
    required this.currentLabel,
    required this.previousLabel,
    required this.currentAverage,
    required this.previousAverage,
    required this.currentSnapshotCount,
    required this.percentageChange,
  });

  final String currentLabel;
  final String previousLabel;
  final Money currentAverage;
  final Money previousAverage;
  final int currentSnapshotCount;
  final double? percentageChange;
}

class _NetWorthChange {
  const _NetWorthChange({
    required this.amountMinorUnits,
    required this.baselineMinorUnits,
  });

  final int amountMinorUnits;
  final int baselineMinorUnits;
}

class CashAccountsSection extends StatelessWidget {
  const CashAccountsSection({super.key, required this.data});

  final AppDataSnapshot data;

  @override
  Widget build(BuildContext context) {
    final balances = data.ledgerBalances;
    final cashAccounts = data.visibleAccounts
        .where((account) => account.accountTypeKind == AccountType.cash)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cash Accounts', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Cash account ledger balances through the latest transaction.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: AppColors.mutedText),
        ),
        SizedBox(
          height: usesCompactVerticalSpacing(context)
              ? AppSpacing.xs
              : AppSpacing.sm,
        ),
        if (cashAccounts.isEmpty)
          const EmptyState(message: 'No Cash accounts yet.')
        else
          Card(
            clipBehavior: Clip.hardEdge,
            child: Column(
              children: [
                for (var index = 0; index < cashAccounts.length; index++) ...[
                  if (index > 0) const Divider(height: 1),
                  AccountBalanceRow(
                    account: cashAccounts[index],
                    amount: balances[cashAccounts[index].id]!,
                    currencies: data.currenciesById,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({
    super.key,
    required this.title,
    required this.icon,
    required this.message,
  });

  final String title;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return AppPageFrame(
      title: title,
      child: EmptyState(icon: icon, message: message),
    );
  }
}

class AppLoadingPage extends StatelessWidget {
  const AppLoadingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class DataValidationPage extends StatelessWidget {
  const DataValidationPage({
    super.key,
    required this.failure,
    required this.onReload,
  });

  final DataValidationFailure failure;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<DataValidationIssue>>{};
    for (final issue in failure.issues) {
      final key = '${issue.table}|${issue.field}|${issue.message}';
      grouped.putIfAbsent(key, () => []).add(issue);
    }
    final byTable = <String, List<List<DataValidationIssue>>>{};
    for (final issues in grouped.values) {
      byTable.putIfAbsent(issues.first.table, () => []).add(issues);
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 48,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Data validation failed',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    'Accountable is unavailable until the source data is corrected.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  for (final tableEntry in byTable.entries) ...[
                    Text(
                      tableEntry.key,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    for (final issues in tableEntry.value)
                      Builder(
                        builder: (context) {
                          final first = issues.first;
                          final rows = issues
                              .map((issue) => issue.row)
                              .whereType<int>()
                              .toList();
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.error_outline,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            title: Text(first.message),
                            subtitle: Text(
                              _formatValidationLocation(
                                first.table,
                                first.field,
                                rows,
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  FilledButton.icon(
                    onPressed: onReload,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reload data'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ExpansionTile(
                    title: const Text('Technical details'),
                    children: [
                      for (final issue in failure.issues)
                        if (issue.technicalDetails case final details?)
                          ListTile(dense: true, title: Text(details)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _formatValidationLocation(String table, String? field, List<int> rows) {
  if (rows.isEmpty) {
    final parts = <String>[table];
    if (field case final fieldValue?) parts.add(fieldValue);
    return parts.join(' · ');
  }
  final shown = rows.take(3).join(', ');
  final remaining = rows.length - rows.take(3).length;
  final suffix = remaining > 0 ? ' and $remaining other rows' : '';
  final fieldSuffix = field == null ? '' : ' · $field';
  return '$table · rows $shown$suffix$fieldSuffix';
}

class AppErrorPage extends StatelessWidget {
  const AppErrorPage({super.key, required this.error, required this.onReload});

  final Object error;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Could not load your data',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                error.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: onReload,
                icon: const Icon(Icons.refresh),
                label: const Text('Reload'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppPageFrame extends StatelessWidget {
  const AppPageFrame({
    super.key,
    required this.title,
    this.subtitle,
    this.scrollStorageKey,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final PageStorageKey<String>? scrollStorageKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < AppBreakpoints.compact;
    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        key: scrollStorageKey ?? PageStorageKey<String>('app-page-$title'),
        padding: EdgeInsets.all(
          compact ? AppPageSpacing.compactGutter : AppPageSpacing.desktopGutter,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppBreakpoints.maxContentWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(color: AppColors.mutedText),
                ),
              ],
              SizedBox(
                height: compact
                    ? usesCompactVerticalSpacing(context)
                          ? AppSpacing.md
                          : AppPageSpacing.compactSection
                    : AppPageSpacing.desktopSection,
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.detail,
    this.accent,
  });

  final String label;
  final String value;
  final String detail;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final compactSpacing = usesCompactVerticalSpacing(context);
    return Card(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: compactSpacing
              ? AppSpacing.sm + AppSpacing.xs
              : AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: AppColors.mutedText),
            ),
            SizedBox(height: compactSpacing ? AppSpacing.xs : AppSpacing.sm),
            _CompleteMetricValue(
              value: value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: accent ?? AppColors.navy,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(detail, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _CompleteMetricValue extends StatelessWidget {
  const _CompleteMetricValue({required this.value, required this.style});

  final String value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final text = Text(value, maxLines: 1, softWrap: false, style: style);
      if (painter.width <= constraints.maxWidth ||
          !constraints.maxWidth.isFinite) {
        return text;
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: text,
      );
    },
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, this.icon, required this.message});

  final IconData? icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: Column(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 40, color: AppColors.mutedText),
              const SizedBox(height: AppSpacing.sm),
            ],
            Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: AppColors.mutedText),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualValuationRow extends StatelessWidget {
  const _ManualValuationRow({
    required this.account,
    required this.data,
    required this.balances,
  });

  final Account account;
  final AppDataSnapshot data;
  final Map<String, Money> balances;

  @override
  Widget build(BuildContext context) {
    final accountValuations = data.manualValuationsByAccountId[account.id];
    final latest = accountValuations == null || accountValuations.isEmpty
        ? null
        : accountValuations.last;
    final currency = data.currenciesById[account.currencyId];
    final value = account.isValuationAccount
        ? latest?.value
        : balances[account.id];
    return AccountBalanceRow(
      account: account,
      amount: currency == null ? null : value,
      currencies: data.currenciesById,
    );
  }
}

class TransactionSummaryRow extends StatelessWidget {
  const TransactionSummaryRow({
    super.key,
    required this.transaction,
    required this.currencies,
  });

  final Transaction transaction;
  final Map<String, CurrencyDefinition> currencies;

  @override
  Widget build(BuildContext context) {
    final amount = transaction.sourceAmount ?? transaction.destinationAmount;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(_iconFor(transaction.type)),
      ),
      title: Text(
        transaction.description.isEmpty
            ? transaction.type.wireValue
            : transaction.description,
      ),
      subtitle: Text(formatDate(transaction.date)),
      trailing: Text(amount == null ? '—' : formatMoney(amount, currencies)),
    );
  }

  static IconData _iconFor(TransactionType type) {
    return switch (type) {
      TransactionType.expense => Icons.arrow_upward,
      TransactionType.income => Icons.arrow_downward,
      TransactionType.reimbursement => Icons.replay,
      TransactionType.transfer => Icons.swap_horiz,
    };
  }
}

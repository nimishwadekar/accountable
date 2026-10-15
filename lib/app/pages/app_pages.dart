import 'package:flutter/material.dart';

import '../../data/data.dart';
import '../formatters.dart';
import '../theme/design_tokens.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key, required this.data});

  final AppDataSnapshot data;

  @override
  Widget build(BuildContext context) {
    final latestNetWorth = _latestByDate(
      data.dailyNetWorth,
      (value) => value.date,
    );

    return AppPageFrame(
      title: 'Overview',
      subtitle: 'A clear view of your financial position.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MetricCard(
            label: 'Net worth',
            value: latestNetWorth == null
                ? 'Unavailable'
                : formatMoney(latestNetWorth.amount, data.currenciesById),
            detail: latestNetWorth == null
                ? 'No daily snapshot available'
                : 'As of ${formatDate(latestNetWorth.date)}',
            accent: AppColors.teal,
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Current balances',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Current ledger balance through the latest transaction.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: AppColors.mutedText),
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Column(
              children: [
                for (var index = 0; index < data.accounts.length; index++) ...[
                  if (index > 0) const Divider(height: 1),
                  _AccountRow(
                    account: data.accounts[index],
                    currencies: data.currenciesById,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
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

class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key, required this.data});

  final AppDataSnapshot data;

  @override
  Widget build(BuildContext context) {
    return AppPageFrame(
      title: 'Accounts',
      subtitle: 'Balances across your connected accounts.',
      child: Card(
        child: Column(
          children: [
            for (var index = 0; index < data.accounts.length; index++) ...[
              if (index > 0) const Divider(height: 1),
              _AccountRow(
                account: data.accounts[index],
                currencies: data.currenciesById,
              ),
            ],
          ],
        ),
      ),
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
                  for (final entry in grouped.entries) ...[
                    Text(
                      entry.value.first.table,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Builder(
                      builder: (context) {
                        final issues = entry.value;
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
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
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
              const SizedBox(height: AppSpacing.xl),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: AppColors.mutedText),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: accent ?? AppColors.navy,
                fontWeight: FontWeight.w800,
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

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.account, required this.currencies});

  final Account account;
  final Map<String, CurrencyDefinition> currencies;

  @override
  Widget build(BuildContext context) {
    final currency = currencies[account.currencyId];
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        foregroundColor: AppColors.navy,
        child: const Icon(Icons.account_balance_wallet_outlined),
      ),
      title: Text(account.name),
      subtitle: Text(account.accountType),
      trailing: Text(
        currency == null
            ? '—'
            : formatMoney(account.currentBalance, currencies),
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
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

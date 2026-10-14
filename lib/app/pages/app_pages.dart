import 'package:flutter/material.dart';

import '../../data/data.dart';
import '../formatters.dart';
import '../theme/design_tokens.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key, required this.data});

  final AppDataSnapshot data;

  @override
  Widget build(BuildContext context) {
    final latestNetWorth = _latestByDate(data.dailyNetWorth, (value) => value.date);
    final latestBalances = [
      ...data.accounts.map(
        (account) => data.dailyAccountBalances
            .where((balance) => balance.accountId == account.id)
            .fold<DailyAccountBalance?>(
              null,
              (latest, balance) =>
                  latest == null || balance.date.isAfter(latest.date)
                      ? balance
                      : latest,
            ),
      ),
    ];

    return AppPageFrame(
      title: 'Overview',
      subtitle: 'A clear view of your financial position.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = constraints.maxWidth < 700
                  ? constraints.maxWidth
                  : (constraints.maxWidth - AppSpacing.md * 2) / 3;
              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  SizedBox(
                    width: cardWidth,
                    child: MetricCard(
                      label: 'Net worth',
                      value: latestNetWorth == null
                          ? '—'
                          :                           formatMoney(
                              latestNetWorth.amount,
                              data.currenciesById,
                            ),
                      detail: latestNetWorth == null
                          ? 'No daily snapshot'
                          : 'As of ${formatDate(latestNetWorth.date)}',
                      accent: AppColors.teal,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: MetricCard(
                      label: 'Accounts',
                      value: data.accounts.length.toString(),
                      detail: 'Across ${data.currencies.length} currencies',
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: MetricCard(
                      label: 'Transactions',
                      value: data.transactions.length.toString(),
                      detail: 'Loaded from local fixtures',
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('Accounts', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Column(
              children: [
                for (var index = 0; index < data.accounts.length; index++) ...[
                  if (index > 0) const Divider(height: 1),
                  _AccountRow(
                    account: data.accounts[index],
                    balance: latestBalances[index],
                    currencies: data.currenciesById,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Recent transactions',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: data.transactions.isEmpty
                ? const EmptyState(message: 'No transactions yet.')
                : Column(
                    children: [
                      for (final transaction
                          in _recentTransactions(data.transactions))
                        TransactionSummaryRow(
                          transaction: transaction,
                          currencies: data.currenciesById,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  static T? _latestByDate<T>(
    Iterable<T> values,
    DateTime Function(T) dateOf,
  ) {
    T? latest;
    for (final value in values) {
      if (latest == null || dateOf(value).isAfter(dateOf(latest as T))) {
        latest = value;
      }
    }
    return latest;
  }

  static List<Transaction> _recentTransactions(
    List<Transaction> transactions,
  ) {
    final sorted = [...transactions]
      ..sort((a, b) => b.date.compareTo(a.date));
    return sorted.take(5).toList();
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
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.mutedText,
                      ),
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
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.mutedText,
                  ),
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
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.mutedText,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.currencies,
    this.balance,
  });

  final Account account;
  final DailyAccountBalance? balance;
  final Map<String, CurrencyDefinition> currencies;

  @override
  Widget build(BuildContext context) {
    final currency = currencies[account.currencyId];
    final money = balance?.balance ?? account.currentBalance;
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
        currency == null ? '—' : formatMoney(money, currencies),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
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
      trailing: Text(
        amount == null ? '—' : formatMoney(amount, currencies),
      ),
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


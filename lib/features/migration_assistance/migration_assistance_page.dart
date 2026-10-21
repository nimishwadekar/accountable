import 'package:flutter/material.dart';

import '../../app/formatters.dart';
import '../../app/pages/app_pages.dart';
import '../../app/pages/transaction_list_widgets.dart';
import '../../app/theme/design_tokens.dart';
import '../../data/data.dart';

class MigrationAccountChange {
  const MigrationAccountChange({
    required this.account,
    required this.openingBalance,
    required this.netChange,
    required this.preMigrationBalance,
  });

  final Account account;
  final Money openingBalance;
  final Money netChange;
  final Money preMigrationBalance;
}

List<MigrationAccountChange> calculateMigrationChanges(AppDataSnapshot data) {
  final changes = {
    for (final account in data.accounts)
      account.id: Money.zero(data.currenciesById[account.currencyId]!),
  };
  for (final transaction in data.transactionsToMigrate) {
    if (transaction.sourceAccountId != null &&
        transaction.sourceAmount != null) {
      final accountId = transaction.sourceAccountId!;
      changes[accountId] = changes[accountId]! - transaction.sourceAmount!;
    }
    if (transaction.destinationAccountId != null &&
        transaction.destinationAmount != null) {
      final accountId = transaction.destinationAccountId!;
      changes[accountId] = changes[accountId]! + transaction.destinationAmount!;
    }
  }
  return [
    for (final account in data.accounts)
      MigrationAccountChange(
        account: account,
        openingBalance: account.openingBalance,
        netChange: changes[account.id]!,
        preMigrationBalance: account.openingBalance - changes[account.id]!,
      ),
  ];
}

class MigrationAssistancePage extends StatelessWidget {
  const MigrationAssistancePage({super.key, required this.data});

  final AppDataSnapshot data;

  @override
  Widget build(BuildContext context) {
    final changes = calculateMigrationChanges(data);
    return AppPageFrame(
      title: 'Migration Assistance',
      subtitle:
          '${data.transactionsToMigrate.length} older transactions · read-only',
      child: Card(
        clipBehavior: Clip.hardEdge,
        child: Column(
          children: [
            for (var index = 0; index < changes.length; index++) ...[
              if (index > 0) const Divider(height: 1),
              _MigrationAccountRow(
                change: changes[index],
                data: data,
                onTap: () =>
                    _showAccountTransactions(context, changes[index].account),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showAccountTransactions(
    BuildContext context,
    Account account,
  ) async {
    final transactions =
        data.transactionsToMigrate
            .where(
              (transaction) =>
                  transaction.sourceAccountId == account.id ||
                  transaction.destinationAccountId == account.id,
            )
            .toList()
          ..sort((a, b) {
            final dateComparison = b.date.compareTo(a.date);
            return dateComparison == 0
                ? b.createdAt.compareTo(a.createdAt)
                : dateComparison;
          });

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _MigrationTransactionsSheet(
        account: account,
        data: data,
        transactions: transactions,
      ),
    );
  }
}

class _MigrationAccountRow extends StatelessWidget {
  const _MigrationAccountRow({
    required this.change,
    required this.data,
    required this.onTap,
  });

  final MigrationAccountChange change;
  final AppDataSnapshot data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final currency = data.currenciesById[change.account.currencyId];
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              change.account.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '${change.account.id} · ${currency?.id ?? change.account.currencyId}',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.mutedText),
            ),
            const SizedBox(height: AppSpacing.sm),
            _ValueLine(
              label: 'Active opening balance',
              value: formatMoney(change.openingBalance, data.currenciesById),
            ),
            _ValueLine(
              label: 'Migration net change',
              value: formatMoney(change.netChange, data.currenciesById),
            ),
            _ValueLine(
              label: 'Before migration',
              value: formatMoney(
                change.preMigrationBalance,
                data.currenciesById,
              ),
              emphasized: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _MigrationTransactionsSheet extends StatelessWidget {
  const _MigrationTransactionsSheet({
    required this.account,
    required this.data,
    required this.transactions,
  });

  final Account account;
  final AppDataSnapshot data;
  final List<Transaction> transactions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                account.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                '${transactions.length} migration transactions · newest first',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppColors.mutedText),
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: transactions.isEmpty
                    ? const Center(child: Text('No migration transactions.'))
                    : ListView.separated(
                        itemCount: transactions.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final transaction = transactions[index];
                          return TransactionListRow(
                            transaction: transaction,
                            data: data,
                            onTap: () => showModalBottomSheet<void>(
                              context: context,
                              showDragHandle: true,
                              builder: (_) => TransactionDetailsSheet(
                                transaction: transaction,
                                data: data,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ValueLine extends StatelessWidget {
  const _ValueLine({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = emphasized
        ? Theme.of(context).textTheme.bodyLarge
              ?.copyWith(fontWeight: FontWeight.w700)
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

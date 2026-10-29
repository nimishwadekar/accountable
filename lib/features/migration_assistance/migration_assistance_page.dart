import 'package:flutter/material.dart';

import '../../app/error_dialog.dart';
import '../../app/formatters.dart';
import '../../app/pages/app_pages.dart';
import '../../app/pages/transaction_list_widgets.dart';
import '../../app/theme/design_tokens.dart';
import '../../data/data.dart';

class MigrationAccountChange {
  const MigrationAccountChange({
    required this.account,
    required this.transactionCount,
    required this.openingBalance,
    required this.netChange,
    required this.preMigrationBalance,
  });

  final Account account;
  final int transactionCount;
  final Money openingBalance;
  final Money netChange;
  final Money preMigrationBalance;
}

List<MigrationAccountChange> calculateMigrationChanges(AppDataSnapshot data) {
  final changes = {
    for (final account in data.accounts)
      account.id: Money.zero(data.currenciesById[account.currencyId]!),
  };
  final transactionCounts = {
    for (final account in data.accounts) account.id: 0,
  };
  for (final transaction in data.transactionsToMigrate) {
    final accountIds = {
      transaction.sourceAccountId,
      transaction.destinationAccountId,
    }.whereType<String>();
    for (final accountId in accountIds) {
      transactionCounts[accountId] = transactionCounts[accountId]! + 1;
    }
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
        transactionCount: transactionCounts[account.id]!,
        openingBalance: account.openingBalance,
        netChange: changes[account.id]!,
        preMigrationBalance: account.openingBalance - changes[account.id]!,
      ),
  ];
}

class MigrationAssistancePage extends StatefulWidget {
  const MigrationAssistancePage({
    super.key,
    required this.data,
    this.onFinalizeTransactions,
    this.onMigrateTransactions,
  });

  final AppDataSnapshot data;
  final Future<MigrationBatchStatus> Function()? onFinalizeTransactions;
  final Future<MigrationExecutionResult> Function()? onMigrateTransactions;

  @override
  State<MigrationAssistancePage> createState() =>
      _MigrationAssistancePageState();
}

class _MigrationAssistancePageState extends State<MigrationAssistancePage> {
  bool _working = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final changes = calculateMigrationChanges(data);
    final status = MigrationBatchStatus.fromSnapshot(data);
    final canWrite =
        widget.onFinalizeTransactions != null &&
        widget.onMigrateTransactions != null;
    return AppPageFrame(
      title: 'Migration Assistance',
      subtitle:
          '${status.transactionCount} older transactions'
          '${canWrite ? '' : ' · read-only'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (canWrite) ...[
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.icon(
                  onPressed:
                      _working ||
                          status.isFinalized ||
                          status.transactionCount == 0 ||
                          status.transactionCount >
                              maximumMigrationTransactionCount
                      ? null
                      : _finalizeTransactions,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(
                    status.isFinalized
                        ? 'Transactions Finalized'
                        : 'Finalize Transactions',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _working ||
                          !status.isFinalized ||
                          status.isFullyMigrated ||
                          status.isPartiallyMigrated
                      ? null
                      : _confirmAndMigrate,
                  icon: const Icon(Icons.move_down),
                  label: const Text('Migrate Transactions'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (status.transactionCount == 0)
              const _MigrationNotice(
                icon: Icons.info_outline,
                color: AppColors.mutedText,
                message: 'Add migration transactions to the sheet to begin.',
              ),
            if (status.transactionCount > maximumMigrationTransactionCount)
              const _MigrationNotice(
                icon: Icons.error_outline,
                color: AppColors.danger,
                message:
                    'There are more than 9,999 migration transactions. '
                    'Reduce the batch before finalizing it.',
              ),
            if (status.isFinalized) _dateOrderNotice(status),
            if (status.isFullyMigrated)
              const _MigrationNotice(
                icon: Icons.check_circle_outline,
                color: AppColors.success,
                message:
                    'These migration transactions are already present in '
                    'the main Transactions sheet.',
              ),
            if (status.isPartiallyMigrated)
              const _MigrationNotice(
                icon: Icons.error_outline,
                color: AppColors.danger,
                message:
                    'Migration IDs are partially present or conflict with '
                    'rows in Transactions. Migration is blocked to prevent '
                    'duplicates; review the sheet before continuing.',
              ),
          ],
          if (status.transactionCount == 0)
            const EmptyState(message: 'No migration transactions to review.')
          else
            Card(
              clipBehavior: Clip.hardEdge,
              child: Column(
                children: [
                  for (var index = 0; index < changes.length; index++) ...[
                    if (index > 0) const Divider(height: 1),
                    _MigrationAccountRow(
                      change: changes[index],
                      data: data,
                      onTap: () => _showAccountTransactions(
                        context,
                        changes[index].account,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _dateOrderNotice(MigrationBatchStatus status) {
    final strictlyBefore = status.datesStrictlyBeforeOldestMainTransaction;
    if (strictlyBefore == null) {
      return const Padding(
        padding: EdgeInsets.only(bottom: AppSpacing.md),
        child: _MigrationNotice(
          icon: Icons.info_outline,
          color: AppColors.teal,
          message:
              'Finalized. There are no existing main transactions to compare '
              'the migration dates against.',
        ),
      );
    }
    final oldest = formatDate(status.oldestMainTransactionDate!);
    final message = strictlyBefore
        ? 'Date check passed: every migration date is strictly before the '
              'oldest main transaction ($oldest).'
        : 'Warning: not all migration dates are strictly before the oldest '
              'main transaction ($oldest). After migration, you will need to '
              'manually organize the main Transactions sheet.';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: _MigrationNotice(
        icon: strictlyBefore ? Icons.check_circle_outline : Icons.warning_amber,
        color: strictlyBefore ? AppColors.success : AppColors.warning,
        message: message,
      ),
    );
  }

  Future<void> _finalizeTransactions() async {
    final finalize = widget.onFinalizeTransactions;
    if (finalize == null || _working) return;
    setState(() => _working = true);
    try {
      await finalize();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Migration transactions finalized.')),
      );
    } catch (error) {
      if (mounted) showPersistentErrorDialog(context, error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _confirmAndMigrate() async {
    final migrate = widget.onMigrateTransactions;
    if (migrate == null || _working) return;
    final status = MigrationBatchStatus.fromSnapshot(widget.data);
    if (!status.isFinalized ||
        status.isFullyMigrated ||
        status.isPartiallyMigrated) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Confirm migration'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ensure you have manually updated the opening balances and '
                'opening dates in the Accounts sheet to account for these '
                'historical transactions. The Accounts sheet will not be '
                'changed by this migration.',
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'This will insert ${status.transactionCount} transactions '
                'below the header in the main Transactions sheet.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    if (status.datesStrictlyBeforeOldestMainTransaction == false) {
      final continueDespiteDateWarning = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Migration date warning'),
          content: Text(
            'The latest migration date (${formatDate(status.latestMigrationDate!)}) '
            'is not strictly before the oldest existing transaction '
            '(${formatDate(status.oldestMainTransactionDate!)}). After '
            'migration, you will need to manually organize the main '
            'Transactions sheet. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel migration'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Continue migration'),
            ),
          ],
        ),
      );
      if (!mounted || continueDespiteDateWarning != true) return;
    }

    setState(() => _working = true);
    try {
      final result = await migrate();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.wasAlreadyMigrated
                ? 'These migration transactions were already imported.'
                : '${result.transactionCount} transactions migrated.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) showPersistentErrorDialog(context, error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _showAccountTransactions(
    BuildContext context,
    Account account,
  ) async {
    final data = widget.data;
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

class _MigrationNotice extends StatelessWidget {
  const _MigrationNotice({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(AppRadii.control),
      border: Border.all(color: color.withValues(alpha: 0.28)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(message)),
      ],
    ),
  );
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
    return Container(
      color: change.transactionCount > 0 ? const Color(0xFFEAF7EF) : null,
      child: InkWell(
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

import 'package:flutter/material.dart';

import '../../data/data.dart';
import '../formatters.dart';
import '../theme/design_tokens.dart';
import 'category_visuals.dart';
import 'transaction_form.dart';

class TransactionDateHeader extends StatelessWidget {
  const TransactionDateHeader({super.key, required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
      child: Text(
        formatDate(date),
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class TransactionListRow extends StatelessWidget {
  const TransactionListRow({
    super.key,
    required this.transaction,
    required this.data,
    required this.onTap,
  });

  final Transaction transaction;
  final AppDataSnapshot data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < AppBreakpoints.compact;
    final sourceAccount = transaction.sourceAccountId == null
        ? null
        : data.accountsById[transaction.sourceAccountId!];
    final destinationAccount = transaction.destinationAccountId == null
        ? null
        : data.accountsById[transaction.destinationAccountId!];
    final category = transaction.categoryId == null
        ? null
        : data.categoriesById[transaction.categoryId!];
    final tag = transaction.tagId == null
        ? null
        : data.tagsById[transaction.tagId!];

    final detailParts = <String>[
      if (category != null) category.name,
      if (tag != null) tag.name,
      if (sourceAccount != null && destinationAccount != null)
        '${sourceAccount.name} → ${destinationAccount.name}'
      else if (sourceAccount != null)
        sourceAccount.name
      else if (destinationAccount != null)
        destinationAccount.name,
    ];

    return Card(
      clipBehavior: Clip.hardEdge,
      child: ListTile(
        onTap: onTap,
        contentPadding: EdgeInsets.symmetric(
          horizontal: compact ? AppSpacing.sm : AppSpacing.md,
          vertical: compact ? AppSpacing.xs / 2 : AppSpacing.xs,
        ),
        leading: CircleAvatar(
          radius: compact ? 18 : 20,
          backgroundColor: _backgroundColor(context),
          foregroundColor: _foregroundColor(context),
          child: Icon(_icon),
        ),
        title: Text(
          transaction.description.isEmpty
              ? transactionTypeLabel(transaction.type)
              : transaction.description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          detailParts.isEmpty
              ? transactionTypeLabel(transaction.type)
              : detailParts.join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: _buildAmount(context),
      ),
    );
  }

  Widget _buildAmount(BuildContext context) {
    if (transaction.type == TransactionType.transfer &&
        transaction.sourceAmount != null &&
        transaction.destinationAmount != null) {
      final amountStyle = Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w700);
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '-${formatMoney(transaction.sourceAmount!, data.currenciesById)}',
            textAlign: TextAlign.right,
            style: amountStyle?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          Text(
            '+${formatMoney(transaction.destinationAmount!, data.currenciesById)}',
            textAlign: TextAlign.right,
            style: amountStyle?.copyWith(color: AppColors.success),
          ),
        ],
      );
    }

    final amount = transaction.sourceAmount ?? transaction.destinationAmount;
    if (amount == null) return const Text('—');
    final isExpense = transaction.type == TransactionType.expense;
    final prefix = isExpense ? '-' : '+';
    return Text(
      '$prefix${formatMoney(amount, data.currenciesById)}',
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: isExpense
            ? Theme.of(context).colorScheme.error
            : AppColors.success,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Color _backgroundColor(BuildContext context) {
    final categoryColor = _categoryColor;
    if (categoryColor != null) return categoryColor.withValues(alpha: 0.14);
    return switch (transaction.type) {
      TransactionType.expense => Theme.of(context).colorScheme.errorContainer,
      TransactionType.income => Theme.of(
        context,
      ).colorScheme.secondaryContainer,
      TransactionType.reimbursement => Theme.of(
        context,
      ).colorScheme.tertiaryContainer,
      TransactionType.transfer => Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest,
    };
  }

  Color _foregroundColor(BuildContext context) =>
      _categoryColor ??
      switch (transaction.type) {
        TransactionType.expense => Theme.of(
          context,
        ).colorScheme.onErrorContainer,
        TransactionType.income => Theme.of(
          context,
        ).colorScheme.onSecondaryContainer,
        TransactionType.reimbursement => Theme.of(
          context,
        ).colorScheme.onTertiaryContainer,
        TransactionType.transfer => Theme.of(
          context,
        ).colorScheme.onSurfaceVariant,
      };

  Color? get _categoryColor {
    final category = transaction.categoryId == null
        ? null
        : data.categoriesById[transaction.categoryId!];
    return category == null ? null : categoryColor(category);
  }

  IconData get _icon {
    final category = transaction.categoryId == null
        ? null
        : data.categoriesById[transaction.categoryId!];
    if (category != null) return categoryIcon(category);
    return switch (transaction.type) {
      TransactionType.expense => Icons.arrow_upward,
      TransactionType.income => Icons.arrow_downward,
      TransactionType.reimbursement => Icons.replay,
      TransactionType.transfer => Icons.swap_horiz,
    };
  }
}

class TransactionDetailsSheet extends StatelessWidget {
  const TransactionDetailsSheet({
    super.key,
    required this.transaction,
    required this.data,
  });

  final Transaction transaction;
  final AppDataSnapshot data;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                transaction.description.isEmpty
                    ? transactionTypeLabel(transaction.type)
                    : transaction.description,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(formatDate(transaction.date)),
              const SizedBox(height: AppSpacing.lg),
              _DetailLine(
                label: 'Type',
                value: transactionTypeLabel(transaction.type),
              ),
              _DetailLine(
                label: 'Category',
                value: transaction.categoryId == null
                    ? '—'
                    : data.categoriesById[transaction.categoryId!]?.name ??
                          transaction.categoryId!,
              ),
              _DetailLine(
                label: 'Tag',
                value: transaction.tagId == null
                    ? '—'
                    : data.tagsById[transaction.tagId!]?.name ??
                          transaction.tagId!,
              ),
              const SizedBox(height: AppSpacing.md),
              if (transaction.sourceAccountId != null)
                _DetailLine(
                  label: 'Source',
                  value: _accountAmount(
                    transaction.sourceAccountId!,
                    transaction.sourceAmount,
                  ),
                ),
              if (transaction.destinationAccountId != null)
                _DetailLine(
                  label: 'Destination',
                  value: _accountAmount(
                    transaction.destinationAccountId!,
                    transaction.destinationAmount,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _accountAmount(String accountId, Money? amount) {
    final accountName = data.accountsById[accountId]?.name ?? accountId;
    if (amount == null) return accountName;
    return '$accountName · ${formatMoney(amount, data.currenciesById)}';
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.mutedText),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class EmptyTransactionsState extends StatelessWidget {
  const EmptyTransactionsState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.receipt_long_outlined,
            size: 48,
            color: AppColors.mutedText,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No Transactions Match These Filters.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text('Try Clearing One or More Filters.'),
        ],
      ),
    );
  }
}

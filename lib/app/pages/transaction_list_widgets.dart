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
    final compactSpacing = usesCompactVerticalSpacing(context);
    return Padding(
      padding: EdgeInsets.only(
        top: compactSpacing ? AppSpacing.xs : AppSpacing.sm,
        bottom: compactSpacing ? AppSpacing.xs / 2 : AppSpacing.xs,
      ),
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
    this.showAccountBalances = false,
  });

  final Transaction transaction;
  final AppDataSnapshot data;
  final VoidCallback onTap;
  final bool showAccountBalances;

  @override
  Widget build(BuildContext context) {
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

    final metadata = <String>[
      if (category != null) category.name,
      if (tag != null) tag.name,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < AppBreakpoints.compact;
        final enlargedText = MediaQuery.textScalerOf(context).scale(14) > 16.8;
        final internalGap = compact ? 1.0 : AppSpacing.xs / 2;
        return Card(
          margin: const EdgeInsets.fromLTRB(
            AppSpacing.xs,
            AppSpacing.sm,
            AppSpacing.xs,
            0,
          ),
          clipBehavior: Clip.hardEdge,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? AppSpacing.sm : AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: compact
                  ? _buildCompactRow(
                      context,
                      metadata: metadata,
                      sourceAccount: sourceAccount,
                      destinationAccount: destinationAccount,
                      internalGap: internalGap,
                    )
                  : _buildWideRow(
                      context,
                      metadata: metadata,
                      sourceAccount: sourceAccount,
                      destinationAccount: destinationAccount,
                      allowWrapping: enlargedText,
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompactRow(
    BuildContext context, {
    required List<String> metadata,
    required Account? sourceAccount,
    required Account? destinationAccount,
    required double internalGap,
  }) {
    final description = transaction.description.isEmpty
        ? transactionTypeLabel(transaction.type)
        : transaction.description;
    final isTransfer =
        transaction.type == TransactionType.transfer &&
        transaction.sourceAmount != null &&
        transaction.destinationAmount != null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final amountWidth = _compactAmountWidth(context);
        final transferAmountsWidth = isTransfer
            ? _compactTransferAmountsWidth(context, constraints.maxWidth)
            : 0.0;
        const minimumIdentityWidth = 120.0;
        final trailingAmountFits =
            !isTransfer &&
            !showAccountBalances &&
            constraints.maxWidth - 36 - AppSpacing.sm * 2 - amountWidth >=
                minimumIdentityWidth;
        final identity = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: internalGap),
              child: Text(description, maxLines: 2),
            ),
            if (metadata.isNotEmpty) ...[
              SizedBox(height: internalGap),
              Text(
                metadata.join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AppColors.mutedText),
              ),
            ],
            if (!isTransfer &&
                (sourceAccount != null || destinationAccount != null)) ...[
              SizedBox(height: internalGap),
              Text(
                (sourceAccount ?? destinationAccount)!.name,
                softWrap: true,
                style: _secondaryDetailStyle(context),
              ),
            ],
          ],
        );
        final leading = <Widget>[
          CircleAvatar(
            radius: 18,
            backgroundColor: _backgroundColor(context),
            foregroundColor: _foregroundColor(context),
            child: Icon(_icon),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: identity),
        ];

        if (isTransfer) {
          return _buildCompactTransferRow(
            context,
            description: description,
            metadata: metadata,
            sourceAccount: sourceAccount,
            destinationAccount: destinationAccount,
            internalGap: internalGap,
            amountWidth: transferAmountsWidth,
          );
        }

        if (trailingAmountFits) {
          return ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ...leading,
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: amountWidth,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _buildAmount(context),
                  ),
                ),
              ],
            ),
          );
        }

        return ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: leading,
              ),
              SizedBox(height: internalGap),
              Align(
                alignment: Alignment.centerRight,
                child: _buildAmount(context),
              ),
            ],
          ),
        );
      },
    );
  }

  double _compactAmountWidth(BuildContext context) {
    final amount = transaction.sourceAmount ?? transaction.destinationAmount;
    final text = amount == null
        ? '—'
        : '${transaction.type == TransactionType.expense ? '-' : '+'}'
              '${formatMoney(amount, data.currenciesById)}';
    final style = Theme.of(context).textTheme.titleMedium
        ?.copyWith(fontWeight: FontWeight.w700);
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    return painter.width + 2;
  }

  double _compactTransferAmountsWidth(
    BuildContext context,
    double availableWidth,
  ) {
    final sourceColor = Theme.of(context).colorScheme.error;
    final destinationColor = AppColors.success;
    final sourceAmountStyle = _compactTransferAmountStyle(context, sourceColor);
    final destinationAmountStyle = _compactTransferAmountStyle(
      context,
      destinationColor,
    );
    final balanceStyle = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: AppColors.mutedText);
    final sourceBalance = showAccountBalances
        ? _balanceAfter(transaction.sourceAccountId)
        : null;
    final destinationBalance = showAccountBalances
        ? _balanceAfter(transaction.destinationAccountId)
        : null;
    final values = <(String, TextStyle?)>[
      (
        '-${formatMoney(transaction.sourceAmount!, data.currenciesById)}',
        sourceAmountStyle,
      ),
      (
        '+${formatMoney(transaction.destinationAmount!, data.currenciesById)}',
        destinationAmountStyle,
      ),
      if (sourceBalance != null)
        (
          'Balance: ${formatMoney(sourceBalance, data.currenciesById)}',
          balanceStyle,
        ),
      if (destinationBalance != null)
        (
          'Balance: ${formatMoney(destinationBalance, data.currenciesById)}',
          balanceStyle,
        ),
    ];
    var width = 0.0;
    for (final (value, style) in values) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      if (painter.width > width) width = painter.width;
    }
    final identityWidthLimit = availableWidth - 36 - AppSpacing.sm * 2 - 120;
    final amountWidthLimit = identityWidthLimit < availableWidth * 0.45
        ? identityWidthLimit
        : availableWidth * 0.45;
    return (width + 2).clamp(0.0, amountWidthLimit).toDouble();
  }

  Widget _buildCompactTransferRow(
    BuildContext context, {
    required String description,
    required List<String> metadata,
    required Account? sourceAccount,
    required Account? destinationAccount,
    required double internalGap,
    required double amountWidth,
  }) {
    final detailLines = [
      'From · ${sourceAccount?.name ?? 'Account unavailable'}',
      'To · ${destinationAccount?.name ?? 'Account unavailable'}',
    ];
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: _backgroundColor(context),
            foregroundColor: _foregroundColor(context),
            child: Icon(_icon),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: internalGap),
                  child: Text(description, maxLines: 2),
                ),
                if (metadata.isNotEmpty) ...[
                  SizedBox(height: internalGap),
                  Text(
                    metadata.join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _secondaryDetailStyle(context),
                  ),
                ],
                for (final line in detailLines) ...[
                  SizedBox(height: internalGap),
                  Text(
                    line,
                    softWrap: true,
                    style: _secondaryDetailStyle(context),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: amountWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _amountWithBalance(
                  context,
                  amount: transaction.sourceAmount!,
                  accountId: transaction.sourceAccountId,
                  prefix: '-',
                  color: Theme.of(context).colorScheme.error,
                  amountStyle: _compactTransferAmountStyle(
                    context,
                    Theme.of(context).colorScheme.error,
                  ),
                ),
                SizedBox(height: internalGap),
                _amountWithBalance(
                  context,
                  amount: transaction.destinationAmount!,
                  accountId: transaction.destinationAccountId,
                  prefix: '+',
                  color: AppColors.success,
                  amountStyle: _compactTransferAmountStyle(
                    context,
                    AppColors.success,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TextStyle? _secondaryDetailStyle(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: AppColors.mutedText);

  TextStyle? _compactTransferAmountStyle(BuildContext context, Color color) =>
      Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: color, fontWeight: FontWeight.w700);

  Widget _buildWideRow(
    BuildContext context, {
    required List<String> metadata,
    required Account? sourceAccount,
    required Account? destinationAccount,
    required bool allowWrapping,
  }) {
    final detailParts = [
      ...metadata,
      if (sourceAccount != null && destinationAccount != null)
        '${sourceAccount.name} → ${destinationAccount.name}'
      else if (sourceAccount != null)
        sourceAccount.name
      else if (destinationAccount != null)
        destinationAccount.name,
    ];
    final description = transaction.description.isEmpty
        ? transactionTypeLabel(transaction.type)
        : transaction.description;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: _backgroundColor(context),
            foregroundColor: _foregroundColor(context),
            child: Icon(_icon),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: allowWrapping
                ? _buildExpandedWideDetails(
                    context,
                    description: description,
                    metadata: metadata,
                    sourceAccount: sourceAccount,
                    destinationAccount: destinationAccount,
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.xs / 2),
                      Text(
                        detailParts.isEmpty
                            ? transactionTypeLabel(transaction.type)
                            : detailParts.join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _secondaryDetailStyle(context),
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _buildAmount(context),
        ],
      ),
    );
  }

  Widget _buildExpandedWideDetails(
    BuildContext context, {
    required String description,
    required List<String> metadata,
    required Account? sourceAccount,
    required Account? destinationAccount,
  }) {
    final accountLines = <String>[];
    if (transaction.type == TransactionType.transfer) {
      if (transaction.sourceAccountId != null) {
        accountLines.add(
          'From · ${sourceAccount?.name ?? 'Account unavailable'}',
        );
      }
      if (transaction.destinationAccountId != null) {
        accountLines.add(
          'To · ${destinationAccount?.name ?? 'Account unavailable'}',
        );
      }
    } else if (sourceAccount != null || destinationAccount != null) {
      accountLines.add((sourceAccount ?? destinationAccount)!.name);
    }

    final detailLines = [
      if (metadata.isNotEmpty) metadata.join(' · '),
      ...accountLines,
      if (metadata.isEmpty && accountLines.isEmpty)
        transactionTypeLabel(transaction.type),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(description, softWrap: true),
        for (final line in detailLines) ...[
          const SizedBox(height: AppSpacing.xs / 2),
          Text(line, softWrap: true, style: _secondaryDetailStyle(context)),
        ],
      ],
    );
  }

  Widget _buildAmount(BuildContext context) {
    if (transaction.type == TransactionType.transfer &&
        transaction.sourceAmount != null &&
        transaction.destinationAmount != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          _amountWithBalance(
            context,
            amount: transaction.sourceAmount!,
            accountId: transaction.sourceAccountId,
            prefix: '-',
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: AppSpacing.xs),
          _amountWithBalance(
            context,
            amount: transaction.destinationAmount!,
            accountId: transaction.destinationAccountId,
            prefix: '+',
            color: AppColors.success,
          ),
        ],
      );
    }

    final amount = transaction.sourceAmount ?? transaction.destinationAmount;
    if (amount == null) return const Text('—');
    final isExpense = transaction.type == TransactionType.expense;
    final accountId = transaction.sourceAmount != null
        ? transaction.sourceAccountId
        : transaction.destinationAccountId;
    return _amountWithBalance(
      context,
      amount: amount,
      accountId: accountId,
      prefix: isExpense ? '-' : '+',
      color: isExpense
          ? Theme.of(context).colorScheme.error
          : AppColors.success,
    );
  }

  Widget _amountWithBalance(
    BuildContext context, {
    required Money amount,
    required String? accountId,
    required String prefix,
    required Color color,
    TextStyle? amountStyle,
  }) {
    final balance = showAccountBalances ? _balanceAfter(accountId) : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _completeValueText(
          context,
          '$prefix${formatMoney(amount, data.currenciesById)}',
          style:
              amountStyle ??
              Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
        if (showAccountBalances && balance != null)
          _completeValueText(
            context,
            'Balance: ${formatMoney(balance, data.currenciesById)}',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: AppColors.mutedText),
          ),
      ],
    );
  }

  Widget _completeValueText(
    BuildContext context,
    String value, {
    required TextStyle? style,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final text = Text(
        value,
        textAlign: TextAlign.right,
        maxLines: 1,
        softWrap: false,
        style: style,
      );
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

  Money? _balanceAfter(String? accountId) {
    if (accountId == null ||
        data.accountsById[accountId]?.isLedgerAccount != true) {
      return null;
    }
    return data.balanceAfterTransaction(accountId, transaction.id);
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
                    transaction.type == TransactionType.expense ||
                            transaction.type == TransactionType.transfer
                        ? '-'
                        : '+',
                  ),
                ),
              if (transaction.destinationAccountId != null)
                _DetailLine(
                  label: 'Destination',
                  value: _accountAmount(
                    transaction.destinationAccountId!,
                    transaction.destinationAmount,
                    '+',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _accountAmount(String accountId, Money? amount, String prefix) {
    final accountName = data.accountsById[accountId]?.name ?? accountId;
    if (amount == null) return accountName;
    return '$accountName · $prefix${formatMoney(amount, data.currenciesById)}';
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 420 ||
              MediaQuery.textScalerOf(context).scale(14) > 16.8;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppColors.mutedText)),
                const SizedBox(height: AppSpacing.xs / 2),
                Text(value),
              ],
            );
          }
          return Row(
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
          );
        },
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

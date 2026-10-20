import 'package:flutter/material.dart';

import '../../data/data.dart';
import '../formatters.dart';
import '../theme/design_tokens.dart';

class TransactionReviewSheet extends StatelessWidget {
  const TransactionReviewSheet({
    super.key,
    required this.transaction,
    required this.data,
  });

  final Transaction transaction;
  final AppDataSnapshot data;

  @override
  Widget build(BuildContext context) {
    final category = transaction.categoryId == null
        ? null
        : data.categoriesById[transaction.categoryId!];
    final tag = transaction.tagId == null
        ? null
        : data.tagsById[transaction.tagId!];
    final source = transaction.sourceAccountId == null
        ? null
        : data.accountsById[transaction.sourceAccountId!];
    final destination = transaction.destinationAccountId == null
        ? null
        : data.accountsById[transaction.destinationAccountId!];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Review Transaction',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.md),
            _row('Description', transaction.description),
            _row('Date', formatDate(transaction.date)),
            if (source != null) _row('Source Account', source.name),
            if (destination != null)
              _row('Destination Account', destination.name),
            if (transaction.sourceAmount != null)
              _row(
                'Amount',
                formatMoney(transaction.sourceAmount!, data.currenciesById),
              ),
            if (transaction.destinationAmount != null)
              _row(
                'Amount',
                formatMoney(
                  transaction.destinationAmount!,
                  data.currenciesById,
                ),
              ),
            if (category != null) _row('Category', category.name),
            if (tag != null) _row('Tag', tag.name),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Okay'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Row(
      children: [
        SizedBox(width: 140, child: Text(label)),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

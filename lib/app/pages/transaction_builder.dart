import 'dart:math';

import '../../data/data.dart';

class TransferBuildResult {
  const TransferBuildResult({required this.transactions, this.error});

  final List<Transaction> transactions;
  final String? error;

  bool get isValid => error == null;
}

const _transactionIdAlphabet =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
const _transactionIdLength = 12;

String generateTransactionId(Iterable<String> existingIds, {Random? random}) {
  final existing = existingIds.toSet();
  final generator = random ?? Random.secure();
  String candidate;
  do {
    candidate = List.generate(
      _transactionIdLength,
      (_) =>
          _transactionIdAlphabet[generator.nextInt(
            _transactionIdAlphabet.length,
          )],
    ).join();
  } while (existing.contains(candidate));
  return candidate;
}

TransferBuildResult buildTransferTransactions({
  required Iterable<String> existingIds,
  required DateTime date,
  required String description,
  required String? sourceAccountId,
  required Money? sourceAmount,
  required String? destinationAccountId,
  required Money? destinationAmount,
  required Money? sourceFee,
  required Money? destinationFee,
  required bool sameCurrency,
  required String? categoryId,
  required String? tagId,
  required bool hasFinancialFeesCategory,
}) {
  if ((sourceFee != null || destinationFee != null) &&
      !hasFinancialFeesCategory) {
    return const TransferBuildResult(
      transactions: [],
      error: 'Financial Fees category is required.',
    );
  }
  if (sourceFee != null &&
      sourceAmount != null &&
      sourceFee.minorUnits >= sourceAmount.minorUnits) {
    return const TransferBuildResult(
      transactions: [],
      error: 'Source fee must be less than the transfer amount.',
    );
  }

  final transferAmounts = calculateTransferAmounts(
    sameCurrency: sameCurrency,
    sourceAmount: sourceAmount,
    destinationAmount: destinationAmount,
    sourceFee: sourceFee,
  );
  final normalizedDate = DateTime.utc(date.year, date.month, date.day);
  final generated = <Transaction>[];
  final feeDescription = 'Transfer Fee - ${description.trim()}';
  for (final entry in [
    (sourceFee, sourceAccountId),
    (destinationFee, destinationAccountId),
  ]) {
    if (entry.$1 == null || entry.$2 == null) continue;
    generated.add(
      Transaction(
        id: generateTransactionId({
          ...existingIds,
          ...generated.map((item) => item.id),
        }),
        createdAt: DateTime.now().toUtc(),
        date: normalizedDate,
        type: TransactionType.expense,
        sourceAmount: entry.$1,
        sourceAccountId: entry.$2,
        destinationAmount: null,
        destinationAccountId: null,
        categoryId: 'financial_fees',
        tagId: tagId,
        description: feeDescription,
      ),
    );
  }
  generated.insert(
    sourceFee == null ? 0 : 1,
    Transaction(
      id: generateTransactionId({
        ...existingIds,
        ...generated.map((item) => item.id),
      }),
      createdAt: DateTime.now().toUtc(),
      date: normalizedDate,
      type: TransactionType.transfer,
      sourceAmount: transferAmounts.source,
      sourceAccountId: sourceAccountId,
      destinationAmount: transferAmounts.destination,
      destinationAccountId: destinationAccountId,
      categoryId: categoryId,
      tagId: tagId,
      description: description.trim(),
    ),
  );

  final errors = generated.expand((item) => item.validateForEntry()).toList();
  if (errors.isNotEmpty) {
    return TransferBuildResult(transactions: const [], error: errors.join(' '));
  }
  return TransferBuildResult(transactions: generated);
}

({Money? source, Money? destination}) calculateTransferAmounts({
  required bool sameCurrency,
  required Money? sourceAmount,
  required Money? destinationAmount,
  required Money? sourceFee,
}) {
  final transferSourceAmount = sourceFee == null || sourceAmount == null
      ? sourceAmount
      : sourceAmount - sourceFee;
  return (
    source: transferSourceAmount,
    destination: sameCurrency ? transferSourceAmount : destinationAmount,
  );
}

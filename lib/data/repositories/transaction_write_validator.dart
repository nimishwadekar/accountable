import '../app_data_snapshot.dart';
import '../models/models.dart';

List<String> validateTransactionForWrite(
  Transaction transaction,
  AppDataSnapshot data,
) {
  final errors = [...transaction.validateForEntry()];

  void validateSide({
    required String side,
    required String? accountId,
    required Money? amount,
  }) {
    if (accountId == null) return;
    final account = data.accountsById[accountId];
    if (account == null) {
      errors.add('Unknown $side account: $accountId.');
      return;
    }
    if (amount != null && amount.currencyId != account.currencyId) {
      errors.add(
        '$side amount currency ${amount.currencyId} does not match '
        'account currency ${account.currencyId}.',
      );
    }
    if (amount != null && amount.minorUnits < 0) {
      errors.add('$side amount cannot be negative.');
    }
    if (!_accountIsActiveOn(account, transaction.date)) {
      errors.add('Transaction date is outside account ${account.id} lifetime.');
    }
  }

  validateSide(
    side: 'source',
    accountId: transaction.sourceAccountId,
    amount: transaction.sourceAmount,
  );
  validateSide(
    side: 'destination',
    accountId: transaction.destinationAccountId,
    amount: transaction.destinationAmount,
  );

  if (transaction.categoryId != null) {
    final category = data.categoriesById[transaction.categoryId];
    if (category == null) {
      errors.add('Unknown category: ${transaction.categoryId}.');
    } else if (!category.allowedTransactionTypes.contains(transaction.type)) {
      errors.add(
        'Category ${transaction.categoryId} is not allowed for '
        '${transaction.type.wireValue} transactions.',
      );
    }
  }
  if (transaction.tagId != null &&
      !data.tagsById.containsKey(transaction.tagId)) {
    errors.add('Unknown tag: ${transaction.tagId}.');
  }

  return errors;
}

bool _accountIsActiveOn(Account account, DateTime date) {
  final transactionDate = _dateOnly(date);
  final openingDate = _dateOnly(account.openingDate);
  final closingDate = account.closingDate == null
      ? null
      : _dateOnly(account.closingDate!);
  return !transactionDate.isBefore(openingDate) &&
      (closingDate == null || !transactionDate.isAfter(closingDate));
}

DateTime _dateOnly(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

List<String> validateTransactionsForWrite(
  Iterable<Transaction> transactions,
  AppDataSnapshot data,
) {
  final errors = <String>[];
  final knownIds = data.transactionsById.keys.toSet();
  for (final transaction in transactions) {
    if (!knownIds.add(transaction.id)) {
      errors.add('Duplicate transaction ID: ${transaction.id}.');
    }
    errors.addAll(validateTransactionForWrite(transaction, data));
  }
  return errors;
}

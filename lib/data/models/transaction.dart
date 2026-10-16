import 'currency.dart';
import 'money.dart';

enum TransactionType {
  expense,
  income,
  reimbursement,
  transfer,
}

extension TransactionTypeWireValue on TransactionType {
  String get wireValue => switch (this) {
        TransactionType.expense => 'expense',
        TransactionType.income => 'income',
        TransactionType.reimbursement => 'reimbursement',
        TransactionType.transfer => 'transfer',
      };

  static TransactionType parse(String value) {
    return switch (value.trim().toLowerCase()) {
      'expense' => TransactionType.expense,
      'income' => TransactionType.income,
      'reimbursement' => TransactionType.reimbursement,
      'transfer' => TransactionType.transfer,
      _ => throw FormatException('Unknown transaction type: $value.'),
    };
  }
}

class TransactionTypeRule {
  const TransactionTypeRule({
    required this.sourceRequired,
    required this.destinationRequired,
    required this.categoryRequired,
  });

  final bool sourceRequired;
  final bool destinationRequired;
  final bool categoryRequired;
}

const transactionTypeRules = <TransactionType, TransactionTypeRule>{
  TransactionType.expense: TransactionTypeRule(
    sourceRequired: true,
    destinationRequired: false,
    categoryRequired: true,
  ),
  TransactionType.income: TransactionTypeRule(
    sourceRequired: false,
    destinationRequired: true,
    categoryRequired: true,
  ),
  TransactionType.reimbursement: TransactionTypeRule(
    sourceRequired: false,
    destinationRequired: true,
    categoryRequired: true,
  ),
  TransactionType.transfer: TransactionTypeRule(
    sourceRequired: true,
    destinationRequired: true,
    categoryRequired: false,
  ),
};

Map<String, String> transactionToRow(
  Transaction transaction,
  Map<String, CurrencyDefinition> currencies,
  Map<String, String> accountCurrencies,
) {
  String? amountFor(Money? amount, String? accountId) {
    if (amount == null || accountId == null) return null;
    final currencyId = accountCurrencies[accountId];
    final currency = currencyId == null ? null : currencies[currencyId];
    if (currency == null) {
      throw StateError('Unknown currency for account $accountId.');
    }
    return amount.toMajorUnits(currency).toString();
  }

  return {
    'transaction_id': transaction.id,
    'created_at': transaction.createdAt.toUtc().toIso8601String(),
    'date': _dateToString(transaction.date),
    'transaction_type': transaction.type.wireValue,
    'source_amount': amountFor(transaction.sourceAmount, transaction.sourceAccountId) ?? '',
    'source_account_id': transaction.sourceAccountId ?? '',
    'dest_amount': amountFor(transaction.destinationAmount, transaction.destinationAccountId) ?? '',
    'dest_account_id': transaction.destinationAccountId ?? '',
    'category': transaction.categoryId ?? '',
    'tag': transaction.tagId ?? '',
    'description': transaction.description,
  };
}

String _dateToString(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

class Transaction {
  const Transaction({
    required this.id,
    required this.createdAt,
    required this.date,
    required this.type,
    required this.sourceAmount,
    required this.sourceAccountId,
    required this.destinationAmount,
    required this.destinationAccountId,
    required this.categoryId,
    required this.tagId,
    required this.description,
  });

  final String id;
  final DateTime createdAt;

  /// A UTC DateTime containing only the local calendar date selected by the user.
  final DateTime date;

  final TransactionType type;
  final Money? sourceAmount;
  final String? sourceAccountId;
  final Money? destinationAmount;
  final String? destinationAccountId;
  final String? categoryId;
  final String? tagId;
  final String description;

  List<String> validate() {
    final rule = transactionTypeRules[type]!;
    final errors = <String>[];
    final hasSource = sourceAmount != null && sourceAccountId != null;
    final hasDestination =
        destinationAmount != null && destinationAccountId != null;

    if (rule.sourceRequired && !hasSource) {
      errors.add('${type.wireValue} requires a source account and amount.');
    }
    if (!rule.sourceRequired && (sourceAmount != null || sourceAccountId != null)) {
      errors.add('${type.wireValue} cannot have a source account and amount.');
    }
    if (rule.destinationRequired && !hasDestination) {
      errors.add(
        '${type.wireValue} requires a destination account and amount.',
      );
    }
    if (!rule.destinationRequired &&
        (destinationAmount != null || destinationAccountId != null)) {
      errors.add(
        '${type.wireValue} cannot have a destination account and amount.',
      );
    }
    if (rule.categoryRequired && categoryId == null) {
      errors.add('${type.wireValue} requires a category.');
    }

    return errors;
  }

  List<String> validateForEntry() {
    final errors = [...validate()];
    if (tagId == null) errors.add('A tag is required.');
    if (description.trim().isEmpty) errors.add('A description is required.');
    return errors;
  }
}

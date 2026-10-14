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
    categoryRequired: false,
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
}

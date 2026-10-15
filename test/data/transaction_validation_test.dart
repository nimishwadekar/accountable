import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';

void main() {
  const currency = CurrencyDefinition(
    id: 'USD',
    symbol: r'$',
    decimalPlaces: 2,
  );
  final amount = Money.fromMajorUnits(value: '10', currency: currency);

  Transaction build({
    required TransactionType type,
    Money? sourceAmount,
    String? sourceAccountId,
    Money? destinationAmount,
    String? destinationAccountId,
    String? categoryId,
    String? tagId,
    String description = 'Valid',
  }) {
    return Transaction(
      id: 'test',
      createdAt: DateTime.utc(2026, 1, 1),
      date: DateTime.utc(2026, 1, 1),
      type: type,
      sourceAmount: sourceAmount,
      sourceAccountId: sourceAccountId,
      destinationAmount: destinationAmount,
      destinationAccountId: destinationAccountId,
      categoryId: categoryId,
      tagId: tagId,
      description: description,
    );
  }

  test('parses all supported transaction type wire values', () {
    for (final type in TransactionType.values) {
      expect(TransactionTypeWireValue.parse(type.wireValue), type);
    }
    expect(
      () => TransactionTypeWireValue.parse('unknown'),
      throwsFormatException,
    );
  });

  test('validates required and forbidden transaction sides', () {
    expect(build(type: TransactionType.expense).validate(), isNotEmpty);
    expect(
      build(
        type: TransactionType.expense,
        sourceAmount: amount,
        sourceAccountId: 'checking',
      ).validate(),
      isNotEmpty,
    );
    expect(
      build(
        type: TransactionType.income,
        sourceAmount: amount,
        sourceAccountId: 'checking',
        destinationAmount: amount,
        destinationAccountId: 'checking',
      ).validate(),
      isNotEmpty,
    );
    expect(
      build(
        type: TransactionType.transfer,
        sourceAmount: amount,
        sourceAccountId: 'checking',
        destinationAmount: amount,
        destinationAccountId: 'savings',
      ).validate(),
      isEmpty,
    );
  });

  test('entry validation requires tag and description', () {
    final transaction = build(
      type: TransactionType.expense,
      sourceAmount: amount,
      sourceAccountId: 'checking',
      categoryId: 'food',
      description: ' ',
    );

    expect(transaction.validateForEntry(), contains('A tag is required.'));
    expect(
      transaction.validateForEntry(),
      contains('A description is required.'),
    );
  });

  test(
    'transaction rows preserve optional sides and reject unknown currencies',
    () {
      final transaction = build(
        type: TransactionType.expense,
        sourceAmount: amount,
        sourceAccountId: 'checking',
        categoryId: 'food',
        tagId: 'trip',
      );
      final row = transactionToRow(
        transaction,
        {'USD': currency},
        {'checking': 'USD'},
      );

      expect(row['source_amount'], '10');
      expect(row['dest_amount'], isEmpty);
      expect(row['tag'], 'trip');
      expect(
        () => transactionToRow(transaction, {}, {'checking': 'EUR'}),
        throwsStateError,
      );
    },
  );
}

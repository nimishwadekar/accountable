import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/pages/transaction_builder.dart';
import 'package:accountable/data/data.dart';

void main() {
  const usd = CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2);
  const inr = CurrencyDefinition(id: 'INR', symbol: '₹', decimalPlaces: 2);

  test('same-currency fees reduce the transfer and preserve both fee legs', () {
    final result = buildTransferTransactions(
      existingIds: const {'already-used-id'},
      date: DateTime(2026, 1, 12, 19, 30),
      description: '  Move savings  ',
      sourceAccountId: 'checking',
      sourceAmount: Money.fromMajorUnits(value: '100', currency: usd),
      destinationAccountId: 'savings',
      destinationAmount: Money.fromMajorUnits(value: '95', currency: usd),
      sourceFee: Money.fromMajorUnits(value: '2', currency: usd),
      destinationFee: Money.fromMajorUnits(value: '1', currency: usd),
      sameCurrency: true,
      categoryId: 'transfer',
      tagId: 'tag',
      hasFinancialFeesCategory: true,
    );

    expect(result.isValid, isTrue);
    expect(result.error, isNull);
    expect(result.transactions, hasLength(3));
    final transfer = result.transactions.singleWhere(
      (transaction) => transaction.type == TransactionType.transfer,
    );
    expect(transfer.sourceAmount?.minorUnits, 9800);
    expect(transfer.destinationAmount?.minorUnits, 9800);
    expect(transfer.description, 'Move savings');
    expect(transfer.date, DateTime.utc(2026, 1, 12));

    final fees = result.transactions
        .where((transaction) => transaction.type == TransactionType.expense)
        .toList();
    expect(
      fees.map((fee) => fee.sourceAmount?.minorUnits),
      containsAll([200, 100]),
    );
    expect(
      fees.map((fee) => fee.sourceAccountId),
      containsAll(['checking', 'savings']),
    );
    expect(fees.every((fee) => fee.categoryId == 'financial_fees'), isTrue);
    expect(
      fees.every((fee) => fee.description == 'Transfer Fee - Move savings'),
      isTrue,
    );
    expect(
      result.transactions.map((transaction) => transaction.id).toSet(),
      hasLength(3),
    );
    expect(
      result.transactions.map((transaction) => transaction.id),
      isNot(contains('already-used-id')),
    );
  });

  test('cross-currency source fees do not alter the destination amount', () {
    final result = buildTransferTransactions(
      existingIds: const {},
      date: DateTime.utc(2026, 2, 1),
      description: 'Cross-currency transfer',
      sourceAccountId: 'checking',
      sourceAmount: Money.fromMajorUnits(value: '100', currency: usd),
      destinationAccountId: 'savings-inr',
      destinationAmount: Money.fromMajorUnits(value: '8300', currency: inr),
      sourceFee: Money.fromMajorUnits(value: '3', currency: usd),
      destinationFee: null,
      sameCurrency: false,
      categoryId: 'transfer',
      tagId: 'tag',
      hasFinancialFeesCategory: true,
    );

    expect(result.isValid, isTrue);
    final transfer = result.transactions.singleWhere(
      (transaction) => transaction.type == TransactionType.transfer,
    );
    expect(transfer.sourceAmount?.minorUnits, 9700);
    expect(transfer.sourceAmount?.currencyId, 'USD');
    expect(transfer.destinationAmount?.minorUnits, 830000);
    expect(transfer.destinationAmount?.currencyId, 'INR');
    expect(result.transactions, hasLength(2));
  });

  test('rejects missing fee category and fees that consume the source', () {
    TransferBuildResult build({
      required Money? sourceFee,
      required bool hasFinancialFeesCategory,
    }) => buildTransferTransactions(
      existingIds: const {},
      date: DateTime.utc(2026, 3, 1),
      description: 'Transfer',
      sourceAccountId: 'checking',
      sourceAmount: Money.fromMajorUnits(value: '10', currency: usd),
      destinationAccountId: 'savings',
      destinationAmount: Money.fromMajorUnits(value: '10', currency: usd),
      sourceFee: sourceFee,
      destinationFee: null,
      sameCurrency: true,
      categoryId: 'transfer',
      tagId: 'tag',
      hasFinancialFeesCategory: hasFinancialFeesCategory,
    );

    final missingCategory = build(
      sourceFee: Money.fromMajorUnits(value: '1', currency: usd),
      hasFinancialFeesCategory: false,
    );
    expect(missingCategory.isValid, isFalse);
    expect(missingCategory.transactions, isEmpty);
    expect(missingCategory.error, 'Financial Fees category is required.');

    final consumedAmount = build(
      sourceFee: Money.fromMajorUnits(value: '10', currency: usd),
      hasFinancialFeesCategory: true,
    );
    expect(consumedAmount.isValid, isFalse);
    expect(consumedAmount.transactions, isEmpty);
    expect(
      consumedAmount.error,
      'Source fee must be less than the transfer amount.',
    );
  });

  test('does not return a transfer when required account sides are absent', () {
    final result = buildTransferTransactions(
      existingIds: const {},
      date: DateTime.utc(2026, 3, 1),
      description: 'Incomplete transfer',
      sourceAccountId: null,
      sourceAmount: null,
      destinationAccountId: 'savings',
      destinationAmount: Money.fromMajorUnits(value: '10', currency: usd),
      sourceFee: null,
      destinationFee: null,
      sameCurrency: false,
      categoryId: 'transfer',
      tagId: 'tag',
      hasFinancialFeesCategory: true,
    );

    expect(result.isValid, isFalse);
    expect(result.transactions, isEmpty);
    expect(
      result.error,
      contains('transfer requires a source account and amount.'),
    );
  });
}

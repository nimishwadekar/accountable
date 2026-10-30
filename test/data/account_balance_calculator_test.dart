import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';

void main() {
  test('calculates balances from opening values and transactions', () {
    const usd = CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2);
    final checking = Account(
      id: 'checking',
      name: 'Checking',
      accountType: 'cash',
      currencyId: 'USD',
      openingBalance: Money.fromMajorUnits(value: '1000', currency: usd),
      openingDate: DateTime.utc(2026, 1, 1),
      closingDate: null,
      usesManualValuations: false,
    );
    final transactions = [
      Transaction(
        id: 'expense',
        createdAt: DateTime.utc(2026, 1, 1),
        date: DateTime.utc(2026, 1, 1),
        type: TransactionType.expense,
        sourceAmount: Money.fromMajorUnits(value: '40', currency: usd),
        sourceAccountId: 'checking',
        destinationAmount: null,
        destinationAccountId: null,
        categoryId: 'food',
        tagId: 'tag',
        description: 'Food',
      ),
      Transaction(
        id: 'income',
        createdAt: DateTime.utc(2026, 1, 1),
        date: DateTime.utc(2026, 1, 1),
        type: TransactionType.income,
        sourceAmount: null,
        sourceAccountId: null,
        destinationAmount: Money.fromMajorUnits(value: '100', currency: usd),
        destinationAccountId: 'checking',
        categoryId: null,
        tagId: 'tag',
        description: 'Income',
      ),
    ];

    final balances = const AccountBalanceCalculator().calculate(
      accounts: [checking],
      transactions: transactions,
    );

    expect(balances['checking']?.minorUnits, 106000);
  });

  test('rejects a transaction referencing an unknown account', () {
    const usd = CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2);
    final transaction = Transaction(
      id: 'bad',
      createdAt: DateTime.utc(2026, 1, 1),
      date: DateTime.utc(2026, 1, 1),
      type: TransactionType.expense,
      sourceAmount: Money.fromMajorUnits(value: '1', currency: usd),
      sourceAccountId: 'missing',
      destinationAmount: null,
      destinationAccountId: null,
      categoryId: 'food',
      tagId: 'tag',
      description: 'Bad',
    );

    expect(
      () => AccountBalanceCalculator().calculate(
        accounts: const [],
        transactions: [transaction],
      ),
      throwsStateError,
    );
  });

  test('rejects a transfer referencing an unknown destination account', () {
    const usd = CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2);
    final checking = Account(
      id: 'checking',
      name: 'Checking',
      accountType: 'cash',
      currencyId: 'USD',
      openingBalance: Money.zero(usd),
      openingDate: DateTime.utc(2026, 1, 1),
      closingDate: null,
      usesManualValuations: false,
    );
    final transfer = Transaction(
      id: 'transfer-with-missing-destination',
      createdAt: DateTime.utc(2026, 1, 2),
      date: DateTime.utc(2026, 1, 2),
      type: TransactionType.transfer,
      sourceAmount: Money(minorUnits: 500, currencyId: 'USD'),
      sourceAccountId: 'checking',
      destinationAmount: Money(minorUnits: 500, currencyId: 'USD'),
      destinationAccountId: 'missing',
      categoryId: 'transfer',
      tagId: 'tag',
      description: 'Transfer to a deleted account',
    );

    expect(
      () => const AccountBalanceCalculator().calculate(
        accounts: [checking],
        transactions: [transfer],
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Unknown destination account: missing.',
        ),
      ),
    );
  });
}

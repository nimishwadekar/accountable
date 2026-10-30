import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    DateTime? date,
  }) {
    return Transaction(
      id: 'test',
      createdAt: DateTime.utc(2026, 1, 1),
      date: date ?? DateTime.utc(2026, 1, 1),
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
    final invalidIncome = build(
      type: TransactionType.income,
      sourceAmount: amount,
      sourceAccountId: 'checking',
      destinationAmount: amount,
      destinationAccountId: 'checking',
    );
    expect(invalidIncome.validate(), isNotEmpty);
    expect(invalidIncome.validate(), contains('income requires a category.'));
    expect(
      build(
        type: TransactionType.transfer,
        sourceAmount: amount,
        sourceAccountId: 'checking',
        destinationAmount: amount,
        destinationAccountId: 'savings',
        categoryId: 'general',
      ).validate(),
      isEmpty,
    );
    expect(
      build(
        type: TransactionType.expense,
        sourceAmount: amount,
        sourceAccountId: 'checking',
        destinationAmount: amount,
        destinationAccountId: 'savings',
      ).validate(),
      contains('expense cannot have a destination account and amount.'),
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

  test('write validation checks references and duplicate IDs', () async {
    final data = await AssetAppDataRepository().load();
    final transaction = build(
      type: TransactionType.expense,
      sourceAmount: amount,
      sourceAccountId: 'chase_checking',
      categoryId: 'salary',
      tagId: 'missing-tag',
    );

    final errors = validateTransactionsForWrite([
      transaction,
      transaction,
    ], data);

    expect(
      errors,
      contains('Category salary is not allowed for expense transactions.'),
    );
    expect(errors, contains('Unknown tag: missing-tag.'));
    expect(errors, contains('Duplicate transaction ID: test.'));
  });

  test(
    'write validation rejects transaction dates outside account lifetime',
    () async {
      final data = await AssetAppDataRepository().load();
      final inr = data.currenciesById['INR']!;
      final transaction = build(
        type: TransactionType.expense,
        sourceAmount: Money.fromMajorUnits(value: '10', currency: inr),
        sourceAccountId: 'sbi_nro',
        categoryId: 'groceries',
        tagId: 'boston',
        date: DateTime.utc(2026, 10, 12),
      );

      expect(
        validateTransactionForWrite(transaction, data),
        contains('Transaction date is outside account sbi_nro lifetime.'),
      );
    },
  );

  test(
    'write validation checks both account references and amount currencies',
    () {
      const usd = CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2);
      const inr = CurrencyDefinition(id: 'INR', symbol: '₹', decimalPlaces: 2);
      const eur = CurrencyDefinition(id: 'EUR', symbol: '€', decimalPlaces: 2);
      final checking = Account(
        id: 'checking',
        name: 'Checking',
        accountType: 'cash',
        currencyId: 'USD',
        openingBalance: Money.zero(usd),
        openingDate: DateTime.utc(2026, 1, 1),
        closingDate: DateTime.utc(2026, 1, 31),
        usesManualValuations: false,
      );
      final savings = Account(
        id: 'savings',
        name: 'Savings',
        accountType: 'cash',
        currencyId: 'INR',
        openingBalance: Money.zero(inr),
        openingDate: DateTime.utc(2026, 1, 1),
        closingDate: null,
        usesManualValuations: false,
      );
      final data = AppDataSnapshot(
        accounts: [checking, savings],
        categories: const [
          Category(
            id: 'expense',
            name: 'Expense',
            allowedTransactionTypes: {TransactionType.expense},
          ),
          Category(
            id: 'transfer',
            name: 'Transfer',
            allowedTransactionTypes: {TransactionType.transfer},
          ),
        ],
        currencies: const [usd, inr, eur],
        tags: const [Tag(id: 'tag', name: 'Tag')],
        transactions: const [],
        exchangeRates: const [],
        dailyAccountBalances: const [],
        dailyNetWorth: const [],
        dailyManualValuations: const [],
      );
      Transaction expense({
        String? accountId = 'checking',
        Money? amount,
        String? categoryId = 'expense',
        DateTime? date,
      }) => Transaction(
        id: 'expense',
        createdAt: DateTime.utc(2026, 1, 10),
        date: date ?? DateTime.utc(2026, 1, 10),
        type: TransactionType.expense,
        sourceAmount: amount ?? Money(minorUnits: 100, currencyId: 'USD'),
        sourceAccountId: accountId,
        destinationAmount: null,
        destinationAccountId: null,
        categoryId: categoryId,
        tagId: 'tag',
        description: 'Test expense',
      );

      expect(
        validateTransactionForWrite(expense(accountId: 'missing'), data),
        contains('Unknown source account: missing.'),
      );
      expect(
        validateTransactionForWrite(
          expense(amount: Money(minorUnits: 100, currencyId: 'EUR')),
          data,
        ),
        contains(
          'source amount currency EUR does not match account currency USD.',
        ),
      );
      expect(
        validateTransactionForWrite(
          expense(amount: Money(minorUnits: -100, currencyId: 'USD')),
          data,
        ),
        contains('source amount cannot be negative.'),
      );
      expect(
        validateTransactionForWrite(expense(categoryId: 'missing'), data),
        contains('Unknown category: missing.'),
      );

      final transfer = Transaction(
        id: 'transfer',
        createdAt: DateTime.utc(2026, 1, 10),
        date: DateTime.utc(2026, 1, 10),
        type: TransactionType.transfer,
        sourceAmount: Money(minorUnits: 100, currencyId: 'USD'),
        sourceAccountId: 'checking',
        destinationAmount: Money(minorUnits: 100, currencyId: 'INR'),
        destinationAccountId: 'missing',
        categoryId: 'transfer',
        tagId: 'tag',
        description: 'Test transfer',
      );
      expect(
        validateTransactionForWrite(transfer, data),
        contains('Unknown destination account: missing.'),
      );
    },
  );

  test(
    'transaction dates include the account closing day but not later dates',
    () {
      const usd = CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2);
      final checking = Account(
        id: 'checking',
        name: 'Checking',
        accountType: 'cash',
        currencyId: 'USD',
        openingBalance: Money.zero(usd),
        openingDate: DateTime.utc(2026, 1, 1),
        closingDate: DateTime.utc(2026, 1, 31),
        usesManualValuations: false,
      );
      final data = AppDataSnapshot(
        accounts: [checking],
        categories: const [
          Category(
            id: 'expense',
            name: 'Expense',
            allowedTransactionTypes: {TransactionType.expense},
          ),
        ],
        currencies: const [usd],
        tags: const [Tag(id: 'tag', name: 'Tag')],
        transactions: const [],
        exchangeRates: const [],
        dailyAccountBalances: const [],
        dailyNetWorth: const [],
        dailyManualValuations: const [],
      );
      final closingDay = build(
        type: TransactionType.expense,
        sourceAmount: amount,
        sourceAccountId: 'checking',
        categoryId: 'expense',
        tagId: 'tag',
        date: DateTime.utc(2026, 1, 31),
      );
      final afterClosing = build(
        type: TransactionType.expense,
        sourceAmount: amount,
        sourceAccountId: 'checking',
        categoryId: 'expense',
        tagId: 'tag',
        date: DateTime.utc(2026, 2, 1),
      );

      expect(validateTransactionForWrite(closingDay, data), isEmpty);
      expect(
        validateTransactionForWrite(afterClosing, data),
        contains('Transaction date is outside account checking lifetime.'),
      );
    },
  );

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

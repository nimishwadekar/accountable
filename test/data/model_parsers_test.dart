import 'package:accountable/data/csv/csv.dart';
import 'package:accountable/data/models/models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundles the CSV fixtures as Flutter assets', () async {
    final transactions = await rootBundle.loadString(
      'test_sheets/Transactions.csv',
    );

    expect(transactions, contains('transaction_id,date,description'));
  });

  const currenciesCsv = '''
currency_id,currency_symbol,decimal_places
USD,\$,2
INR,₹,2
''';

  const accountsCsv = '''
account_id,name,account_type,currency,opening_balance,current_balance,opening_date,closing_date
checking,Checking,Bank,USD,1000,1200,2026-10-01,
''';

  test('parses the current fixture tables together', () async {
    final currencies = ModelParsers.parseCurrencies(
      await rootBundle.loadString('test_sheets/Currencies.csv'),
    );
    final currencyById = {
      for (final currency in currencies) currency.id: currency,
    };
    final accounts = ModelParsers.parseAccounts(
      await rootBundle.loadString('test_sheets/Accounts.csv'),
      currencyById,
    );
    final accountById = {for (final account in accounts) account.id: account};
    final categories = ModelParsers.parseCategories(
      await rootBundle.loadString('test_sheets/Categories.csv'),
    );
    final tags = ModelParsers.parseTags(
      await rootBundle.loadString('test_sheets/Tags.csv'),
    );
    final transactions = ModelParsers.parseTransactions(
      await rootBundle.loadString('test_sheets/Transactions.csv'),
      accounts: accountById,
      currencies: currencyById,
    );
    final exchangeRates = ModelParsers.parseExchangeRates(
      await rootBundle.loadString('test_sheets/DailyExchangeRates.csv'),
    );
    final dailyBalances = ModelParsers.parseDailyAccountBalances(
      await rootBundle.loadString('test_sheets/DailyAccountBalances.csv'),
      accounts: accountById,
      currencies: currencyById,
    );
    final dailyNetWorth = ModelParsers.parseDailyNetWorth(
      await rootBundle.loadString('test_sheets/DailyNetWorth.csv'),
      currencyById,
    );

    expect(currencies, hasLength(2));
    expect(accounts, hasLength(3));
    expect(categories, hasLength(14));
    expect(tags, hasLength(1));
    expect(transactions, hasLength(8));
    expect(exchangeRates, hasLength(6));
    expect(exchangeRates.first.sourceRateDate, DateTime.utc(2026, 10, 10));
    expect(dailyBalances, hasLength(8));
    expect(dailyNetWorth, hasLength(3));
  });

  test('accepts legacy exchange-rate rows without source rate dates', () {
    final rates = ModelParsers.parseExchangeRates(
      'rate_id,rate_date,currency,rate_to_usd,retrieved_at\n'
      'r1,2026-10-10,USD,1,2026-10-10T00:00:00Z\n',
    );
    expect(rates.single.sourceRateDate, DateTime.utc(2026, 10, 10));
  });

  test('parses currencies and amounts using minor units', () {
    final currencies = ModelParsers.parseCurrencies(currenciesCsv);
    final usd = currencies.firstWhere((currency) => currency.id == 'USD');

    expect(currencies, hasLength(2));
    expect(usd.id, 'USD');
    expect(usd.decimalPlaces, 2);

    final amount = Money.fromMajorUnits(value: '12.34', currency: usd);
    expect(amount.minorUnits, 1234);
    expect(amount.toMajorUnitsString(usd), '12.34');
  });

  test('parses quoted category type lists', () {
    const source = '''
category_id,category_name,allowed_transaction_types
food,Food,"expense,reimbursement"
salary,Salary,income
''';

    final categories = ModelParsers.parseCategories(source);

    expect(categories, hasLength(2));
    expect(
      categories.first.allowedTransactionTypes,
      containsAll(<TransactionType>[
        TransactionType.expense,
        TransactionType.reimbursement,
      ]),
    );
    expect(
      categories.last.allowedTransactionTypes,
      contains(TransactionType.income),
    );
  });

  test('parses transactions and represents empty sides as null', () {
    final currencies = {
      for (final currency in ModelParsers.parseCurrencies(currenciesCsv))
        currency.id: currency,
    };
    final accounts = {
      for (final account in ModelParsers.parseAccounts(accountsCsv, currencies))
        account.id: account,
    };
    const source = '''
transaction_id,date,description,category,transaction_type,source_amount,source_account_id,dest_amount,dest_account_id,tag,created_at
expense-1,2026-10-10,Lunch,groceries,expense,40,checking,,,,2026-10-09 11:03:04
''';

    final transactions = ModelParsers.parseTransactions(
      source,
      accounts: accounts,
      currencies: currencies,
    );
    final transaction = transactions.single;

    expect(transaction.sourceAmount?.minorUnits, 4000);
    expect(transaction.destinationAmount, isNull);
    expect(transaction.sourceAccountId, 'checking');
    expect(transaction.destinationAccountId, isNull);
    expect(transaction.createdAt, DateTime.utc(2026, 10, 9, 11, 3, 4));
    expect(transaction.date, DateTime.utc(2026, 10, 10));
  });

  test('accepts ISO and legacy UTC timestamps', () {
    expect(
      parseUtcTimestamp('2026-10-12T02:18:28Z', fieldName: 'timestamp'),
      DateTime.utc(2026, 10, 12, 2, 18, 28),
    );
    expect(
      parseUtcTimestamp('2026-10-12 02:18:28', fieldName: 'timestamp'),
      DateTime.utc(2026, 10, 12, 2, 18, 28),
    );
  });

  test('rejects transaction sides that do not match their type', () {
    final currencies = {
      for (final currency in ModelParsers.parseCurrencies(currenciesCsv))
        currency.id: currency,
    };
    final accounts = {
      for (final account in ModelParsers.parseAccounts(accountsCsv, currencies))
        account.id: account,
    };
    const source = '''
transaction_id,date,description,category,transaction_type,source_amount,source_account_id,dest_amount,dest_account_id,tag,created_at
income-1,2026-10-10,Invalid income,,income,40,checking,,,,2026-10-09T11:03:04Z
''';

    expect(
      () => ModelParsers.parseTransactions(
        source,
        accounts: accounts,
        currencies: currencies,
      ),
      throwsFormatException,
    );
  });
}

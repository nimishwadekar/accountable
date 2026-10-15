import 'package:csv/csv.dart';
import 'package:decimal/decimal.dart';

import '../models/models.dart';
import '../repositories/data_validation_failure.dart';
import 'csv_table.dart';
import 'model_parse_result.dart';
import 'parse_helpers.dart';

class ModelParsers {
  const ModelParsers._();

  static ModelParseResult<T> _parseRows<T>(
    String source, {
    required String tableName,
    required T Function(String rowSource) parseRow,
  }) {
    final table = CsvTable.parse(source, tableName: tableName);
    final values = <T>[];
    final issues = <DataValidationIssue>[];
    for (var index = 0; index < table.rows.length; index++) {
      try {
        values.add(parseRow(csv.encode([
          table.headers,
          table.rows[index].values.toList(),
        ])));
      } catch (error) {
        issues.add(
          DataValidationIssue(
            table: tableName,
            row: table.rowNumbers[index],
            message: _friendlyParseMessage(error),
            technicalDetails: error.toString(),
          ),
        );
      }
    }
    return ModelParseResult(values: values, issues: issues);
  }

  static String _friendlyParseMessage(Object error) {
    final message = error.toString();
    final separator = message.indexOf(': ');
    return separator < 0 ? message : message.substring(separator + 2);
  }

  static ModelParseResult<CurrencyDefinition> parseCurrenciesWithIssues(
    String source,
  ) => _parseRows(
    source,
    tableName: 'Currencies',
    parseRow: (row) => parseCurrencies(row).single,
  );

  static ModelParseResult<Account> parseAccountsWithIssues(
    String source,
    Map<String, CurrencyDefinition> currencies,
  ) => _parseRows(
    source,
    tableName: 'Accounts',
    parseRow: (row) => parseAccounts(row, currencies).single,
  );

  static ModelParseResult<Category> parseCategoriesWithIssues(String source) =>
      _parseRows(
        source,
        tableName: 'Categories',
        parseRow: (row) => parseCategories(row).single,
      );

  static ModelParseResult<Tag> parseTagsWithIssues(String source) => _parseRows(
        source,
        tableName: 'Tags',
        parseRow: (row) => parseTags(row).single,
      );

  static ModelParseResult<Transaction> parseTransactionsWithIssues(
    String source, {
    required Map<String, Account> accounts,
    required Map<String, CurrencyDefinition> currencies,
  }) => _parseRows(
        source,
        tableName: 'Transactions',
        parseRow: (row) => parseTransactions(
          row,
          accounts: accounts,
          currencies: currencies,
        ).single,
      );

  static ModelParseResult<ExchangeRate> parseExchangeRatesWithIssues(
    String source,
  ) => _parseRows(
        source,
        tableName: 'DailyExchangeRates',
        parseRow: (row) => parseExchangeRates(row).single,
      );

  static ModelParseResult<DailyAccountBalance>
      parseDailyAccountBalancesWithIssues(
    String source, {
    required Map<String, Account> accounts,
    required Map<String, CurrencyDefinition> currencies,
  }) => _parseRows(
        source,
        tableName: 'DailyAccountBalances',
        parseRow: (row) => parseDailyAccountBalances(
          row,
          accounts: accounts,
          currencies: currencies,
        ).single,
      );

  static ModelParseResult<DailyNetWorth> parseDailyNetWorthWithIssues(
    String source,
    Map<String, CurrencyDefinition> currencies,
  ) => _parseRows(
        source,
        tableName: 'DailyNetWorth',
        parseRow: (row) => parseDailyNetWorth(row, currencies).single,
      );

  static ModelParseResult<DailyManualValuation>
      parseDailyManualValuationsWithIssues(
    String source, {
    required Map<String, Account> accounts,
    required Map<String, CurrencyDefinition> currencies,
  }) => _parseRows(
        source,
        tableName: 'DailyManualValuations',
        parseRow: (row) => parseDailyManualValuations(
          row,
          accounts: accounts,
          currencies: currencies,
        ).single,
      );

  static List<CurrencyDefinition> parseCurrencies(String source) {
    final table = CsvTable.parse(source, tableName: 'Currencies');
    return _uniqueById(
      table.rows.map(CurrencyDefinition.fromRow),
      (currency) => currency.id,
      table.tableName,
    );
  }

  static List<Account> parseAccounts(
    String source,
    Map<String, CurrencyDefinition> currencies,
  ) {
    final table = CsvTable.parse(source, tableName: 'Accounts');
    return _uniqueById(
      table.rows.map((row) {
        final currencyId = requiredValue(row, 'currency');
        final currency = _currency(currencies, currencyId);
        return Account(
          id: requiredValue(row, 'account_id'),
          name: requiredValue(row, 'name'),
          accountType: requiredValue(row, 'account_type'),
          currencyId: currencyId,
          openingBalance: Money.fromMajorUnits(
            value: requiredValue(row, 'opening_balance'),
            currency: currency,
          ),
          openingDate: parseDateOnly(
            requiredValue(row, 'opening_date'),
            fieldName: 'opening_date',
          ),
          closingDate: _optionalDate(row, 'closing_date'),
        );
      }),
      (account) => account.id,
      table.tableName,
    );
  }

  static List<Category> parseCategories(String source) {
    final table = CsvTable.parse(source, tableName: 'Categories');
    return _uniqueById(
      table.rows.map((row) {
        final rawTypes = optionalValue(row, 'allowed_transaction_types');
        final types = rawTypes == null
            ? <TransactionType>{}
            : rawTypes
                  .split(',')
                  .where((value) => value.trim().isNotEmpty)
                  .map(TransactionTypeWireValue.parse)
                  .toSet();
        return Category(
          id: requiredValue(row, 'category_id'),
          name: requiredValue(row, 'category_name'),
          allowedTransactionTypes: Set.unmodifiable(types),
        );
      }),
      (category) => category.id,
      table.tableName,
    );
  }

  static List<Tag> parseTags(String source) {
    final table = CsvTable.parse(source, tableName: 'Tags');
    return _uniqueById(
      table.rows.map(
        (row) => Tag(
          id: requiredValue(row, 'tag_id'),
          name: requiredValue(row, 'tag_name'),
        ),
      ),
      (tag) => tag.id,
      table.tableName,
    );
  }

  static List<Transaction> parseTransactions(
    String source, {
    required Map<String, Account> accounts,
    required Map<String, CurrencyDefinition> currencies,
  }) {
    final table = CsvTable.parse(source, tableName: 'Transactions');
    return _uniqueById(
      table.rows.map((row) {
        final sourceAccountId = optionalValue(row, 'source_account_id');
        final destinationAccountId = optionalValue(row, 'dest_account_id');
        final sourceAmount = _optionalAmount(
          row,
          amountField: 'source_amount',
          accountId: sourceAccountId,
          accounts: accounts,
          currencies: currencies,
        );
        final destinationAmount = _optionalAmount(
          row,
          amountField: 'dest_amount',
          accountId: destinationAccountId,
          accounts: accounts,
          currencies: currencies,
        );
        final transaction = Transaction(
          id: requiredValue(row, 'transaction_id'),
          createdAt: parseUtcTimestamp(
            requiredValue(row, 'created_at'),
            fieldName: 'created_at',
          ),
          date: parseDateOnly(requiredValue(row, 'date'), fieldName: 'date'),
          type: TransactionTypeWireValue.parse(
            requiredValue(row, 'transaction_type'),
          ),
          sourceAmount: sourceAmount,
          sourceAccountId: sourceAccountId,
          destinationAmount: destinationAmount,
          destinationAccountId: destinationAccountId,
          categoryId: optionalValue(row, 'category'),
          tagId: optionalValue(row, 'tag'),
          description: optionalValue(row, 'description') ?? '',
        );
        final validationErrors = transaction.validate();
        if (validationErrors.isNotEmpty) {
          throw FormatException(
            'Invalid transaction ${transaction.id}: '
            '${validationErrors.join(' ')}',
          );
        }
        return transaction;
      }),
      (transaction) => transaction.id,
      table.tableName,
    );
  }

  static List<ExchangeRate> parseExchangeRates(String source) {
    final table = CsvTable.parse(source, tableName: 'DailyExchangeRates');
    return _uniqueById(
      table.rows.map(
        (row) => ExchangeRate(
          id: requiredValue(row, 'rate_id'),
          date: parseDateOnly(
            requiredValue(row, 'rate_date'),
            fieldName: 'rate_date',
          ),
          currencyId: requiredValue(row, 'currency'),
          rateToUsd: Decimal.parse(requiredValue(row, 'rate_to_usd')),
          sourceRateDate: parseDateOnly(
            optionalValue(row, 'source_rate_date') ??
                requiredValue(row, 'rate_date'),
            fieldName: 'source_rate_date',
          ),
          retrievedAt: parseUtcTimestamp(
            requiredValue(row, 'retrieved_at'),
            fieldName: 'retrieved_at',
          ),
        ),
      ),
      (rate) => rate.id,
      table.tableName,
    );
  }

  static List<DailyAccountBalance> parseDailyAccountBalances(
    String source, {
    required Map<String, Account> accounts,
    required Map<String, CurrencyDefinition> currencies,
  }) {
    final table = CsvTable.parse(source, tableName: 'DailyAccountBalances');
    final usd = _currency(currencies, 'USD');
    return _uniqueById(
      table.rows.map((row) {
        final accountId = requiredValue(row, 'account_id');
        final account = accounts[accountId];
        if (account == null) {
          throw FormatException(
            'DailyAccountBalances references unknown account: $accountId.',
          );
        }
        final accountCurrency = _currency(currencies, account.currencyId);
        return DailyAccountBalance(
          id: requiredValue(row, 'balance_id'),
          date: parseDateOnly(
            requiredValue(row, 'balance_date'),
            fieldName: 'balance_date',
          ),
          accountId: accountId,
          balance: Money.fromMajorUnits(
            value: requiredValue(row, 'balance'),
            currency: accountCurrency,
          ),
          balanceUsd: Money.fromMajorUnits(
            value: requiredValue(row, 'balance_usd'),
            currency: usd,
          ),
          retrievedAt: parseUtcTimestamp(
            requiredValue(row, 'retrieved_at'),
            fieldName: 'retrieved_at',
          ),
        );
      }),
      (balance) => balance.id,
      table.tableName,
    );
  }

  static List<DailyManualValuation> parseDailyManualValuations(
    String source, {
    required Map<String, Account> accounts,
    required Map<String, CurrencyDefinition> currencies,
  }) {
    final table = CsvTable.parse(source, tableName: 'DailyManualValuations');
    return _uniqueById(
      table.rows.map((row) {
        final accountId = requiredValue(row, 'account_id');
        final account = accounts[accountId];
        if (account == null) {
          throw FormatException(
            'DailyManualValuations references unknown account: $accountId.',
          );
        }
        if (!account.isValuationAccount) {
          throw FormatException(
            'DailyManualValuations references non-valuation account: $accountId.',
          );
        }
        return DailyManualValuation(
          id: requiredValue(row, 'valuation_id'),
          date: parseDateOnly(requiredValue(row, 'date'), fieldName: 'date'),
          accountId: accountId,
          value: Money.fromMajorUnits(
            value: requiredValue(row, 'value'),
            currency: _currency(currencies, account.currencyId),
          ),
        );
      }),
      (valuation) => valuation.id,
      table.tableName,
    );
  }

  static List<DailyNetWorth> parseDailyNetWorth(
    String source,
    Map<String, CurrencyDefinition> currencies,
  ) {
    final table = CsvTable.parse(source, tableName: 'DailyNetWorth');
    final usd = _currency(currencies, 'USD');
    return _uniqueById(
      table.rows.map(
        (row) => DailyNetWorth(
          id: requiredValue(row, 'net_worth_id'),
          date: parseDateOnly(
            requiredValue(row, 'net_worth_date'),
            fieldName: 'net_worth_date',
          ),
          amount: Money.fromMajorUnits(
            value: requiredValue(row, 'amount'),
            currency: usd,
          ),
          retrievedAt: parseUtcTimestamp(
            requiredValue(row, 'retrieved_at'),
            fieldName: 'retrieved_at',
          ),
        ),
      ),
      (netWorth) => netWorth.id,
      table.tableName,
    );
  }

  static Money? _optionalAmount(
    Map<String, String> row, {
    required String amountField,
    required String? accountId,
    required Map<String, Account> accounts,
    required Map<String, CurrencyDefinition> currencies,
  }) {
    final rawAmount = optionalValue(row, amountField);
    if (rawAmount == null && accountId == null) {
      return null;
    }
    if (rawAmount == null || accountId == null) {
      throw FormatException(
        '$amountField and its account must either both be present or both be empty.',
      );
    }

    final account = accounts[accountId];
    if (account == null) {
      throw FormatException(
        'Transaction references unknown account: $accountId.',
      );
    }
    return Money.fromMajorUnits(
      value: rawAmount,
      currency: _currency(currencies, account.currencyId),
    );
  }

  static DateTime? _optionalDate(Map<String, String> row, String fieldName) {
    final value = optionalValue(row, fieldName);
    return value == null ? null : parseDateOnly(value, fieldName: fieldName);
  }

  static CurrencyDefinition _currency(
    Map<String, CurrencyDefinition> currencies,
    String id,
  ) {
    final currency = currencies[id];
    if (currency == null) {
      throw FormatException('Unknown currency: $id.');
    }
    return currency;
  }

  static List<T> _uniqueById<T>(
    Iterable<T> values,
    String Function(T) idOf,
    String tableName,
  ) {
    final result = <T>[];
    final ids = <String>{};
    for (final value in values) {
      final id = idOf(value);
      if (!ids.add(id)) {
        throw FormatException('Duplicate ID in $tableName: $id.');
      }
      result.add(value);
    }
    return List.unmodifiable(result);
  }
}

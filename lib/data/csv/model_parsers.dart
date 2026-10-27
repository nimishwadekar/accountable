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
    required Iterable<String> Function(T value) keysOf,
  }) {
    final table = CsvTable.parse(source, tableName: tableName);
    final values = <T>[];
    final issues = <DataValidationIssue>[];
    final firstRowByKey = <String, int>{};
    for (var index = 0; index < table.rows.length; index++) {
      try {
        final value = parseRow(
          csv.encode([table.headers, table.rows[index].values.toList()]),
        );
        for (final key in keysOf(value)) {
          final firstRow = firstRowByKey[key];
          if (firstRow != null) {
            issues.add(
              DataValidationIssue(
                table: tableName,
                row: table.rowNumbers[index],
                field: 'key',
                message: 'Duplicate key in $tableName: $key.',
                technicalDetails:
                    'Duplicate key "$key" on rows $firstRow and ${table.rowNumbers[index]}.',
              ),
            );
          } else {
            firstRowByKey[key] = table.rowNumbers[index];
          }
        }
        values.add(value);
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
    keysOf: (value) => ['id:${value.id}'],
  );

  static ModelParseResult<Account> parseAccountsWithIssues(
    String source,
    Map<String, CurrencyDefinition> currencies,
  ) => _parseRows(
    source,
    tableName: 'Accounts',
    parseRow: (row) => parseAccounts(row, currencies).single,
    keysOf: (value) => ['id:${value.id}'],
  );

  static ModelParseResult<Category> parseCategoriesWithIssues(String source) =>
      _parseRows(
        source,
        tableName: 'Categories',
        parseRow: (row) => parseCategories(row).single,
        keysOf: (value) => ['id:${value.id}'],
      );

  static ModelParseResult<Tag> parseTagsWithIssues(String source) => _parseRows(
    source,
    tableName: 'Tags',
    parseRow: (row) => parseTags(row).single,
    keysOf: (value) => ['id:${value.id}'],
  );

  static ModelParseResult<DisplayPreference> parseDisplayPreferencesWithIssues(
    String source,
  ) => _parseRows(
    source,
    tableName: 'DisplayPreferences',
    parseRow: (row) => parseDisplayPreferences(row).single,
    keysOf: (value) => ['${value.entityType}:${value.entityId}'],
  );

  static ModelParseResult<Transaction> parseTransactionsWithIssues(
    String source, {
    required Map<String, Account> accounts,
    required Map<String, CurrencyDefinition> currencies,
    Map<String, Category>? categories,
    Map<String, Tag>? tags,
  }) => _parseRows(
    source,
    tableName: 'Transactions',
    parseRow: (row) => parseTransactions(
      row,
      accounts: accounts,
      currencies: currencies,
      categories: categories,
      tags: tags,
    ).single,
    keysOf: (value) => ['id:${value.id}'],
  );

  static ModelParseResult<ExchangeRate> parseExchangeRatesWithIssues(
    String source,
  ) => _parseRows(
    source,
    tableName: 'DailyExchangeRates',
    parseRow: (row) => parseExchangeRates(row).single,
    keysOf: (value) => ['id:${value.id}'],
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
    keysOf: (value) => ['id:${value.id}'],
  );

  static ModelParseResult<DailyNetWorth> parseDailyNetWorthWithIssues(
    String source,
    Map<String, CurrencyDefinition> currencies,
  ) => _parseRows(
    source,
    tableName: 'DailyNetWorth',
    parseRow: (row) => parseDailyNetWorth(row, currencies).single,
    keysOf: (value) => ['id:${value.id}'],
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
    keysOf: (value) => [
      'id:${value.id}',
      'account-date:${value.accountId}:${_dateString(value.date)}',
    ],
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
        final accountType = requiredValue(row, 'account_type');
        final accountTypeKind = AccountType.parse(accountType);
        final usesManualValuations = _parseBoolean(
          requiredValue(row, 'uses_manual_valuations'),
          fieldName: 'uses_manual_valuations',
        );
        if (usesManualValuations &&
            accountTypeKind != AccountType.asset &&
            accountTypeKind != AccountType.liability) {
          throw FormatException(
            'Only asset and liability accounts can use manual valuations.',
          );
        }
        final openingBalance = Money.fromMajorUnits(
          value: requiredValue(row, 'opening_balance'),
          currency: currency,
        );
        final openingDate = parseDateOnly(
          requiredValue(row, 'opening_date'),
          fieldName: 'opening_date',
        );
        final closingDate = _optionalDate(row, 'closing_date');
        if (closingDate != null && closingDate.isBefore(openingDate)) {
          throw FormatException('closing_date cannot be before opening_date.');
        }
        if (usesManualValuations && openingBalance.minorUnits != 0) {
          throw FormatException(
            'Manual valuation accounts must have opening_balance 0.',
          );
        }
        return Account(
          id: requiredValue(row, 'account_id'),
          name: requiredValue(row, 'name'),
          accountType: accountType,
          currencyId: currencyId,
          openingBalance: openingBalance,
          openingDate: openingDate,
          closingDate: closingDate,
          usesManualValuations: usesManualValuations,
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

  static List<DisplayPreference> parseDisplayPreferences(String source) {
    final table = CsvTable.parse(source, tableName: 'DisplayPreferences');
    return table.rows.map((row) {
      final showInApp = _parseBoolean(
        requiredValue(row, 'show_in_app'),
        fieldName: 'show_in_app',
      );
      final showInEntryForms = _parseBoolean(
        requiredValue(row, 'show_in_entry_forms'),
        fieldName: 'show_in_entry_forms',
      );
      if (!showInApp && showInEntryForms) {
        throw FormatException(
          'show_in_entry_forms cannot be TRUE when show_in_app is FALSE.',
        );
      }
      final entityType = requiredValue(row, 'entity_type');
      if (!const {'account', 'category', 'tag'}.contains(entityType)) {
        throw FormatException('Unsupported entity_type: $entityType.');
      }
      return DisplayPreference(
        entityType: entityType,
        entityId: requiredValue(row, 'entity_id'),
        displayOrder: int.parse(requiredValue(row, 'display_order')),
        showInApp: showInApp,
        showInEntryForms: showInEntryForms,
      );
    }).toList();
  }

  static List<IncomeAllocation> parseIncomeAllocations(
    String source, {
    required Map<String, Account> accounts,
    required Map<String, CurrencyDefinition> currencies,
    required Map<String, Category> categories,
  }) {
    final table = CsvTable.parse(source, tableName: 'IncomeAllocations');
    final allocations = table.rows.map((row) {
      final incomeAccountId = requiredValue(row, 'income_account_id');
      final transferCategoryId = requiredValue(row, 'transfer_category_id');
      final incomeAccount = accounts[incomeAccountId];
      if (incomeAccount == null) {
        throw FormatException(
          'Income allocation references an unknown income account.',
        );
      }
      final incomeCategory =
          categories[requiredValue(row, 'income_category_id')];
      if (incomeCategory == null ||
          !incomeCategory.allowedTransactionTypes.contains(
            TransactionType.income,
          )) {
        throw FormatException(
          'Income allocation income category must allow income.',
        );
      }
      final transferCategory = categories[transferCategoryId];
      if (transferCategory == null ||
          !transferCategory.allowedTransactionTypes.contains(
            TransactionType.transfer,
          )) {
        throw FormatException(
          'Income allocation transfer category must allow transfers.',
        );
      }
      return IncomeAllocation(
        id: requiredValue(row, 'allocation_id'),
        name: requiredValue(row, 'name'),
        incomeCategoryId: requiredValue(row, 'income_category_id'),
        incomeAccountId: incomeAccountId,
        transferCategoryId: transferCategoryId,
        expectedAmountPerIncome: Money.fromMajorUnits(
          value: requiredValue(row, 'expected_amount_per_income'),
          currency: _currency(currencies, incomeAccount.currencyId),
        ),
        startDate: parseDateOnly(
          requiredValue(row, 'start_date'),
          fieldName: 'start_date',
        ),
        endDate: _optionalDate(row, 'end_date'),
        createdAt: parseUtcTimestamp(
          requiredValue(row, 'created_at'),
          fieldName: 'created_at',
        ),
        updatedAt: parseUtcTimestamp(
          requiredValue(row, 'updated_at'),
          fieldName: 'updated_at',
        ),
      );
    }).toList();
    final keys = <String>{};
    for (final allocation in allocations) {
      final key =
          '${allocation.incomeCategoryId}:${allocation.incomeAccountId}:${allocation.transferCategoryId}';
      if (!keys.add(key)) {
        throw FormatException(
          'Duplicate income allocation transfer category for $key.',
        );
      }
    }
    return _uniqueById(
      allocations,
      (allocation) => allocation.id,
      table.tableName,
    );
  }

  static List<TransactionTemplate> parseTransactionTemplates(
    String source, {
    required Map<String, Account> accounts,
    required Map<String, CurrencyDefinition> currencies,
  }) {
    final table = CsvTable.parse(source, tableName: 'TransactionTemplates');
    return _uniqueById(
      table.rows.map((row) {
        Money? amount(String field, String? accountId) {
          final raw = optionalValue(row, field);
          if (raw == null || accountId == null) return null;
          final account = accounts[accountId];
          if (account == null) {
            throw FormatException(
              'Template references unknown account: $accountId.',
            );
          }
          return Money.fromMajorUnits(
            value: raw,
            currency: _currency(currencies, account.currencyId),
          );
        }

        final sourceAccountId = optionalValue(row, 'source_account_id');
        final destinationAccountId = optionalValue(row, 'dest_account_id');
        final createdAt = parseUtcTimestamp(
          requiredValue(row, 'created_at'),
          fieldName: 'created_at',
        );
        return TransactionTemplate(
          id: requiredValue(row, 'template_id'),
          name: requiredValue(row, 'name'),
          type: TransactionTypeWireValue.parse(
            requiredValue(row, 'transaction_type'),
          ),
          date: _optionalDate(row, 'date'),
          description: optionalValue(row, 'description'),
          categoryId: optionalValue(row, 'category'),
          tagId: optionalValue(row, 'tag'),
          sourceAccountId: sourceAccountId,
          sourceAmount: amount('source_amount', sourceAccountId),
          destinationAccountId: destinationAccountId,
          destinationAmount: amount('dest_amount', destinationAccountId),
          createdAt: createdAt,
          updatedAt: parseUtcTimestamp(
            requiredValue(row, 'updated_at'),
            fieldName: 'updated_at',
          ),
        );
      }),
      (template) => template.id,
      table.tableName,
    );
  }

  static List<Transaction> parseTransactions(
    String source, {
    required Map<String, Account> accounts,
    required Map<String, CurrencyDefinition> currencies,
    Map<String, Category>? categories,
    Map<String, Tag>? tags,
    String tableName = 'Transactions',
  }) {
    final table = CsvTable.parse(source, tableName: tableName);
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
        if (categories != null && transaction.categoryId != null) {
          final category = categories[transaction.categoryId];
          if (category == null) {
            validationErrors.add(
              'Unknown category: ${transaction.categoryId}.',
            );
          } else if (!category.allowedTransactionTypes.contains(
            transaction.type,
          )) {
            validationErrors.add(
              'Category ${transaction.categoryId} is not allowed for '
              '${transaction.type.wireValue} transactions.',
            );
          }
        }
        if (tags != null &&
            transaction.tagId != null &&
            !tags.containsKey(transaction.tagId)) {
          validationErrors.add('Unknown tag: ${transaction.tagId}.');
        }
        for (final accountId in [
          transaction.sourceAccountId,
          transaction.destinationAccountId,
        ]) {
          if (accountId == null) continue;
          final account = accounts[accountId];
          if (account == null) continue;
          if (!_accountIsActiveOn(account, transaction.date)) {
            validationErrors.add(
              'Transaction date is outside account $accountId lifetime.',
            );
          }
        }
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
    final valuations = table.rows.map((row) {
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
    }).toList();
    final accountDates = <String>{};
    for (final valuation in valuations) {
      final key = '${valuation.accountId}:${_dateString(valuation.date)}';
      if (!accountDates.add(key)) {
        throw FormatException(
          'Duplicate valuation for ${valuation.accountId} on '
          '${_dateString(valuation.date)}.',
        );
      }
    }
    return _uniqueById(
      valuations,
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

  static String _dateString(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static bool _accountIsActiveOn(Account account, DateTime date) {
    final transactionDate = DateTime.utc(date.year, date.month, date.day);
    final openingDate = DateTime.utc(
      account.openingDate.year,
      account.openingDate.month,
      account.openingDate.day,
    );
    final closingDate = account.closingDate == null
        ? null
        : DateTime.utc(
            account.closingDate!.year,
            account.closingDate!.month,
            account.closingDate!.day,
          );
    return !transactionDate.isBefore(openingDate) &&
        (closingDate == null || !transactionDate.isAfter(closingDate));
  }

  static bool _parseBoolean(String value, {required String fieldName}) {
    switch (value.trim().toUpperCase()) {
      case 'TRUE':
        return true;
      case 'FALSE':
        return false;
      default:
        throw FormatException('Invalid boolean in $fieldName: $value.');
    }
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

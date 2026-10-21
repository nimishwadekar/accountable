import 'package:csv/csv.dart';

import '../app_data_snapshot.dart';
import '../csv/csv.dart';
import '../models/models.dart';
import '../sources/google_sheets_api.dart';
import '../table_schema.dart';
import 'data_load_exception.dart';
import 'display_preference_manager.dart';
import 'data_validation_failure.dart';
import 'transaction_write_validator.dart';
import 'manual_valuation_write_validator.dart';
import 'table_dependencies.dart';
import 'repositories.dart';

abstract final class GoogleSheetsRanges {
  static final accounts = RuntimeTableSchemas.accounts.range;
  static final categories = RuntimeTableSchemas.categories.range;
  static final currencies = RuntimeTableSchemas.currencies.range;
  static final dailyAccountBalances =
      RuntimeTableSchemas.dailyAccountBalances.range;
  static final dailyExchangeRates =
      RuntimeTableSchemas.dailyExchangeRates.range;
  static final dailyNetWorth = RuntimeTableSchemas.dailyNetWorth.range;
  static final dailyManualValuations =
      RuntimeTableSchemas.dailyManualValuations.range;
  static final displayPreferences =
      RuntimeTableSchemas.displayPreferences.range;
  static final tags = RuntimeTableSchemas.tags.range;
  static final transactions = RuntimeTableSchemas.transactions.range;
  static final transactionTemplates =
      RuntimeTableSchemas.transactionTemplates.range;
  static final incomeAllocations = RuntimeTableSchemas.incomeAllocations.range;
}

class GoogleSheetsAppDataRepository implements AppDataRepository {
  GoogleSheetsAppDataRepository(this.api);

  final SheetsTableClient api;
  AppDataSnapshot? _cachedSnapshot;

  @override
  Future<AppDataSnapshot> load() async {
    return _cachedSnapshot ??= await _loadFreshSnapshot();
  }

  @override
  Future<AppDataSnapshot> reload() async {
    final snapshot = await _loadFreshSnapshot();
    _cachedSnapshot = snapshot;
    return snapshot;
  }

  @override
  Future<AppDataSnapshot> addManualValuation(DailyManualValuation valuation) =>
      addManualValuations([valuation]);

  @override
  Future<AppDataSnapshot> addManualValuations(
    List<DailyManualValuation> valuations,
  ) async {
    final current = await load();
    final validationErrors = validateManualValuationsForWrite(
      valuations,
      current,
    );
    if (validationErrors.isNotEmpty) {
      throw StateError(validationErrors.join(' '));
    }
    await api.appendRows(GoogleSheetsRanges.dailyManualValuations, [
      for (final valuation in valuations)
        [
          valuation.id,
          _dateString(valuation.date),
          valuation.accountId,
          valuation.value.toMajorUnitsString(
            current.currenciesById[valuation.value.currencyId]!,
          ),
        ],
    ]);
    return reload();
  }

  @override
  Future<AppDataSnapshot> saveDisplayPreferences(
    List<DisplayPreference> preferences,
  ) async {
    final current = await load();
    final normalized = synchronizeDisplayPreferences(
      existing: preferences,
      accountIds: current.accounts.map((item) => item.id).toSet(),
      categoryIds: current.categories.map((item) => item.id).toSet(),
      tagIds: current.tags.map((item) => item.id).toSet(),
    );
    if (normalized.missing.isNotEmpty) {
      throw StateError('Display preferences must include every entity.');
    }
    await api.replaceRange(GoogleSheetsRanges.displayPreferences, [
      RuntimeTableSchemas.displayPreferences.headers,
      for (final preference in normalized.preferences)
        _displayPreferenceRow(preference),
    ]);
    return reload();
  }

  @override
  Future<AppDataSnapshot> addIncomeAllocation(
    IncomeAllocation allocation,
  ) async {
    final current = await load();
    final incomeAccount = current.accountsById[allocation.incomeAccountId];
    if (incomeAccount == null || incomeAccount.currencyId != 'USD') {
      throw StateError('Income allocation income account must use USD.');
    }
    await api.appendRow(
      GoogleSheetsRanges.incomeAllocations,
      _incomeAllocationRow(
        allocation,
        current.accountsById,
        current.currenciesById,
      ),
    );
    return reload();
  }

  @override
  Future<AppDataSnapshot> addTransactionTemplate(
    TransactionTemplate template,
  ) async {
    final current = await load();
    _validateTemplateName(template, current.transactionTemplates);
    await api.appendRow(
      GoogleSheetsRanges.transactionTemplates,
      _transactionTemplateRow(
        template,
        accounts: (await load()).accountsById,
        currencies: (await load()).currenciesById,
      ),
    );
    return reload();
  }

  @override
  Future<AppDataSnapshot> updateTransactionTemplate(
    TransactionTemplate template,
  ) async {
    final current = await load();
    if (!current.transactionTemplates.any((item) => item.id == template.id)) {
      throw StateError('Template ${template.id} does not exist.');
    }
    _validateTemplateName(template, current.transactionTemplates);
    final templates = [
      for (final item in current.transactionTemplates)
        item.id == template.id ? template : item,
    ];
    await api.replaceRange(GoogleSheetsRanges.transactionTemplates, [
      RuntimeTableSchemas.transactionTemplates.headers,
      for (final item in templates)
        _transactionTemplateRow(
          item,
          accounts: current.accountsById,
          currencies: current.currenciesById,
        ),
    ]);
    return reload();
  }

  @override
  Future<AppDataSnapshot> deleteTransactionTemplate(String templateId) async {
    final current = await load();
    if (!current.transactionTemplates.any((item) => item.id == templateId)) {
      throw StateError('Template $templateId does not exist.');
    }
    final templates = current.transactionTemplates
        .where((item) => item.id != templateId)
        .toList();
    await api.replaceRange(GoogleSheetsRanges.transactionTemplates, [
      RuntimeTableSchemas.transactionTemplates.headers,
      for (final item in templates)
        _transactionTemplateRow(
          item,
          accounts: current.accountsById,
          currencies: current.currenciesById,
        ),
    ]);
    return reload();
  }

  @override
  Future<AppDataSnapshot> addTransaction(Transaction transaction) =>
      addTransactions([transaction]);

  @override
  Future<AppDataSnapshot> addTransactions(
    List<Transaction> transactions,
  ) async {
    final current = await load();
    final validationErrors = validateTransactionsForWrite(
      transactions,
      current,
    );
    if (validationErrors.isNotEmpty) {
      throw StateError(validationErrors.join(' '));
    }
    final accountCurrencies = {
      for (final account in current.accounts) account.id: account.currencyId,
    };
    await api.appendRows(GoogleSheetsRanges.transactions, [
      for (final transaction in transactions)
        RuntimeTableSchemas.transactions.headers
            .map(
              (header) =>
                  transactionToRow(
                    transaction,
                    current.currenciesById,
                    accountCurrencies,
                  )[header] ??
                  '',
            )
            .toList(),
    ]);
    return reload();
  }

  static void _validateTemplateName(
    TransactionTemplate template,
    Iterable<TransactionTemplate> existing,
  ) {
    final normalizedName = template.name.trim().toLowerCase();
    if (normalizedName.isEmpty) {
      throw StateError('Template name cannot be empty.');
    }
    if (existing.any(
      (item) =>
          item.id != template.id &&
          item.name.trim().toLowerCase() == normalizedName,
    )) {
      throw StateError('A template with this name already exists.');
    }
  }

  Future<AppDataSnapshot> _loadFreshSnapshot() async {
    try {
      final tables = await _readRuntimeTables();
      final issues = <DataValidationIssue>[];
      final tableHasErrors = <String, bool>{};
      bool dependenciesAreValid(String table) {
        final dependencies = tableDependencies[table] ?? const <String>[];
        return dependencies.every(
          (dependency) => tableHasErrors[dependency] == false,
        );
      }

      void recordIssues(String table, List<DataValidationIssue> tableIssues) {
        tableHasErrors[table] = tableIssues.isNotEmpty;
        issues.addAll(tableIssues);
      }

      List<CurrencyDefinition> currencies = const [];
      List<Account> accounts = const [];
      List<Category> categories = const [];
      List<Tag> tags = const [];
      List<Transaction> transactions = const [];
      List<ExchangeRate> exchangeRates = const [];
      List<DailyAccountBalance> dailyAccountBalances = const [];
      List<DailyNetWorth> dailyNetWorth = const [];
      List<DailyManualValuation> dailyManualValuations = const [];
      List<DisplayPreference> displayPreferences = const [];
      List<TransactionTemplate> transactionTemplates = const [];
      List<IncomeAllocation> incomeAllocations = const [];

      try {
        final result = ModelParsers.parseCurrenciesWithIssues(
          _encode(tables[GoogleSheetsRanges.currencies]!),
        );
        currencies = result.values;
        recordIssues('Currencies', result.issues);
      } catch (error) {
        final issue = issueFromError('Currencies', error);
        recordIssues('Currencies', [issue]);
      }
      final currencyById = {
        for (final currency in currencies) currency.id: currency,
      };
      if (dependenciesAreValid('Accounts')) {
        try {
          final result = ModelParsers.parseAccountsWithIssues(
            _encode(tables[GoogleSheetsRanges.accounts]!),
            currencyById,
          );
          accounts = result.values;
          recordIssues('Accounts', result.issues);
        } catch (error) {
          recordIssues('Accounts', [issueFromError('Accounts', error)]);
        }
      }
      final accountById = {for (final account in accounts) account.id: account};
      try {
        final result = ModelParsers.parseCategoriesWithIssues(
          _encode(tables[GoogleSheetsRanges.categories]!),
        );
        categories = result.values;
        recordIssues('Categories', result.issues);
      } catch (error) {
        recordIssues('Categories', [issueFromError('Categories', error)]);
      }
      try {
        final result = ModelParsers.parseTagsWithIssues(
          _encode(tables[GoogleSheetsRanges.tags]!),
        );
        tags = result.values;
        recordIssues('Tags', result.issues);
      } catch (error) {
        recordIssues('Tags', [issueFromError('Tags', error)]);
      }
      if (dependenciesAreValid('DisplayPreferences')) {
        try {
          final result = ModelParsers.parseDisplayPreferencesWithIssues(
            _encode(tables[GoogleSheetsRanges.displayPreferences]!),
          );
          if (result.issues.isNotEmpty) {
            recordIssues('DisplayPreferences', result.issues);
          } else {
            final synchronized = synchronizeDisplayPreferences(
              existing: result.values,
              accountIds: accountById.keys.toSet(),
              categoryIds: categories.map((item) => item.id).toSet(),
              tagIds: tags.map((item) => item.id).toSet(),
            );
            displayPreferences = synchronized.preferences;
            for (final preference in synchronized.missing) {
              await api.appendRow(
                GoogleSheetsRanges.displayPreferences,
                _displayPreferenceRow(preference),
              );
            }
            recordIssues('DisplayPreferences', const []);
          }
        } catch (error) {
          recordIssues('DisplayPreferences', [
            issueFromError('DisplayPreferences', error),
          ]);
        }
      }
      if (dependenciesAreValid('IncomeAllocations')) {
        try {
          incomeAllocations = ModelParsers.parseIncomeAllocations(
            _encode(tables[GoogleSheetsRanges.incomeAllocations]!),
            accounts: accountById,
            currencies: currencyById,
          );
          recordIssues('IncomeAllocations', const []);
        } catch (error) {
          recordIssues('IncomeAllocations', [
            issueFromError('IncomeAllocations', error),
          ]);
        }
      }
      if (dependenciesAreValid('TransactionTemplates')) {
        try {
          transactionTemplates = ModelParsers.parseTransactionTemplates(
            _encode(tables[GoogleSheetsRanges.transactionTemplates]!),
            accounts: accountById,
            currencies: currencyById,
          );
          recordIssues('TransactionTemplates', const []);
        } catch (error) {
          recordIssues('TransactionTemplates', [
            issueFromError('TransactionTemplates', error),
          ]);
        }
      }
      if (dependenciesAreValid('Transactions')) {
        try {
          final result = ModelParsers.parseTransactionsWithIssues(
            _encode(tables[GoogleSheetsRanges.transactions]!),
            accounts: accountById,
            currencies: currencyById,
            categories: {
              for (final category in categories) category.id: category,
            },
            tags: {for (final tag in tags) tag.id: tag},
          );
          transactions = result.values;
          recordIssues('Transactions', result.issues);
        } catch (error) {
          recordIssues('Transactions', [issueFromError('Transactions', error)]);
        }
      }
      try {
        final result = ModelParsers.parseExchangeRatesWithIssues(
          _encode(tables[GoogleSheetsRanges.dailyExchangeRates]!),
        );
        exchangeRates = result.values;
        recordIssues('DailyExchangeRates', result.issues);
      } catch (error) {
        recordIssues('DailyExchangeRates', [
          issueFromError('DailyExchangeRates', error),
        ]);
      }
      if (dependenciesAreValid('DailyAccountBalances')) {
        try {
          final result = ModelParsers.parseDailyAccountBalancesWithIssues(
            _encode(tables[GoogleSheetsRanges.dailyAccountBalances]!),
            accounts: accountById,
            currencies: currencyById,
          );
          dailyAccountBalances = result.values;
          recordIssues('DailyAccountBalances', result.issues);
        } catch (error) {
          recordIssues('DailyAccountBalances', [
            issueFromError('DailyAccountBalances', error),
          ]);
        }
      }
      if (dependenciesAreValid('DailyNetWorth')) {
        try {
          final result = ModelParsers.parseDailyNetWorthWithIssues(
            _encode(tables[GoogleSheetsRanges.dailyNetWorth]!),
            currencyById,
          );
          dailyNetWorth = result.values;
          recordIssues('DailyNetWorth', result.issues);
        } catch (error) {
          recordIssues('DailyNetWorth', [
            issueFromError('DailyNetWorth', error),
          ]);
        }
      }
      if (dependenciesAreValid('DailyManualValuations')) {
        try {
          final result = ModelParsers.parseDailyManualValuationsWithIssues(
            _encode(tables[GoogleSheetsRanges.dailyManualValuations]!),
            accounts: accountById,
            currencies: currencyById,
          );
          dailyManualValuations = result.values;
          recordIssues('DailyManualValuations', result.issues);
        } catch (error) {
          recordIssues('DailyManualValuations', [
            issueFromError('DailyManualValuations', error),
          ]);
        }
      }
      if (issues.isNotEmpty) throw DataValidationFailure(issues);

      return AppDataSnapshot(
        accounts: accounts,
        categories: categories,
        currencies: currencies,
        tags: tags,
        transactions: transactions,
        exchangeRates: exchangeRates,
        dailyAccountBalances: dailyAccountBalances,
        dailyNetWorth: dailyNetWorth,
        dailyManualValuations: dailyManualValuations,
        displayPreferences: displayPreferences,
        transactionTemplates: transactionTemplates,
        incomeAllocations: incomeAllocations,
      );
    } on DataValidationFailure {
      rethrow;
    } catch (error) {
      throw DataLoadException(
        tableName: 'Google Sheets',
        message: error.toString(),
        cause: error,
      );
    }
  }

  Future<Map<String, List<List<String>>>> _readRuntimeTables() async {
    final ranges = [
      GoogleSheetsRanges.accounts,
      GoogleSheetsRanges.categories,
      GoogleSheetsRanges.currencies,
      GoogleSheetsRanges.dailyAccountBalances,
      GoogleSheetsRanges.dailyExchangeRates,
      GoogleSheetsRanges.dailyNetWorth,
      GoogleSheetsRanges.dailyManualValuations,
      GoogleSheetsRanges.displayPreferences,
      GoogleSheetsRanges.transactionTemplates,
      GoogleSheetsRanges.incomeAllocations,
      GoogleSheetsRanges.tags,
      GoogleSheetsRanges.transactions,
    ];
    final response = await api.batchReadRanges(ranges);
    return {
      for (final range in ranges)
        range: _padRows(
          response[range] ?? const [],
          RuntimeTableSchemas.byRange(range).columnCount,
        ),
    };
  }

  static List<List<String>> _padRows(
    List<List<String>> rows,
    int expectedColumns,
  ) {
    return [
      for (final row in rows)
        [
          ...row,
          for (var index = row.length; index < expectedColumns; index++) '',
        ],
    ];
  }

  static String _encode(List<List<String>> rows) => csv.encode(rows);

  static List<String> _incomeAllocationRow(
    IncomeAllocation allocation,
    Map<String, Account> accounts,
    Map<String, CurrencyDefinition> currencies,
  ) => [
    allocation.id,
    allocation.name,
    allocation.incomeCategoryId,
    allocation.incomeAccountId,
    allocation.sourceAccountId,
    allocation.destinationAccountId,
    allocation.expectedAmountPerIncome.toMajorUnitsString(
      currencies[accounts[allocation.incomeAccountId]!.currencyId]!,
    ),
    allocation.descriptionKeyword ?? '',
    _dateString(allocation.startDate),
    allocation.endDate == null ? '' : _dateString(allocation.endDate!),
    allocation.createdAt.toUtc().toIso8601String(),
    allocation.updatedAt.toUtc().toIso8601String(),
  ];

  static List<String> _transactionTemplateRow(
    TransactionTemplate template, {
    required Map<String, Account> accounts,
    required Map<String, CurrencyDefinition> currencies,
  }) {
    String amountFor(Money? amount, String? accountId) {
      if (amount == null || accountId == null) return '';
      final account = accounts[accountId];
      if (account == null) {
        throw StateError('Unknown template account: $accountId.');
      }
      return amount.toMajorUnitsString(currencies[account.currencyId]!);
    }

    return [
      template.id,
      template.name,
      template.type.wireValue,
      template.date == null ? '' : _dateString(template.date!),
      template.description ?? '',
      template.categoryId ?? '',
      template.tagId ?? '',
      template.sourceAccountId ?? '',
      amountFor(template.sourceAmount, template.sourceAccountId),
      template.destinationAccountId ?? '',
      amountFor(template.destinationAmount, template.destinationAccountId),
      template.createdAt.toUtc().toIso8601String(),
      template.updatedAt.toUtc().toIso8601String(),
    ];
  }

  static List<String> _displayPreferenceRow(DisplayPreference preference) => [
    preference.entityType,
    preference.entityId,
    preference.displayOrder.toString(),
    preference.showInApp.toString().toUpperCase(),
    preference.showInEntryForms.toString().toUpperCase(),
  ];

  static String _dateString(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

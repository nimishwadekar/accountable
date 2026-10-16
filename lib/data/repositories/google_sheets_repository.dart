import 'package:csv/csv.dart';

import '../app_data_snapshot.dart';
import '../csv/csv.dart';
import '../models/models.dart';
import '../sources/google_sheets_api.dart';
import 'data_load_exception.dart';
import 'display_preference_manager.dart';
import 'data_validation_failure.dart';
import 'table_dependencies.dart';
import 'repositories.dart';

abstract final class GoogleSheetsRanges {
  static const accounts = 'Accounts!A:H';
  static const categories = 'Categories!A:C';
  static const currencies = 'Currencies!A:C';
  static const dailyAccountBalances = 'DailyAccountBalances!A:F';
  static const dailyExchangeRates = 'DailyExchangeRates!A:F';
  static const dailyNetWorth = 'DailyNetWorth!A:D';
  static const dailyManualValuations = 'DailyManualValuations!A:D';
  static const displayPreferences = 'DisplayPreferences!A:E';
  static const tags = 'Tags!A:B';
  static const transactions = 'Transactions!A:K';
}

const _displayPreferenceHeaders = <String>[
  'entity_type',
  'entity_id',
  'display_order',
  'show_in_app',
  'show_in_entry_forms',
];

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
  Future<AppDataSnapshot> addManualValuation(
    DailyManualValuation valuation,
  ) async {
    final current = await load();
    final account = current.accountsById[valuation.accountId];
    final currency = account == null
        ? null
        : current.currenciesById[account.currencyId];
    if (account == null || currency == null || !account.isValuationAccount) {
      throw StateError('Invalid manual valuation account.');
    }
    await api.appendRow(GoogleSheetsRanges.dailyManualValuations, [
      valuation.id,
      _dateString(valuation.date),
      valuation.accountId,
      valuation.value.toMajorUnitsString(currency),
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
      _displayPreferenceHeaders,
      for (final preference in normalized.preferences)
        _displayPreferenceRow(preference),
    ]);
    return reload();
  }

  @override
  Future<AppDataSnapshot> addTransaction(Transaction transaction) async {
    final current = await load();
    final accountCurrencies = {
      for (final account in current.accounts) account.id: account.currencyId,
    };
    final row = transactionToRow(
      transaction,
      current.currenciesById,
      accountCurrencies,
    );
    await api.appendRow(
      GoogleSheetsRanges.transactions,
      _transactionHeaders.map((header) => row[header] ?? '').toList(),
    );
    return reload();
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
      if (dependenciesAreValid('Transactions')) {
        try {
          final result = ModelParsers.parseTransactionsWithIssues(
            _encode(tables[GoogleSheetsRanges.transactions]!),
            accounts: accountById,
            currencies: currencyById,
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
    final ranges = const [
      GoogleSheetsRanges.accounts,
      GoogleSheetsRanges.categories,
      GoogleSheetsRanges.currencies,
      GoogleSheetsRanges.dailyAccountBalances,
      GoogleSheetsRanges.dailyExchangeRates,
      GoogleSheetsRanges.dailyNetWorth,
      GoogleSheetsRanges.dailyManualValuations,
      GoogleSheetsRanges.displayPreferences,
      GoogleSheetsRanges.tags,
      GoogleSheetsRanges.transactions,
    ];
    final response = await api.batchReadRanges(ranges);
    return {
      for (final range in ranges)
        range: _padRows(response[range] ?? const [], _columnCount[range]!),
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

const _columnCount = <String, int>{
  GoogleSheetsRanges.accounts: 8,
  GoogleSheetsRanges.categories: 3,
  GoogleSheetsRanges.currencies: 2,
  GoogleSheetsRanges.dailyAccountBalances: 6,
  GoogleSheetsRanges.dailyExchangeRates: 6,
  GoogleSheetsRanges.dailyNetWorth: 4,
  GoogleSheetsRanges.dailyManualValuations: 4,
  GoogleSheetsRanges.displayPreferences: 5,
  GoogleSheetsRanges.tags: 2,
  GoogleSheetsRanges.transactions: 11,
};

const _transactionHeaders = <String>[
  'transaction_id',
  'date',
  'description',
  'category',
  'transaction_type',
  'source_amount',
  'source_account_id',
  'dest_amount',
  'dest_account_id',
  'tag',
  'created_at',
];

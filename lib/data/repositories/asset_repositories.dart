import 'package:csv/csv.dart';

import '../app_data_snapshot.dart';
import '../csv/csv.dart';
import '../models/models.dart';
import '../sources/asset_reader.dart';
import '../sources/local_dataset_store.dart';
import 'data_load_exception.dart';
import 'display_preference_manager.dart';
import 'data_validation_failure.dart';
import 'repositories.dart';

abstract final class DataAssetPaths {
  static const accounts = 'test_sheets/Accounts.csv';
  static const categories = 'test_sheets/Categories.csv';
  static const currencies = 'test_sheets/Currencies.csv';
  static const dailyAccountBalances = 'test_sheets/DailyAccountBalances.csv';
  static const dailyExchangeRates = 'test_sheets/DailyExchangeRates.csv';
  static const dailyNetWorth = 'test_sheets/DailyNetWorth.csv';
  static const dailyManualValuations = 'test_sheets/DailyManualValuations.csv';
  static const displayPreferences = 'test_sheets/DisplayPreferences.csv';
  static const tags = 'test_sheets/Tags.csv';
  static const transactions = 'test_sheets/Transactions.csv';
}

class AssetCurrencyRepository implements CurrencyRepository {
  const AssetCurrencyRepository(this.reader);

  final AssetReader reader;

  @override
  Future<List<CurrencyDefinition>> load() {
    return _loadTable(
      tableName: 'Currencies',
      action: () async => ModelParsers.parseCurrencies(
        await reader.readString(DataAssetPaths.currencies),
      ),
    );
  }
}

class AssetAccountRepository implements AccountRepository {
  const AssetAccountRepository(this.reader);

  final AssetReader reader;

  @override
  Future<List<Account>> load({
    required Map<String, CurrencyDefinition> currencies,
  }) {
    return _loadTable(
      tableName: 'Accounts',
      action: () async => ModelParsers.parseAccounts(
        await reader.readString(DataAssetPaths.accounts),
        currencies,
      ),
    );
  }
}

class AssetCategoryRepository implements CategoryRepository {
  const AssetCategoryRepository(this.reader);

  final AssetReader reader;

  @override
  Future<List<Category>> load() {
    return _loadTable(
      tableName: 'Categories',
      action: () async => ModelParsers.parseCategories(
        await reader.readString(DataAssetPaths.categories),
      ),
    );
  }
}

class AssetTagRepository implements TagRepository {
  const AssetTagRepository(this.reader);

  final AssetReader reader;

  @override
  Future<List<Tag>> load() {
    return _loadTable(
      tableName: 'Tags',
      action: () async =>
          ModelParsers.parseTags(await reader.readString(DataAssetPaths.tags)),
    );
  }
}

class AssetTransactionRepository implements TransactionRepository {
  const AssetTransactionRepository(this.reader);

  final AssetReader reader;

  @override
  Future<List<Transaction>> load({
    required Map<String, Account> accounts,
    required Map<String, CurrencyDefinition> currencies,
  }) {
    return _loadTable(
      tableName: 'Transactions',
      action: () async => ModelParsers.parseTransactions(
        await reader.readString(DataAssetPaths.transactions),
        accounts: accounts,
        currencies: currencies,
      ),
    );
  }
}

class AssetExchangeRateRepository implements ExchangeRateRepository {
  const AssetExchangeRateRepository(this.reader);

  final AssetReader reader;

  @override
  Future<List<ExchangeRate>> load() {
    return _loadTable(
      tableName: 'DailyExchangeRates',
      action: () async => ModelParsers.parseExchangeRates(
        await reader.readString(DataAssetPaths.dailyExchangeRates),
      ),
    );
  }
}

class AssetDailyAccountBalanceRepository
    implements DailyAccountBalanceRepository {
  const AssetDailyAccountBalanceRepository(this.reader);

  final AssetReader reader;

  @override
  Future<List<DailyAccountBalance>> load({
    required Map<String, Account> accounts,
    required Map<String, CurrencyDefinition> currencies,
  }) {
    return _loadTable(
      tableName: 'DailyAccountBalances',
      action: () async => ModelParsers.parseDailyAccountBalances(
        await reader.readString(DataAssetPaths.dailyAccountBalances),
        accounts: accounts,
        currencies: currencies,
      ),
    );
  }
}

class AssetManualValuationRepository implements ManualValuationRepository {
  const AssetManualValuationRepository(this.reader);

  final AssetReader reader;

  @override
  Future<List<DailyManualValuation>> load({
    required Map<String, Account> accounts,
    required Map<String, CurrencyDefinition> currencies,
  }) {
    return _loadTable(
      tableName: 'DailyManualValuations',
      action: () async => ModelParsers.parseDailyManualValuations(
        await reader.readString(DataAssetPaths.dailyManualValuations),
        accounts: accounts,
        currencies: currencies,
      ),
    );
  }
}

class AssetDailyNetWorthRepository implements DailyNetWorthRepository {
  const AssetDailyNetWorthRepository(this.reader);

  final AssetReader reader;

  @override
  Future<List<DailyNetWorth>> load({
    required Map<String, CurrencyDefinition> currencies,
  }) {
    return _loadTable(
      tableName: 'DailyNetWorth',
      action: () async => ModelParsers.parseDailyNetWorth(
        await reader.readString(DataAssetPaths.dailyNetWorth),
        currencies,
      ),
    );
  }
}

class AssetAppDataRepository implements AppDataRepository {
  AssetAppDataRepository({AssetReader? reader, this.store})
    : reader = reader ?? const FlutterAssetReader();

  final AssetReader reader;
  final LocalDatasetStore? store;

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
  @override
  Future<AppDataSnapshot> addManualValuation(
    DailyManualValuation valuation,
  ) async {
    final current = await load();
    final tables = await _readDataset();
    final account = current.accountsById[valuation.accountId];
    final currency = account == null
        ? null
        : current.currenciesById[account.currencyId];
    if (account == null || currency == null || !account.isValuationAccount) {
      throw StateError('Invalid manual valuation account.');
    }
    tables[DataAssetPaths.dailyManualValuations] = _appendCsvRow(
      tables[DataAssetPaths.dailyManualValuations]!,
      {
        'valuation_id': valuation.id,
        'date': _dateString(valuation.date),
        'account_id': valuation.accountId,
        'value': valuation.value.toMajorUnitsString(currency),
      },
    );
    if (store == null) throw StateError('This data source is read-only.');
    await store!.write(tables);
    _cachedSnapshot = null;
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
    if (store == null) throw StateError('This data source is read-only.');
    final tables = await _readDataset();
    tables[DataAssetPaths.displayPreferences] = _displayPreferencesCsv(
      normalized.preferences,
    );
    await store!.write(tables);
    _cachedSnapshot = null;
    return reload();
  }

  @override
  Future<AppDataSnapshot> addTransaction(Transaction transaction) async {
    final current = await load();
    final tables = await _readDataset();
    final accountCurrencies = {
      for (final account in current.accounts) account.id: account.currencyId,
    };
    final row = transactionToRow(
      transaction,
      current.currenciesById,
      accountCurrencies,
    );
    tables[DataAssetPaths.transactions] = _appendCsvRow(
      tables[DataAssetPaths.transactions]!,
      row,
    );
    if (store == null) {
      throw StateError('This data source is read-only.');
    }
    await store!.write(tables);
    _cachedSnapshot = null;
    return reload();
  }

  Future<AppDataSnapshot> _loadFreshSnapshot() async {
    final tables = await _readDataset();
    try {
      final currencyList = ModelParsers.parseCurrencies(
        tables[DataAssetPaths.currencies]!,
      );
      final currencyById = {
        for (final currency in currencyList) currency.id: currency,
      };
      final accountList = ModelParsers.parseAccounts(
        tables[DataAssetPaths.accounts]!,
        currencyById,
      );
      final accountById = {
        for (final account in accountList) account.id: account,
      };
      final categoryList = ModelParsers.parseCategories(
        tables[DataAssetPaths.categories]!,
      );
      final tagList = ModelParsers.parseTags(tables[DataAssetPaths.tags]!);
      final preferenceList = ModelParsers.parseDisplayPreferences(
        tables[DataAssetPaths.displayPreferences]!,
      );
      final synchronizedPreferences = synchronizeDisplayPreferences(
        existing: preferenceList,
        accountIds: accountById.keys.toSet(),
        categoryIds: categoryList.map((item) => item.id).toSet(),
        tagIds: tagList.map((item) => item.id).toSet(),
      );
      if (synchronizedPreferences.missing.isNotEmpty && store != null) {
        tables[DataAssetPaths.displayPreferences] = _displayPreferencesCsv(
          synchronizedPreferences.preferences,
        );
        await store!.write(tables);
      }
      final transactionList = ModelParsers.parseTransactions(
        tables[DataAssetPaths.transactions]!,
        accounts: accountById,
        currencies: currencyById,
      );
      final exchangeRateList = ModelParsers.parseExchangeRates(
        tables[DataAssetPaths.dailyExchangeRates]!,
      );
      final dailyAccountBalanceList = ModelParsers.parseDailyAccountBalances(
        tables[DataAssetPaths.dailyAccountBalances]!,
        accounts: accountById,
        currencies: currencyById,
      );
      final dailyNetWorthList = ModelParsers.parseDailyNetWorth(
        tables[DataAssetPaths.dailyNetWorth]!,
        currencyById,
      );
      final dailyManualValuationList = ModelParsers.parseDailyManualValuations(
        tables[DataAssetPaths.dailyManualValuations]!,
        accounts: accountById,
        currencies: currencyById,
      );

      return AppDataSnapshot(
        accounts: accountList,
        categories: categoryList,
        currencies: currencyList,
        tags: tagList,
        transactions: transactionList,
        exchangeRates: exchangeRateList,
        dailyAccountBalances: dailyAccountBalanceList,
        dailyNetWorth: dailyNetWorthList,
        dailyManualValuations: dailyManualValuationList,
        displayPreferences: synchronizedPreferences.preferences,
      );
    } on DataValidationFailure {
      rethrow;
    } catch (error) {
      throw DataValidationFailure([issueFromError('Local dataset', error)]);
    }
  }

  Future<Map<String, String>> _readDataset() async {
    final stored = await store?.read();
    if (stored != null && _storedDatasetMatchesSchema(stored)) {
      final tables = Map.of(stored);
      for (final path in _runtimeAssetPaths) {
        if (tables.containsKey(path)) continue;
        try {
          tables[path] = await reader.readString(path);
        } catch (error) {
          throw DataLoadException(
            tableName: _tableNameFromPath(path),
            message: error.toString(),
            cause: error,
          );
        }
      }
      if (store != null) await store!.write(tables);
      return tables;
    }

    final tables = <String, String>{};
    for (final path in _runtimeAssetPaths) {
      try {
        tables[path] = await reader.readString(path);
      } catch (error) {
        throw DataLoadException(
          tableName: _tableNameFromPath(path),
          message: error.toString(),
          cause: error,
        );
      }
    }
    if (store != null) await store!.write(tables);
    return tables;
  }

  static bool _storedDatasetMatchesSchema(Map<String, String> tables) {
    for (final entry in _runtimeHeaders.entries) {
      final source = tables[entry.key];
      if (source == null) return false;
      final rows = csv.decode(source);
      if (rows.isEmpty ||
          rows.first.map((value) => value.toString()).join(',') !=
              entry.value.join(',')) {
        return false;
      }
    }
    return true;
  }

  static String _displayPreferencesCsv(List<DisplayPreference> preferences) {
    return csv.encode([
      _runtimeHeaders[DataAssetPaths.displayPreferences]!,
      for (final preference in preferences)
        [
          preference.entityType,
          preference.entityId,
          preference.displayOrder.toString(),
          preference.showInApp.toString().toUpperCase(),
          preference.showInEntryForms.toString().toUpperCase(),
        ],
    ]);
  }

  static String _appendCsvRow(String source, Map<String, String> row) {
    final rows = csv.decode(source);
    if (rows.isEmpty) throw const FormatException('CSV has no header row.');
    final headers = rows.first.map((value) => value.toString()).toList();
    rows.add([for (final header in headers) row[header] ?? '']);
    return csv.encode(rows);
  }
}

String _tableNameFromPath(String path) {
  final fileName = path.split('/').last;
  return fileName.endsWith('.csv')
      ? fileName.substring(0, fileName.length - 4)
      : fileName;
}

const _runtimeHeaders = <String, List<String>>{
  DataAssetPaths.currencies: [
    'currency_id',
    'currency_symbol',
    'decimal_places',
  ],
  DataAssetPaths.accounts: [
    'account_id',
    'name',
    'account_type',
    'currency',
    'opening_balance',
    'opening_date',
    'closing_date',
    'uses_manual_valuations',
  ],
  DataAssetPaths.categories: [
    'category_id',
    'category_name',
    'allowed_transaction_types',
  ],
  DataAssetPaths.dailyAccountBalances: [
    'balance_id',
    'balance_date',
    'account_id',
    'balance',
    'balance_usd',
    'retrieved_at',
  ],
  DataAssetPaths.dailyExchangeRates: [
    'rate_id',
    'rate_date',
    'currency',
    'rate_to_usd',
    'source_rate_date',
    'retrieved_at',
  ],
  DataAssetPaths.dailyNetWorth: [
    'net_worth_id',
    'net_worth_date',
    'amount',
    'retrieved_at',
  ],
  DataAssetPaths.dailyManualValuations: [
    'valuation_id',
    'date',
    'account_id',
    'value',
  ],
  DataAssetPaths.displayPreferences: [
    'entity_type',
    'entity_id',
    'display_order',
    'show_in_app',
    'show_in_entry_forms',
  ],
  DataAssetPaths.tags: ['tag_id', 'tag_name'],
  DataAssetPaths.transactions: [
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
  ],
};

const _runtimeAssetPaths = <String>[
  DataAssetPaths.currencies,
  DataAssetPaths.accounts,
  DataAssetPaths.categories,
  DataAssetPaths.dailyAccountBalances,
  DataAssetPaths.dailyExchangeRates,
  DataAssetPaths.dailyNetWorth,
  DataAssetPaths.dailyManualValuations,
  DataAssetPaths.displayPreferences,
  DataAssetPaths.tags,
  DataAssetPaths.transactions,
];

String _dateString(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

Future<T> _loadTable<T>({
  required String tableName,
  required Future<T> Function() action,
}) async {
  try {
    return await action();
  } on DataLoadException {
    rethrow;
  } catch (error) {
    throw DataLoadException(
      tableName: tableName,
      message: error.toString(),
      cause: error,
    );
  }
}

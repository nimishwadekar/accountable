import 'package:csv/csv.dart';

import '../app_data_snapshot.dart';
import '../csv/csv.dart';
import '../models/models.dart';
import '../sources/asset_reader.dart';
import '../sources/local_dataset_store.dart';
import '../table_schema.dart';
import 'data_load_exception.dart';
import 'display_preference_manager.dart';
import 'data_validation_failure.dart';
import 'transaction_write_validator.dart';
import 'manual_valuation_write_validator.dart';
import 'repositories.dart';

abstract final class DataAssetPaths {
  static final accounts = RuntimeTableSchemas.accounts.assetPath;
  static final categories = RuntimeTableSchemas.categories.assetPath;
  static final currencies = RuntimeTableSchemas.currencies.assetPath;
  static final dailyAccountBalances =
      RuntimeTableSchemas.dailyAccountBalances.assetPath;
  static final dailyExchangeRates =
      RuntimeTableSchemas.dailyExchangeRates.assetPath;
  static final dailyNetWorth = RuntimeTableSchemas.dailyNetWorth.assetPath;
  static final dailyManualValuations =
      RuntimeTableSchemas.dailyManualValuations.assetPath;
  static final displayPreferences =
      RuntimeTableSchemas.displayPreferences.assetPath;
  static final tags = RuntimeTableSchemas.tags.assetPath;
  static final transactions = RuntimeTableSchemas.transactions.assetPath;
  static final transactionsToMigrate =
      RuntimeTableSchemas.transactionsToMigrate.assetPath;
  static final transactionTemplates =
      RuntimeTableSchemas.transactionTemplates.assetPath;
  static final incomeAllocations =
      RuntimeTableSchemas.incomeAllocations.assetPath;
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
  AssetAppDataRepository({
    AssetReader? reader,
    this.store,
    this.migrationAssistance = false,
  }) : reader = reader ?? const FlutterAssetReader();

  final AssetReader reader;
  final LocalDatasetStore? store;
  final bool migrationAssistance;

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
  ) => addManualValuations([valuation]);

  @override
  Future<AppDataSnapshot> addManualValuations(
    List<DailyManualValuation> valuations,
  ) async {
    final current = await load();
    final validationErrors = validateManualValuationsForWrite(valuations, current);
    if (validationErrors.isNotEmpty) {
      throw StateError(validationErrors.join(' '));
    }
    if (store == null) throw StateError('This data source is read-only.');
    final tables = await _readDataset();
    var table = tables[DataAssetPaths.dailyManualValuations]!;
    for (final valuation in valuations) {
      final currency = current.currenciesById[valuation.value.currencyId]!;
      table = _appendCsvRow(
        table,
        {
          'valuation_id': valuation.id,
          'date': _dateString(valuation.date),
          'account_id': valuation.accountId,
          'value': valuation.value.toMajorUnitsString(currency),
        },
      );
    }
    tables[DataAssetPaths.dailyManualValuations] = table;
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
  @override
  Future<AppDataSnapshot> addIncomeAllocation(IncomeAllocation allocation) =>
      throw StateError('Income allocations are not implemented in local assets mode.');

  @override
  Future<AppDataSnapshot> addTransactionTemplate(
    TransactionTemplate template,
  ) => throw StateError('Templates are not implemented in local assets mode.');

  @override
  Future<AppDataSnapshot> updateTransactionTemplate(
    TransactionTemplate template,
  ) => throw StateError('Templates are not implemented in local assets mode.');

  @override
  Future<AppDataSnapshot> deleteTransactionTemplate(String templateId) =>
      throw StateError('Templates are not implemented in local assets mode.');

  @override
  Future<AppDataSnapshot> addTransaction(Transaction transaction) =>
      addTransactions([transaction]);

  @override
  Future<AppDataSnapshot> addTransactions(List<Transaction> transactions) async {
    final current = await load();
    final validationErrors = validateTransactionsForWrite(transactions, current);
    if (validationErrors.isNotEmpty) {
      throw StateError(validationErrors.join(' '));
    }
    final tables = await _readDataset();
    final accountCurrencies = {
      for (final account in current.accounts) account.id: account.currencyId,
    };
    for (final transaction in transactions) {
      final row = transactionToRow(
        transaction,
        current.currenciesById,
        accountCurrencies,
      );
      tables[DataAssetPaths.transactions] = _appendCsvRow(
        tables[DataAssetPaths.transactions]!,
        row,
      );
    }
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
      final allocationList = ModelParsers.parseIncomeAllocations(
        tables[DataAssetPaths.incomeAllocations]!,
        accounts: accountById,
        currencies: currencyById,
        categories: {
          for (final category in categoryList) category.id: category,
        },
      );
      final templateList = ModelParsers.parseTransactionTemplates(
        tables[DataAssetPaths.transactionTemplates]!,
        accounts: accountById,
        currencies: currencyById,
      );
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
        categories: {
          for (final category in categoryList) category.id: category,
        },
        tags: {for (final tag in tagList) tag.id: tag},
      );
      final migrationTransactions = migrationAssistance
          ? ModelParsers.parseTransactions(
              tables[DataAssetPaths.transactionsToMigrate]!,
              accounts: accountById,
              currencies: currencyById,
              categories: {
                for (final category in categoryList) category.id: category,
              },
              tags: {for (final tag in tagList) tag.id: tag},
              tableName: 'TransactionsToMigrate',
            )
          : const <Transaction>[];
      if (migrationAssistance && migrationTransactions.isEmpty) {
        throw const FormatException(
          'TransactionsToMigrate must contain at least one transaction.',
        );
      }
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
        transactionsToMigrate: migrationTransactions,
        exchangeRates: exchangeRateList,
        dailyAccountBalances: dailyAccountBalanceList,
        dailyNetWorth: dailyNetWorthList,
        dailyManualValuations: dailyManualValuationList,
        displayPreferences: synchronizedPreferences.preferences,
        transactionTemplates: templateList,
        incomeAllocations: allocationList,
      );
    } on DataValidationFailure {
      rethrow;
    } catch (error) {
      throw DataValidationFailure([issueFromError('Local dataset', error)]);
    }
  }

  Future<Map<String, String>> _readDataset() async {
    final stored = await store?.read();
    if (stored != null &&
        _storedDatasetMatchesSchema(stored, migrationAssistance)) {
      final tables = Map.of(stored);
      for (final path in _runtimeAssetPaths(migrationAssistance)) {
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
    for (final path in _runtimeAssetPaths(migrationAssistance)) {
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

  static bool _storedDatasetMatchesSchema(
    Map<String, String> tables,
    bool migrationAssistance,
  ) {
    for (final path in _runtimeAssetPaths(migrationAssistance)) {
      final source = tables[path];
      final headers = _runtimeHeaders[path]!;
      if (source == null) return false;
      final rows = csv.decode(source);
      if (rows.isEmpty ||
          rows.first.map((value) => value.toString()).join(',') !=
              headers.join(',')) {
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

final _runtimeHeaders = Map.unmodifiable({
  for (final schema in RuntimeTableSchemas.all) schema.assetPath: schema.headers,
});

List<String> _runtimeAssetPaths(bool migrationAssistance) => [
  for (final schema in RuntimeTableSchemas.all)
    if (schema != RuntimeTableSchemas.transactionsToMigrate)
      schema.assetPath,
  if (migrationAssistance) RuntimeTableSchemas.transactionsToMigrate.assetPath,
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

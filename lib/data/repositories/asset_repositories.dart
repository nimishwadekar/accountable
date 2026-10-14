import 'package:csv/csv.dart';

import '../app_data_snapshot.dart';
import '../csv/csv.dart';
import '../models/models.dart';
import '../sources/asset_reader.dart';
import '../sources/local_dataset_store.dart';
import 'data_load_exception.dart';
import 'repositories.dart';

abstract final class DataAssetPaths {
  static const accounts = 'test_sheets/Accounts.csv';
  static const categories = 'test_sheets/Categories.csv';
  static const currencies = 'test_sheets/Currencies.csv';
  static const dailyAccountBalances = 'test_sheets/DailyAccountBalances.csv';
  static const dailyExchangeRates = 'test_sheets/DailyExchangeRates.csv';
  static const dailyNetWorth = 'test_sheets/DailyNetWorth.csv';
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

      return AppDataSnapshot(
        accounts: accountList,
        categories: categoryList,
        currencies: currencyList,
        tags: tagList,
        transactions: transactionList,
        exchangeRates: exchangeRateList,
        dailyAccountBalances: dailyAccountBalanceList,
        dailyNetWorth: dailyNetWorthList,
      );
    } catch (error) {
      throw DataLoadException(
        tableName: 'local dataset',
        message: error.toString(),
        cause: error,
      );
    }
  }

  Future<Map<String, String>> _readDataset() async {
    final stored = await store?.read();
    if (stored != null) {
      for (final path in _runtimeAssetPaths) {
        if (!stored.containsKey(path)) {
          throw DataLoadException(
            tableName: 'local dataset',
            message: 'Stored dataset is missing $path.',
          );
        }
      }
      return Map.of(stored);
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

const _runtimeAssetPaths = <String>[
  DataAssetPaths.currencies,
  DataAssetPaths.accounts,
  DataAssetPaths.categories,
  DataAssetPaths.dailyAccountBalances,
  DataAssetPaths.dailyExchangeRates,
  DataAssetPaths.dailyNetWorth,
  DataAssetPaths.tags,
  DataAssetPaths.transactions,
];

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

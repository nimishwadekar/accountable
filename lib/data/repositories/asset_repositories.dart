import '../app_data_snapshot.dart';
import '../csv/csv.dart';
import '../models/models.dart';
import '../sources/asset_reader.dart';
import 'data_load_exception.dart';
import 'repositories.dart';

abstract final class DataAssetPaths {
  static const accounts = 'test_sheets/Accounts.csv';
  static const categories = 'test_sheets/Categories.csv';
  static const currencies = 'test_sheets/Currencies.csv';
  static const dailyAccountBalances =
      'test_sheets/DailyAccountBalances.csv';
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
      action: () async => ModelParsers.parseTags(
        await reader.readString(DataAssetPaths.tags),
      ),
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
  AssetAppDataRepository({AssetReader? reader})
      : this._withRepositories(
          reader ?? const FlutterAssetReader(),
        );

  AssetAppDataRepository._withRepositories(AssetReader reader)
      : currencies = AssetCurrencyRepository(reader),
        accounts = AssetAccountRepository(reader),
        categories = AssetCategoryRepository(reader),
        tags = AssetTagRepository(reader),
        transactions = AssetTransactionRepository(reader),
        exchangeRates = AssetExchangeRateRepository(reader),
        dailyAccountBalances = AssetDailyAccountBalanceRepository(reader),
        dailyNetWorth = AssetDailyNetWorthRepository(reader);

  final CurrencyRepository currencies;
  final AccountRepository accounts;
  final CategoryRepository categories;
  final TagRepository tags;
  final TransactionRepository transactions;
  final ExchangeRateRepository exchangeRates;
  final DailyAccountBalanceRepository dailyAccountBalances;
  final DailyNetWorthRepository dailyNetWorth;

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

  Future<AppDataSnapshot> _loadFreshSnapshot() async {
    final currencyList = await currencies.load();
    final currencyById = {
      for (final currency in currencyList) currency.id: currency,
    };
    final accountList = await accounts.load(currencies: currencyById);
    final accountById = {
      for (final account in accountList) account.id: account,
    };

    final categoryList = await categories.load();
    final tagList = await tags.load();
    final transactionList = await transactions.load(
      accounts: accountById,
      currencies: currencyById,
    );
    final exchangeRateList = await exchangeRates.load();
    final dailyAccountBalanceList = await dailyAccountBalances.load(
      accounts: accountById,
      currencies: currencyById,
    );
    final dailyNetWorthList = await dailyNetWorth.load(
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
    );
  }
}

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

import 'package:csv/csv.dart';

import '../app_data_snapshot.dart';
import '../csv/csv.dart';
import '../models/models.dart';
import '../sources/google_sheets_api.dart';
import 'data_load_exception.dart';
import 'repositories.dart';

abstract final class GoogleSheetsRanges {
  static const accounts = 'Accounts!A:H';
  static const categories = 'Categories!A:C';
  static const currencies = 'Currencies!A:C';
  static const dailyAccountBalances = 'DailyAccountBalances!A:F';
  static const dailyExchangeRates = 'DailyExchangeRates!A:F';
  static const dailyNetWorth = 'DailyNetWorth!A:D';
  static const tags = 'Tags!A:B';
  static const transactions = 'Transactions!A:K';
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
      final currencies = ModelParsers.parseCurrencies(
        _encode(tables[GoogleSheetsRanges.currencies]!),
      );
      final currencyById = {
        for (final currency in currencies) currency.id: currency,
      };
      final accounts = ModelParsers.parseAccounts(
        _encode(tables[GoogleSheetsRanges.accounts]!),
        currencyById,
      );
      final accountById = {for (final account in accounts) account.id: account};
      final categories = ModelParsers.parseCategories(
        _encode(tables[GoogleSheetsRanges.categories]!),
      );
      final tags = ModelParsers.parseTags(
        _encode(tables[GoogleSheetsRanges.tags]!),
      );
      final transactions = ModelParsers.parseTransactions(
        _encode(tables[GoogleSheetsRanges.transactions]!),
        accounts: accountById,
        currencies: currencyById,
      );
      final exchangeRates = ModelParsers.parseExchangeRates(
        _encode(tables[GoogleSheetsRanges.dailyExchangeRates]!),
      );
      final dailyAccountBalances = ModelParsers.parseDailyAccountBalances(
        _encode(tables[GoogleSheetsRanges.dailyAccountBalances]!),
        accounts: accountById,
        currencies: currencyById,
      );
      final dailyNetWorth = ModelParsers.parseDailyNetWorth(
        _encode(tables[GoogleSheetsRanges.dailyNetWorth]!),
        currencyById,
      );

      return AppDataSnapshot(
        accounts: accounts,
        categories: categories,
        currencies: currencies,
        tags: tags,
        transactions: transactions,
        exchangeRates: exchangeRates,
        dailyAccountBalances: dailyAccountBalances,
        dailyNetWorth: dailyNetWorth,
      );
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
}

const _columnCount = <String, int>{
  GoogleSheetsRanges.accounts: 8,
  GoogleSheetsRanges.categories: 3,
  GoogleSheetsRanges.currencies: 2,
  GoogleSheetsRanges.dailyAccountBalances: 6,
  GoogleSheetsRanges.dailyExchangeRates: 6,
  GoogleSheetsRanges.dailyNetWorth: 4,
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

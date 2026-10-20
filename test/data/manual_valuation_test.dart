import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses valuation rows with account currencies', () {
    const currencies = {
      'USD': CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2),
    };
    final accounts = {
      'brokerage': Account(
        id: 'brokerage',
        name: 'Brokerage',
        accountType: 'asset',
        currencyId: 'USD',
        openingBalance: Money.zero(currencies['USD']!),
        openingDate: DateTime.utc(2026, 1, 1),
        closingDate: null,
        usesManualValuations: true,
      ),
    };
    final valuations = ModelParsers.parseDailyManualValuations(
      'valuation_id,date,account_id,value\n'
      'v1,2026-10-15,brokerage,1234.56\n',
      accounts: accounts,
      currencies: currencies,
    );

    expect(valuations.single.value.minorUnits, 123456);
  });

  test(
    'manual valuation replaces the asset account in daily net worth',
    () async {
      final source = await AssetAppDataRepository().load();
      final checking = source.accountsById['chase_checking']!;
      final valuationAccount = Account(
        id: checking.id,
        name: checking.name,
        accountType: 'asset',
        currencyId: checking.currencyId,
        openingBalance: checking.openingBalance,
        openingDate: checking.openingDate,
        closingDate: checking.closingDate,
        usesManualValuations: true,
      );
      final data = AppDataSnapshot(
        accounts: [
          valuationAccount,
          ...source.accounts.where((account) => account.id != checking.id),
        ],
        categories: source.categories,
        currencies: source.currencies,
        tags: source.tags,
        transactions: source.transactions,
        exchangeRates: source.exchangeRates,
        dailyAccountBalances: const [],
        dailyNetWorth: const [],
        dailyManualValuations: [
          DailyManualValuation(
            id: '2026-10-10-chase_checking',
            date: DateTime.utc(2026, 10, 10),
            accountId: checking.id,
            value: Money.fromMajorUnits(
              value: '2000',
              currency: source.currenciesById['USD']!,
            ),
          ),
        ],
      );
      final client = _MaintenanceClient();
      await DailyMaintenanceService(
        client: client,
        data: data,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'rates': {'INR': 96.4},
            }),
            200,
          ),
        ),
      ).catchUp(yesterday: DateTime.utc(2026, 10, 10));

      expect(client.replacedNetWorthRows, isEmpty);
      final netWorthRow = client.appendedRows.firstWhere(
        (row) => row.first == '2026-10-10-net',
      );
      expect(netWorthRow[2], '1757.47');
      expect(
        client.appendedRows.any(
          (row) => row.first == '2026-10-10-chase_checking',
        ),
        isFalse,
      );
    },
  );

  test('rejects valuation rows for ledger accounts', () {
    const currencies = {
      'USD': CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2),
    };
    final accounts = {
      'checking': Account(
        id: 'checking',
        name: 'Checking',
        accountType: 'cash',
        currencyId: 'USD',
        openingBalance: Money.zero(currencies['USD']!),
        openingDate: DateTime.utc(2026, 1, 1),
        closingDate: null,
        usesManualValuations: false,
      ),
    };

    expect(
      () => ModelParsers.parseDailyManualValuations(
        'valuation_id,date,account_id,value\n'
        'v1,2026-10-15,checking,100\n',
        accounts: accounts,
        currencies: currencies,
      ),
      throwsFormatException,
    );
  });
}

class _MaintenanceClient extends SheetsTableClient {
  final Map<String, List<List<String>>> tables = {
    'DailyExchangeRates!B:B': const [
      ['rate_date'],
    ],
    'DailyAccountBalances!B:B': const [
      ['balance_date'],
    ],
    'DailyNetWorth!B:B': const [
      ['net_worth_date'],
    ],
  };
  final List<List<String>> appendedRows = [];
  final List<List<String>> replacedNetWorthRows = [];

  @override
  Future<void> appendRow(String range, List<String> values) async {
    appendedRows.add(values);
  }

  @override
  Future<Map<String, List<List<String>>>> batchReadRanges(
    List<String> ranges,
  ) async {
    return {for (final range in ranges) range: tables[range] ?? const []};
  }

  @override
  Future<List<List<String>>> readRange(String range) async =>
      tables[range] ?? [];

  @override
  Future<void> replaceRange(String range, List<List<String>> values) async {
    if (range == GoogleSheetsRanges.dailyNetWorth) {
      replacedNetWorthRows.addAll(values);
    }
  }
}

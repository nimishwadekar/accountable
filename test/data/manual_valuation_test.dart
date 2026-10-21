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
    'manual valuation before transaction history is carried into net worth',
    () async {
      final source = await AssetAppDataRepository().load();
      final asset = source.accountsById['fidelity-401k-2065']!;
      final usd = source.currenciesById['USD']!;
      final data = AppDataSnapshot(
        accounts: source.accounts,
        categories: source.categories,
        currencies: source.currencies,
        tags: source.tags,
        transactions: source.transactions,
        exchangeRates: const [],
        dailyAccountBalances: const [],
        dailyNetWorth: const [],
        dailyManualValuations: [
          DailyManualValuation(
            id: '2026-10-05-fidelity-401k-2065',
            date: DateTime.utc(2026, 10, 5),
            accountId: asset.id,
            value: Money.fromMajorUnits(value: '1000', currency: usd),
          ),
        ],
      );
      final client = _MaintenanceClient();
      await DailyMaintenanceService(
        client: client,
        data: data,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({'rates': {'INR': 96.4}}),
            200,
          ),
        ),
      ).catchUp(yesterday: DateTime.utc(2026, 10, 10));

      final netWorth = client.replacedNetWorthRows.firstWhere(
        (row) => row.first == '2026-10-10-net',
      );
      expect(netWorth[2], '1717.47');
    },
  );

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

      expect(client.replacedNetWorthRows, isNotEmpty);
      final netWorthRow = client.replacedNetWorthRows.firstWhere(
        (row) => row.first == '2026-10-10-net',
      );
      expect(netWorthRow[2], '1757.47');
    },
  );

  test('validates batch valuation signs, dates, and duplicate keys', () async {
    final data = await AssetAppDataRepository().load();
    final asset = data.accountsById['fidelity-401k-2065']!;
    final liability = data.accountsById['hdfc-credila-loan']!;
    final usd = data.currenciesById['USD']!;
    final inr = data.currenciesById['INR']!;

    final errors = validateManualValuationsForWrite([
      DailyManualValuation(
        id: 'asset-negative',
        date: DateTime.utc(2026, 10, 15),
        accountId: asset.id,
        value: Money.fromMajorUnits(value: '-1', currency: usd),
      ),
      DailyManualValuation(
        id: 'liability-positive',
        date: DateTime.utc(2026, 10, 15),
        accountId: liability.id,
        value: Money.fromMajorUnits(value: '1', currency: inr),
      ),
      DailyManualValuation(
        id: 'duplicate-a',
        date: DateTime.utc(2026, 10, 16),
        accountId: asset.id,
        value: Money.fromMajorUnits(value: '1', currency: usd),
      ),
      DailyManualValuation(
        id: 'duplicate-b',
        date: DateTime.utc(2026, 10, 16),
        accountId: asset.id,
        value: Money.fromMajorUnits(value: '2', currency: usd),
      ),
    ], data);

    expect(errors, contains('Asset valuations cannot be negative.'));
    expect(
      errors,
      contains('Liability valuations must be stored as negative values.'),
    );
    expect(
      errors,
      contains('Duplicate valuation for fidelity-401k-2065 on 2026-10-16.'),
    );
  });

  test(
    'reports invalid valuation accounts, currencies, dates, and IDs',
    () async {
      final data = await AssetAppDataRepository().load();
      final asset = data.accountsById['fidelity-401k-2065']!;
      final checking = data.accountsById['chase_checking']!;
      final usd = data.currenciesById['USD']!;
      final inr = data.currenciesById['INR']!;
      final errors = validateManualValuationsForWrite([
        DailyManualValuation(
          id: 'unknown-account',
          date: DateTime.utc(2026, 10, 15),
          accountId: 'missing',
          value: Money.fromMajorUnits(value: '1', currency: usd),
        ),
        DailyManualValuation(
          id: 'ledger-account',
          date: DateTime.utc(2026, 10, 15),
          accountId: checking.id,
          value: Money.fromMajorUnits(value: '1', currency: usd),
        ),
        DailyManualValuation(
          id: 'wrong-currency',
          date: DateTime.utc(2026, 10, 15),
          accountId: asset.id,
          value: Money.fromMajorUnits(value: '1', currency: inr),
        ),
        DailyManualValuation(
          id: 'before-opening',
          date: DateTime.utc(2026, 10, 4),
          accountId: asset.id,
          value: Money.fromMajorUnits(value: '1', currency: usd),
        ),
        DailyManualValuation(
          id: 'after-closing',
          date: DateTime.utc(2026, 10, 15),
          accountId: asset.id,
          value: Money.fromMajorUnits(value: '1', currency: usd),
        ),
        DailyManualValuation(
          id: 'duplicate-existing',
          date: DateTime.utc(2026, 10, 14),
          accountId: asset.id,
          value: Money.fromMajorUnits(value: '1', currency: usd),
        ),
      ], data);

      expect(errors, contains('Unknown valuation account: missing.'));
      expect(errors, contains('Account chase_checking does not use manual valuations.'));
      expect(
      errors,
      contains('Valuation currency INR does not match account currency USD.'),
    );
      expect(
      errors,
      contains(
        'Valuation date is before account fidelity-401k-2065 opened.',
      ),
    );
      expect(
        errors,
        contains('Duplicate valuation for fidelity-401k-2065 on 2026-10-14.'),
      );
    },
  );

  test('rejects duplicate valuation account dates', () {
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

    expect(
      () => ModelParsers.parseDailyManualValuations(
        'valuation_id,date,account_id,value\n'
        'v1,2026-10-15,brokerage,100\n'
        'v2,2026-10-15,brokerage,200\n',
        accounts: accounts,
        currencies: currencies,
      ),
      throwsFormatException,
    );
  });

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

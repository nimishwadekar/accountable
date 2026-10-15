import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('daily USD balances preserve currency minor units', () async {
    final data = await AssetAppDataRepository().load();
    final client = _FakeSheetsClient({
      'DailyExchangeRates!B:B': [
        ['rate_date'],
        ['2026-10-12'],
      ],
      'DailyAccountBalances!B:B': [
        ['balance_date'],
        ['2026-10-12'],
      ],
      'DailyNetWorth!B:B': [
        ['net_worth_date'],
        ['2026-10-12'],
      ],
    });
    final httpClient = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'rates': {'INR': 96.4},
        }),
        200,
      ),
    );

    await DailyMaintenanceService(
      client: client,
      data: data,
      httpClient: httpClient,
    ).catchUp(yesterday: DateTime.utc(2026, 10, 13));

    final checkingBalance = client.appendedRows.firstWhere(
      (row) => row.isNotEmpty && row.first == '2026-10-13-chase_checking',
    );
    expect(checkingBalance[3], '1560');
    expect(checkingBalance[4], '1560');
  });

  test(
    'catch-up resumes after a partial write without duplicate rates',
    () async {
      final data = await AssetAppDataRepository().load();
      final client = _ResumableSheetsClient();
      final httpClient = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'rates': {'INR': 96.4},
          }),
          200,
        ),
      );
      final service = DailyMaintenanceService(
        client: client,
        data: data,
        httpClient: httpClient,
      );

      await expectLater(
        service.catchUp(yesterday: DateTime.utc(2026, 10, 13)),
        throwsStateError,
      );

      client.failOnAppendNumber = null;
      final reloadedData = AppDataSnapshot(
        accounts: data.accounts,
        categories: data.categories,
        currencies: data.currencies,
        tags: data.tags,
        transactions: data.transactions,
        exchangeRates: [
          ...data.exchangeRates,
          ExchangeRate(
            id: '2026-10-13-USD',
            date: DateTime.utc(2026, 10, 13),
            currencyId: 'USD',
            rateToUsd: Decimal.one,
            retrievedAt: DateTime.utc(2026, 10, 15),
          ),
          ExchangeRate(
            id: '2026-10-13-INR',
            date: DateTime.utc(2026, 10, 13),
            currencyId: 'INR',
            rateToUsd: Decimal.parse('0.01037344398'),
            retrievedAt: DateTime.utc(2026, 10, 15),
          ),
        ],
        dailyAccountBalances: data.dailyAccountBalances,
        dailyNetWorth: data.dailyNetWorth,
      );
      await DailyMaintenanceService(
        client: client,
        data: reloadedData,
        httpClient: httpClient,
      ).catchUp(yesterday: DateTime.utc(2026, 10, 13));

      expect(
        client.appendedRows
            .where((row) => row.first == '2026-10-13-USD')
            .length,
        1,
      );
      expect(
        client.appendedRows
            .where((row) => row.first == '2026-10-13-chase_checking')
            .length,
        1,
      );
      expect(
        client.appendedRows
            .where((row) => row.first == '2026-10-13-net')
            .length,
        1,
      );
    },
  );
}

class _ResumableSheetsClient implements SheetsTableClient {
  final Map<String, List<List<String>>> tables = {
    'DailyExchangeRates!B:B': [
      ['rate_date'],
      ['2026-10-12'],
    ],
    'DailyAccountBalances!B:B': [
      ['balance_date'],
      ['2026-10-12'],
    ],
    'DailyNetWorth!B:B': [
      ['net_worth_date'],
      ['2026-10-12'],
    ],
  };

  final List<List<String>> appendedRows = [];
  int appendCount = 0;
  int? failOnAppendNumber = 3;

  @override
  Future<void> appendRow(String range, List<String> values) async {
    appendCount++;
    if (appendCount == failOnAppendNumber) {
      throw StateError('Injected partial-write failure.');
    }
    appendedRows.add(values);
    final dateRange = switch (range) {
      'DailyExchangeRates!A:E' => 'DailyExchangeRates!B:B',
      'DailyAccountBalances!A:F' => 'DailyAccountBalances!B:B',
      'DailyNetWorth!A:D' => 'DailyNetWorth!B:B',
      _ => null,
    };
    if (dateRange != null) tables[dateRange]!.add([values[1]]);
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
  Future<void> replaceRange(String range, List<List<String>> values) async {}
}

class _FakeSheetsClient implements SheetsTableClient {
  _FakeSheetsClient(this.tables);

  final Map<String, List<List<String>>> tables;
  final List<List<String>> appendedRows = [];

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
    tables[range] = values;
  }
}

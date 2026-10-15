import 'dart:convert';

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

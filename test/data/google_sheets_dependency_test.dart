import 'package:csv/csv.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('skips dependent parsers when an upstream table is invalid', () async {
    final tables = <String, List<List<String>>>{};
    for (final entry in <String, String>{
      GoogleSheetsRanges.accounts: 'test_sheets/Accounts.csv',
      GoogleSheetsRanges.categories: 'test_sheets/Categories.csv',
      GoogleSheetsRanges.currencies: 'test_sheets/Currencies.csv',
      GoogleSheetsRanges.dailyAccountBalances:
          'test_sheets/DailyAccountBalances.csv',
      GoogleSheetsRanges.dailyExchangeRates:
          'test_sheets/DailyExchangeRates.csv',
      GoogleSheetsRanges.dailyNetWorth: 'test_sheets/DailyNetWorth.csv',
      GoogleSheetsRanges.dailyManualValuations:
          'test_sheets/DailyManualValuations.csv',
      GoogleSheetsRanges.tags: 'test_sheets/Tags.csv',
      GoogleSheetsRanges.transactions: 'test_sheets/Transactions.csv',
    }.entries) {
      tables[entry.key] = [
        for (final row in csv.decode(await rootBundle.loadString(entry.value)))
          [for (final value in row) value.toString()],
      ];
    }
    tables[GoogleSheetsRanges.accounts]![1][4] = '';

    final repository = GoogleSheetsAppDataRepository(_FakeSheetsClient(tables));
    await expectLater(
      repository.load(),
      throwsA(
        isA<DataValidationFailure>().having(
          (failure) => failure.issues.map((issue) => issue.table).toList(),
          'tables',
          allOf(contains('Accounts'), isNot(contains('Transactions'))),
        ),
      ),
    );
  });
}

class _FakeSheetsClient extends SheetsTableClient {
  _FakeSheetsClient(this.tables);

  final Map<String, List<List<String>>> tables;

  @override
  Future<void> appendRow(String range, List<String> values) async {}

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

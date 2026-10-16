import 'package:csv/csv.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('maps Sheets table ranges into the domain snapshot', () async {
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
      GoogleSheetsRanges.displayPreferences:
          'test_sheets/DisplayPreferences.csv',
      GoogleSheetsRanges.tags: 'test_sheets/Tags.csv',
      GoogleSheetsRanges.transactions: 'test_sheets/Transactions.csv',
    }.entries) {
      tables[entry.key] = [
        for (final row in csv.decode(await rootBundle.loadString(entry.value)))
          [for (final value in row) value.toString()],
      ];
    }

    final client = _FakeSheetsClient(tables);
    final repository = GoogleSheetsAppDataRepository(client);
    final snapshot = await repository.load();

    expect(snapshot.accounts, hasLength(5));
    expect(snapshot.transactions, hasLength(8));
    expect(snapshot.dailyNetWorth, hasLength(3));
    expect(snapshot.dailyManualValuations, hasLength(2));
    expect(snapshot.displayPreferences, hasLength(5 + 14 + 1));
    expect(client.appendedRows, isNotEmpty);
  });

  test('appends a canonical transaction row', () async {
    final client = _FakeSheetsClient({});
    final fixture = await AssetAppDataRepository().load();
    final account = fixture.accountsById['chase_checking']!;
    final usd = fixture.currenciesById['USD']!;
    final transaction = Transaction(
      id: 'sheets-test',
      createdAt: DateTime.utc(2026, 10, 14),
      date: DateTime.utc(2026, 10, 14),
      type: TransactionType.expense,
      sourceAmount: Money.fromMajorUnits(value: '3.25', currency: usd),
      sourceAccountId: account.id,
      destinationAmount: null,
      destinationAccountId: null,
      categoryId: 'dining',
      tagId: 'boston',
      description: 'Sheets test',
    );

    // This verifies the row shape independently of a network call.
    final row = transactionToRow(transaction, fixture.currenciesById, {
      account.id: account.currencyId,
    });

    expect(row['transaction_id'], 'sheets-test');
    expect(row['source_amount'], '3.25');
    expect(row['description'], 'Sheets test');
    expect(client.appendedRows, isEmpty);
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

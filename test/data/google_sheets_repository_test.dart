import 'package:csv/csv.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('maps Sheets table ranges into the domain snapshot', () async {
    final tables = await _fixtureTables();

    final client = _FakeSheetsClient(tables);
    final repository = GoogleSheetsAppDataRepository(client);
    final snapshot = await repository.load();

    expect(snapshot.accounts, hasLength(5));
    expect(snapshot.transactions, hasLength(8));
    expect(snapshot.dailyNetWorth, hasLength(3));
    expect(snapshot.dailyManualValuations, hasLength(2));
    expect(snapshot.displayPreferences, hasLength(5 + 15 + 1));
    expect(client.appendedRows, isNotEmpty);
    await expectLater(
      repository.deleteTransactionTemplate('missing-template'),
      throwsStateError,
    );
    await expectLater(
      repository.updateTransactionTemplate(
        TransactionTemplate(
          id: 'missing-template',
          name: 'Missing',
          type: TransactionType.expense,
          createdAt: DateTime.utc(2026, 10, 20),
          updatedAt: DateTime.utc(2026, 10, 20),
        ),
      ),
      throwsStateError,
    );
  });

  test('validates template rename, update, and delete operations', () async {
    final tables = await _fixtureTables();
    tables[GoogleSheetsRanges.transactionTemplates]!.add([
      'template-1',
      'Existing',
      'expense',
      '',
      'Coffee',
      'food_drink',
      'boston',
      'chase_checking',
      '4.50',
      '',
      '',
      '2026-10-20T00:00:00Z',
      '2026-10-20T00:00:00Z',
    ]);
    tables[GoogleSheetsRanges.transactionTemplates]!.add([
      'template-2',
      'Other',
      'expense',
      '',
      'Lunch',
      'food_drink',
      'boston',
      'chase_checking',
      '5.00',
      '',
      '',
      '2026-10-20T00:00:00Z',
      '2026-10-20T00:00:00Z',
    ]);
    final repository = GoogleSheetsAppDataRepository(_FakeSheetsClient(tables));
    await repository.load();
    final now = DateTime.utc(2026, 10, 20);

    await expectLater(
      repository.addTransactionTemplate(
        TransactionTemplate(
          id: 'template-3',
          name: 'Existing',
          type: TransactionType.expense,
          createdAt: now,
          updatedAt: now,
        ),
      ),
      throwsStateError,
    );
    await expectLater(
      repository.addTransactionTemplate(
        TransactionTemplate(
          id: 'template-3',
          name: ' ',
          type: TransactionType.expense,
          createdAt: now,
          updatedAt: now,
        ),
      ),
      throwsStateError,
    );
    await expectLater(
      repository.updateTransactionTemplate(
        TransactionTemplate(
          id: 'template-1',
          name: '',
          type: TransactionType.expense,
          createdAt: now,
          updatedAt: now,
        ),
      ),
      throwsStateError,
    );
    await expectLater(
      repository.updateTransactionTemplate(
        TransactionTemplate(
          id: 'template-1',
          name: 'Other',
          type: TransactionType.expense,
          createdAt: DateTime.utc(2026, 10, 20),
          updatedAt: DateTime.utc(2026, 10, 20),
        ),
      ),
      throwsStateError,
    );
    await expectLater(
      repository.updateTransactionTemplate(
        TransactionTemplate(
          id: 'template-1',
          name: 'Renamed',
          type: TransactionType.expense,
          createdAt: DateTime.utc(2026, 10, 20),
          updatedAt: DateTime.utc(2026, 10, 20),
        ),
      ),
      completes,
    );
    await expectLater(
      repository.deleteTransactionTemplate('template-2'),
      completes,
    );
    await expectLater(
      repository.addTransactionTemplate(
        TransactionTemplate(
          id: 'template-3',
          name: 'New template',
          type: TransactionType.expense,
          createdAt: now,
          updatedAt: now,
        ),
      ),
      completes,
    );
    await expectLater(
      repository.addManualValuation(
        DailyManualValuation(
          id: 'new-valuation',
          date: DateTime.utc(2026, 10, 15),
          accountId: 'fidelity-401k-2065',
          value: const Money(minorUnits: 100, currencyId: 'USD'),
        ),
      ),
      completes,
    );
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
      categoryId: 'food_drink',
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

  test('returns the added transaction without rereading Sheets', () async {
    final client = _FakeSheetsClient(await _fixtureTables());
    final repository = GoogleSheetsAppDataRepository(client);
    final current = await repository.load();
    final account = current.accountsById['chase_checking']!;
    final transaction = Transaction(
      id: 'immediate-sheets-test',
      createdAt: DateTime.utc(2026, 10, 14),
      date: DateTime.utc(2026, 10, 14),
      type: TransactionType.expense,
      sourceAmount: Money.fromMajorUnits(
        value: '3.25',
        currency: current.currenciesById['USD']!,
      ),
      sourceAccountId: account.id,
      destinationAmount: null,
      destinationAccountId: null,
      categoryId: 'food_drink',
      tagId: 'boston',
      description: 'Immediate reload test',
    );

    final updated = await repository.addTransaction(transaction);

    expect(updated.transactionsById[transaction.id], same(transaction));
    expect(
      client.appendedRows.where((row) => row.first == transaction.id),
      hasLength(1),
    );
  });

  test('reads legacy template sheets without the favorite column', () async {
    final tables = await _fixtureTables();
    final range = GoogleSheetsRanges.transactionTemplates;
    final current = tables[range]!;
    tables[range] = [
      current.first.take(13).toList(),
      [
        'legacy-template',
        'Coffee',
        'expense',
        '',
        'Coffee at {Merchant}',
        'food_drink',
        'boston',
        'chase_checking',
        '4.50',
        '',
        '',
        '2026-10-20T00:00:00Z',
        '2026-10-20T00:00:00Z',
      ],
    ];
    final snapshot = await GoogleSheetsAppDataRepository(
      _FakeSheetsClient(tables),
    ).load();

    expect(snapshot.transactionTemplates.single.name, 'Coffee');
    expect(snapshot.transactionTemplates.single.isFavorite, isFalse);
  });

  test(
    'loads achievements from adjacent ranges and acknowledges them',
    () async {
      final tables = await _fixtureTables();
      tables[GoogleSheetsRanges.achievements] = [
        RuntimeTableSchemas.achievements.headers,
        ['ACH001', 'A fresh start', '-12000', 'FALSE'],
      ];
      tables[GoogleSheetsRanges.achievementSettings] = [
        RuntimeTableSchemas.achievementSettings.headers,
        ['2026-10-01'],
      ];
      final repository = GoogleSheetsAppDataRepository(
        _FakeSheetsClient(tables),
      );

      final loaded = await repository.load();
      expect(loaded.achievementStartDate, DateTime.utc(2026, 10, 1));
      expect(loaded.achievements.single.target.minorUnits, -1200000);
      expect(loaded.achievements.single.earned, isFalse);

      final acknowledged = await repository.updateAchievementEarned(
        'ACH001',
        earned: true,
      );
      expect(acknowledged.achievements.single.earned, isTrue);
      expect(tables[GoogleSheetsRanges.achievements]![1][3], 'TRUE');
    },
  );
}

Future<Map<String, List<List<String>>>> _fixtureTables() async {
  final tables = <String, List<List<String>>>{};
  for (final entry in <String, String>{
    GoogleSheetsRanges.accounts: 'test_sheets/Accounts.csv',
    GoogleSheetsRanges.categories: 'test_sheets/Categories.csv',
    GoogleSheetsRanges.currencies: 'test_sheets/Currencies.csv',
    GoogleSheetsRanges.dailyAccountBalances:
        'test_sheets/DailyAccountBalances.csv',
    GoogleSheetsRanges.dailyExchangeRates: 'test_sheets/DailyExchangeRates.csv',
    GoogleSheetsRanges.dailyNetWorth: 'test_sheets/DailyNetWorth.csv',
    GoogleSheetsRanges.dailyManualValuations:
        'test_sheets/DailyManualValuations.csv',
    GoogleSheetsRanges.displayPreferences: 'test_sheets/DisplayPreferences.csv',
    GoogleSheetsRanges.tags: 'test_sheets/Tags.csv',
    GoogleSheetsRanges.transactionTemplates:
        'test_sheets/TransactionTemplates.csv',
    GoogleSheetsRanges.incomeAllocations: 'test_sheets/IncomeAllocations.csv',
    GoogleSheetsRanges.achievements: 'test_sheets/Achievements.csv',
    GoogleSheetsRanges.achievementSettings:
        'test_sheets/AchievementSettings.csv',
    GoogleSheetsRanges.transactions: 'test_sheets/Transactions.csv',
  }.entries) {
    tables[entry.key] = [
      for (final row in csv.decode(await rootBundle.loadString(entry.value)))
        [for (final value in row) value.toString()],
    ];
  }
  return tables;
}

class _FakeSheetsClient extends SheetsTableClient {
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

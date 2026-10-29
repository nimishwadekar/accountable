import 'dart:math';

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

  test('finalizes migration metadata and migrates a batch only once', () async {
    final tables = await _fixtureTables();
    tables[GoogleSheetsRanges.transactionsToMigrate] = [
      RuntimeTableSchemas.transactionsToMigrate.headers,
      [
        '',
        '2026-10-05',
        'Historical lunch',
        'groceries',
        'expense',
        '5',
        'chase_checking',
        '',
        '',
        '',
        '',
      ],
      [
        '',
        '2026-10-06',
        'Historical dinner',
        'groceries',
        'expense',
        '7',
        'chase_checking',
        '',
        '',
        '',
        '',
      ],
    ];
    final client = _FakeSheetsClient(tables);
    final repository = GoogleSheetsAppDataRepository(
      client,
      migrationAssistance: true,
    );

    final unfinalized = await repository.load();
    expect(unfinalized.transactionsToMigrate.map((item) => item.id), [
      'migration-pending-2',
      'migration-pending-3',
    ]);

    final finalized = await repository.finalizeMigrationTransactions(
      now: DateTime.utc(2026, 10, 29, 12),
      random: Random(12),
    );
    expect(finalized.isFinalized, isTrue);
    expect(finalized.datesStrictlyBeforeOldestMainTransaction, isTrue);
    final migrations = (await repository.load()).transactionsToMigrate;
    expect(RegExp(r'^MIG[A-Z0-9]{6}0001$').hasMatch(migrations[0].id), isTrue);
    expect(RegExp(r'^MIG[A-Z0-9]{6}0002$').hasMatch(migrations[1].id), isTrue);
    expect(migrations[0].id.substring(0, 9), migrations[1].id.substring(0, 9));
    expect(migrations[0].createdAt, DateTime.utc(2026, 10, 29, 12));
    expect(
      migrations[1].createdAt.difference(migrations[0].createdAt),
      const Duration(seconds: 10),
    );
    expect(client.valueRangeUpdateCount, 1);

    await repository.finalizeMigrationTransactions(
      now: DateTime.utc(2030),
      random: Random(99),
    );
    expect(
      (await repository.load()).transactionsToMigrate.map((item) => item.id),
      migrations.map((item) => item.id),
    );
    expect(client.valueRangeUpdateCount, 1);

    final firstMigration = await repository.migrateTransactionsToMain();
    expect(firstMigration.wasAlreadyMigrated, isFalse);
    expect(firstMigration.transactionCount, 2);
    expect(client.rowInsertionCount, 1);
    expect(tables[GoogleSheetsRanges.transactions]![1][0], migrations[0].id);
    expect(tables[GoogleSheetsRanges.transactions]![2][0], migrations[1].id);
    final postMigrationStatus = MigrationBatchStatus.fromSnapshot(
      await repository.reload(),
    );
    expect(
      postMigrationStatus.oldestMainTransactionDate,
      DateTime.utc(2026, 10, 10),
    );
    expect(
      postMigrationStatus.datesStrictlyBeforeOldestMainTransaction,
      isTrue,
    );

    final retry = await repository.migrateTransactionsToMain();
    expect(retry.wasAlreadyMigrated, isTrue);
    expect(client.rowInsertionCount, 1);
  });

  test(
    'flags migration dates that are not strictly before existing history',
    () async {
      final tables = await _fixtureTables();
      tables[GoogleSheetsRanges.transactionsToMigrate] = [
        RuntimeTableSchemas.transactionsToMigrate.headers,
        [
          '',
          '2026-10-10',
          'Historical lunch',
          'groceries',
          'expense',
          '5',
          'chase_checking',
          '',
          '',
          '',
          '',
        ],
      ];
      final repository = GoogleSheetsAppDataRepository(
        _FakeSheetsClient(tables),
        migrationAssistance: true,
      );

      final result = await repository.finalizeMigrationTransactions(
        now: DateTime.utc(2026, 10, 29),
        random: Random(3),
      );

      expect(result.datesStrictlyBeforeOldestMainTransaction, isFalse);
      await repository.migrateTransactionsToMain();
      final afterImport = MigrationBatchStatus.fromSnapshot(
        await repository.reload(),
      );
      expect(afterImport.oldestMainTransactionDate, DateTime.utc(2026, 10, 10));
      expect(afterImport.datesStrictlyBeforeOldestMainTransaction, isFalse);
    },
  );

  test(
    'refuses batches larger than the four-digit migration sequence',
    () async {
      final tables = await _fixtureTables();
      tables[GoogleSheetsRanges.transactionsToMigrate] = [
        RuntimeTableSchemas.transactionsToMigrate.headers,
        for (
          var index = 0;
          index < maximumMigrationTransactionCount + 1;
          index++
        )
          [
            '',
            '2026-10-05',
            'Historical transaction $index',
            'groceries',
            'expense',
            '5',
            'chase_checking',
            '',
            '',
            '',
            '',
          ],
      ];
      final client = _FakeSheetsClient(tables);
      final repository = GoogleSheetsAppDataRepository(
        client,
        migrationAssistance: true,
      );

      await expectLater(
        repository.finalizeMigrationTransactions(),
        throwsA(isA<StateError>()),
      );
      expect(client.valueRangeUpdateCount, 0);
    },
  );

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
    GoogleSheetsRanges.transactionsToMigrate:
        'test_sheets/TransactionsToMigrate.csv',
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
  int valueRangeUpdateCount = 0;
  int rowInsertionCount = 0;

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

  @override
  Future<void> updateRanges(Map<String, List<List<String>>> ranges) async {
    valueRangeUpdateCount++;
    for (final entry in ranges.entries) {
      final match = RegExp(r'^([^!]+)!([A-Z]+)(\d+):[A-Z]+\d+$')
          .firstMatch(entry.key)!;
      final sheetName = match.group(1)!;
      final column = _columnIndex(match.group(2)!);
      final firstRow = int.parse(match.group(3)!) - 1;
      final tableKey = tables.keys.firstWhere(
        (key) => key.startsWith('$sheetName!'),
      );
      final table = tables[tableKey]!;
      for (var index = 0; index < entry.value.length; index++) {
        final row = table[firstRow + index];
        while (row.length <= column) {
          row.add('');
        }
        row[column] = entry.value[index].single;
      }
    }
  }

  @override
  Future<void> insertRowsAndCopyValues({
    required String sourceSheetName,
    required String destinationSheetName,
    required int rowCount,
    required int columnCount,
  }) async {
    rowInsertionCount++;
    final source = tables.entries
        .firstWhere((entry) => entry.key.startsWith('$sourceSheetName!'))
        .value;
    final destinationEntry = tables.entries.firstWhere(
      (entry) => entry.key.startsWith('$destinationSheetName!'),
    );
    final destination = destinationEntry.value;
    final copiedRows = [
      for (final row in source.skip(1).take(rowCount))
        [
          ...row.take(columnCount),
          for (var index = row.length; index < columnCount; index++) '',
        ],
    ];
    destination.insertAll(
      1,
      List.generate(rowCount, (_) => List<String>.filled(columnCount, '')),
    );
    for (var index = 0; index < copiedRows.length; index++) {
      destination[index + 1] = copiedRows[index];
    }
  }

  int _columnIndex(String column) {
    var result = 0;
    for (final codeUnit in column.codeUnits) {
      result = result * 26 + codeUnit - 64;
    }
    return result - 1;
  }
}

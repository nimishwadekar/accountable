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
    await expectLater(
      repository.addTransactionTemplate(
        TransactionTemplate(
          id: 'template-with-missing-account',
          name: 'Broken account reference',
          type: TransactionType.expense,
          sourceAccountId: 'missing-account',
          sourceAmount: const Money(minorUnits: 100, currencyId: 'USD'),
          createdAt: now,
          updatedAt: now,
        ),
      ),
      throwsStateError,
    );
  });

  test('rejects invalid financial writes before sending any rows', () async {
    final client = _FakeSheetsClient(await _fixtureTables());
    final repository = GoogleSheetsAppDataRepository(client);
    final current = await repository.load();
    final appendsBefore = client.appendedRows.length;
    final liability = current.accountsById['hdfc-credila-loan']!;
    final invalidValuation = DailyManualValuation(
      id: 'positive-liability',
      date: DateTime.utc(2026, 10, 20),
      accountId: liability.id,
      value: Money(minorUnits: 100, currencyId: liability.currencyId),
    );
    final invalidTransaction = Transaction(
      id: 'missing-account-transaction',
      createdAt: DateTime.utc(2026, 10, 20),
      date: DateTime.utc(2026, 10, 20),
      type: TransactionType.expense,
      sourceAmount: const Money(minorUnits: 100, currencyId: 'USD'),
      sourceAccountId: 'missing-account',
      destinationAmount: null,
      destinationAccountId: null,
      categoryId: 'food_drink',
      tagId: 'boston',
      description: 'Must not persist',
    );

    await expectLater(
      repository.addManualValuation(invalidValuation),
      throwsStateError,
    );
    await expectLater(
      repository.addTransaction(invalidTransaction),
      throwsStateError,
    );
    expect(client.appendedRows, hasLength(appendsBefore));
  });

  test(
    'saves complete display preferences and refuses an incomplete set',
    () async {
      final tables = await _fixtureTables();
      final client = _FakeSheetsClient(tables);
      final repository = GoogleSheetsAppDataRepository(client);
      final current = await repository.load();
      final checkingPreference = current.displayPreferenceFor(
        'account',
        'chase_checking',
      )!;
      final updatedPreferences = [
        for (final preference in current.displayPreferences)
          preference.entityType == checkingPreference.entityType &&
                  preference.entityId == checkingPreference.entityId
              ? preference.copyWith(showInApp: false, showInEntryForms: false)
              : preference,
      ];

      final saved = await repository.saveDisplayPreferences(updatedPreferences);
      expect(
        saved.displayPreferenceFor('account', 'chase_checking')?.showInApp,
        isFalse,
      );
      expect(tables[GoogleSheetsRanges.displayPreferences]![1][3], 'FALSE');
      await expectLater(
        repository.saveDisplayPreferences(const []),
        throwsStateError,
      );
    },
  );

  test(
    'validates and writes income allocations using the income account currency',
    () async {
      final tables = await _fixtureTables();
      final client = _FakeSheetsClient(tables);
      final repository = GoogleSheetsAppDataRepository(client);
      final current = await repository.load();
      tables[GoogleSheetsRanges.displayPreferences] = [
        RuntimeTableSchemas.displayPreferences.headers,
        for (final preference in current.displayPreferences)
          [
            preference.entityType,
            preference.entityId,
            preference.displayOrder.toString(),
            preference.showInApp.toString().toUpperCase(),
            preference.showInEntryForms.toString().toUpperCase(),
          ],
      ];
      client.appendedRows.clear();
      final now = DateTime.utc(2026, 10, 20);
      IncomeAllocation allocation({
        String id = 'salary-allocation',
        String accountId = 'chase_checking',
        String incomeCategoryId = 'salary',
        String transferCategoryId = 'general',
      }) => IncomeAllocation(
        id: id,
        name: 'Monthly savings',
        incomeCategoryId: incomeCategoryId,
        incomeAccountId: accountId,
        transferCategoryId: transferCategoryId,
        expectedAmountPerIncome: const Money(
          minorUnits: 5025,
          currencyId: 'USD',
        ),
        startDate: now,
        endDate: null,
        createdAt: now,
        updatedAt: now,
      );

      final writesBeforeAllocation = client.appendedRows.length;
      await repository.addIncomeAllocation(allocation());
      expect(client.appendedRows.length, writesBeforeAllocation + 1);
      final appended = client.appendedRows.last;
      expect(appended[5], '50.25');
      expect(appended[6], '2026-10-20');
      expect(appended[7], isEmpty);

      tables[GoogleSheetsRanges.incomeAllocations]!.add(appended);
      await repository.reload();
      await expectLater(
        repository.addIncomeAllocation(allocation()),
        throwsStateError,
      );

      await expectLater(
        repository.addIncomeAllocation(
          allocation(accountId: 'missing-account'),
        ),
        throwsStateError,
      );
      await expectLater(
        repository.addIncomeAllocation(
          allocation(incomeCategoryId: 'food_drink'),
        ),
        throwsStateError,
      );
      expect(client.appendedRows.length, writesBeforeAllocation + 1);
    },
  );

  test(
    'does not import a migration row that conflicts with an existing ID',
    () async {
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
      ];
      final client = _FakeSheetsClient(tables);
      final repository = GoogleSheetsAppDataRepository(
        client,
        migrationAssistance: true,
      );
      await repository.finalizeMigrationTransactions(
        now: DateTime.utc(2026, 10, 29, 12),
        random: Random(3),
      );
      final migrationRow = tables[GoogleSheetsRanges.transactionsToMigrate]![1];
      tables[GoogleSheetsRanges.transactions]!.add([
        migrationRow[0],
        migrationRow[1],
        'Different persisted description',
        migrationRow[3],
        migrationRow[4],
        migrationRow[5],
        migrationRow[6],
        migrationRow[7],
        migrationRow[8],
        migrationRow[9],
        migrationRow[10],
      ]);

      await expectLater(
        repository.migrateTransactionsToMain(),
        throwsStateError,
      );
      expect(client.rowInsertionCount, 0);
    },
  );

  test(
    'requires a finalized complete migration batch before any insertion',
    () async {
      final emptyClient = _FakeSheetsClient(await _fixtureTables());
      final emptyRepository = GoogleSheetsAppDataRepository(
        emptyClient,
        migrationAssistance: true,
      );
      await expectLater(
        emptyRepository.finalizeMigrationTransactions(),
        throwsStateError,
      );
      await expectLater(
        emptyRepository.migrateTransactionsToMain(),
        throwsStateError,
      );

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
      ];
      final pendingClient = _FakeSheetsClient(tables);
      final pendingRepository = GoogleSheetsAppDataRepository(
        pendingClient,
        migrationAssistance: true,
      );
      await expectLater(
        pendingRepository.migrateTransactionsToMain(),
        throwsStateError,
      );
      expect(pendingClient.rowInsertionCount, 0);
      await expectLater(
        GoogleSheetsAppDataRepository(_FakeSheetsClient(await _fixtureTables()))
            .migrateTransactionsToMain(),
        throwsStateError,
      );
    },
  );

  test(
    'partial migration retries do not append a second partial batch',
    () async {
      final tables = await _fixtureTables();
      tables[GoogleSheetsRanges.transactionsToMigrate] = [
        RuntimeTableSchemas.transactionsToMigrate.headers,
        for (var index = 0; index < 2; index++)
          [
            '',
            '2026-10-0${5 + index}',
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
      await repository.finalizeMigrationTransactions(
        now: DateTime.utc(2026, 10, 29),
        random: Random(71),
      );
      final firstMigration =
          tables[GoogleSheetsRanges.transactionsToMigrate]![1];
      tables[GoogleSheetsRanges.transactions]!.add(firstMigration);

      await expectLater(
        repository.migrateTransactionsToMain(),
        throwsStateError,
      );
      expect(client.rowInsertionCount, 0);
    },
  );

  test(
    'production migration ID generation returns a valid finalized batch',
    () async {
      final tables = await _singlePendingMigrationTables();
      final repository = GoogleSheetsAppDataRepository(
        _FakeSheetsClient(tables),
        migrationAssistance: true,
      );

      final status = await repository.finalizeMigrationTransactions(
        now: DateTime.utc(2026, 10, 29, 12),
      );

      expect(status.isFinalized, isTrue);
      expect(status.batchToken, matches(RegExp(r'^[A-Z0-9]{6}$')));
      expect(
        tables[GoogleSheetsRanges.transactionsToMigrate]![1][0],
        matches(RegExp(r'^MIG[A-Z0-9]{6}0001$')),
      );
    },
  );

  test(
    'migration ID collisions retry and exhaustion fails without modifying rows',
    () async {
      final tables = await _singlePendingMigrationTables();
      final collidingTransaction = List<String>.from(
        tables[GoogleSheetsRanges.transactions]![1],
      )..[0] = 'MIG0000000001';
      tables[GoogleSheetsRanges.transactions]!.add(collidingTransaction);
      final client = _FakeSheetsClient(tables);
      final repository = GoogleSheetsAppDataRepository(
        client,
        migrationAssistance: true,
      );
      final sequence = _ScriptedRandom([
        ...List<int>.filled(6, 0),
        ...List<int>.filled(6, 1),
      ]);

      final finalized = await repository.finalizeMigrationTransactions(
        now: DateTime.utc(2026, 10, 29),
        random: sequence,
      );
      expect(finalized.batchToken, '111111');
      expect(
        tables[GoogleSheetsRanges.transactionsToMigrate]![1][0],
        'MIG1111110001',
      );

      final exhaustedTables = await _singlePendingMigrationTables();
      exhaustedTables[GoogleSheetsRanges.transactions]!.add(
        collidingTransaction,
      );
      final exhaustedClient = _FakeSheetsClient(exhaustedTables);
      final exhaustedRepository = GoogleSheetsAppDataRepository(
        exhaustedClient,
        migrationAssistance: true,
      );
      await expectLater(
        exhaustedRepository.finalizeMigrationTransactions(
          now: DateTime.utc(2026, 10, 29),
          random: _ZeroRandom(),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Could not generate a unique migration ID batch.',
          ),
        ),
      );
      expect(
        exhaustedTables[GoogleSheetsRanges.transactionsToMigrate]![1][0],
        isEmpty,
      );
      expect(exhaustedClient.valueRangeUpdateCount, 0);
    },
  );

  test(
    'load reports all row-level finance errors instead of dropping them',
    () async {
      final tables = await _fixtureTables();
      tables[GoogleSheetsRanges.displayPreferences] = [
        RuntimeTableSchemas.displayPreferences.headers,
        ['account', 'chase_checking', '0', 'FALSE', 'TRUE'],
      ];
      tables[GoogleSheetsRanges.transactions]!.add([
        'invalid-row',
        '2026-10-20',
        'Expense with an unknown account',
        'food_drink',
        'expense',
        '10',
        'missing-account',
        '',
        '',
        'boston',
        '2026-10-20T00:00:00Z',
      ]);
      tables[GoogleSheetsRanges.dailyExchangeRates]!.add([
        'bad-rate',
        'not-a-date',
        'USD',
        '1',
        'not-a-date',
        '2026-10-20T00:00:00Z',
      ]);

      await expectLater(
        GoogleSheetsAppDataRepository(_FakeSheetsClient(tables)).load(),
        throwsA(
          isA<DataValidationFailure>().having(
            (failure) => failure.issues.map((issue) => issue.table),
            'tables',
            containsAll([
              'Transactions',
              'DailyExchangeRates',
              'DisplayPreferences',
            ]),
          ),
        ),
      );
    },
  );

  test('Sheets read failures keep a table-level data-load error', () async {
    await expectLater(
      GoogleSheetsAppDataRepository(_ThrowingSheetsClient()).load(),
      throwsA(
        isA<DataLoadException>().having(
          (error) => error.tableName,
          'tableName',
          'Google Sheets',
        ),
      ),
    );
  });

  test(
    'validates each malformed financial table at the repository boundary',
    () async {
      final tablesToCheck = <String, String>{
        GoogleSheetsRanges.currencies: 'Currencies',
        GoogleSheetsRanges.accounts: 'Accounts',
        GoogleSheetsRanges.categories: 'Categories',
        GoogleSheetsRanges.tags: 'Tags',
        GoogleSheetsRanges.displayPreferences: 'DisplayPreferences',
        GoogleSheetsRanges.incomeAllocations: 'IncomeAllocations',
        GoogleSheetsRanges.transactionTemplates: 'TransactionTemplates',
        GoogleSheetsRanges.transactions: 'Transactions',
        GoogleSheetsRanges.transactionsToMigrate: 'TransactionsToMigrate',
        GoogleSheetsRanges.dailyExchangeRates: 'DailyExchangeRates',
        GoogleSheetsRanges.dailyAccountBalances: 'DailyAccountBalances',
        GoogleSheetsRanges.dailyNetWorth: 'DailyNetWorth',
        GoogleSheetsRanges.dailyManualValuations: 'DailyManualValuations',
        GoogleSheetsRanges.achievements: 'Achievements',
        GoogleSheetsRanges.achievementSettings: 'AchievementSettings',
      };

      for (final entry in tablesToCheck.entries) {
        final tables = await _fixtureTables();
        tables[entry.key] = [];
        await expectLater(
          GoogleSheetsAppDataRepository(
            _FakeSheetsClient(tables),
            migrationAssistance:
                entry.key == GoogleSheetsRanges.transactionsToMigrate,
          ).load(),
          throwsA(
            isA<DataValidationFailure>().having(
              (failure) => failure.issues.map((issue) => issue.table),
              'tables',
              contains(entry.value),
            ),
          ),
          reason:
              'An empty ${entry.value} range must not become valid zero data.',
        );
      }
    },
  );

  test(
    'reconciles earned achievement flags only after complete history',
    () async {
      final tables = await _fixtureTables();
      tables[GoogleSheetsRanges.achievements] = [
        RuntimeTableSchemas.achievements.headers,
        ['ACH001', 'First milestone', '5000', 'TRUE'],
      ];
      tables[GoogleSheetsRanges.achievementSettings] = [
        RuntimeTableSchemas.achievementSettings.headers,
        ['2025-01-01'],
      ];
      final historyEnd = DateTime.utc(
        DateTime.now().year,
        DateTime.now().month,
      ).subtract(const Duration(days: 1));
      final dailyHistory = <List<String>>[
        RuntimeTableSchemas.dailyNetWorth.headers,
      ];
      for (
        var date = DateTime.utc(2025, 1, 1);
        !date.isAfter(historyEnd);
        date = date.add(const Duration(days: 1))
      ) {
        final day = _date(date);
        dailyHistory.add([day, day, '0', '2025-02-01T00:00:00Z']);
      }
      tables[GoogleSheetsRanges.dailyNetWorth] = dailyHistory;
      final client = _FakeSheetsClient(tables);

      final snapshot = await GoogleSheetsAppDataRepository(client).load();

      expect(snapshot.achievements.single.earned, isFalse);
      expect(tables[GoogleSheetsRanges.achievements]![1][3], 'FALSE');
    },
  );

  test('normalizes a blank extra column in a Sheets template header', () async {
    final tables = await _fixtureTables();
    tables[GoogleSheetsRanges.transactionTemplates]![0] = [
      ...RuntimeTableSchemas.transactionTemplates.headers.take(
        RuntimeTableSchemas.transactionTemplates.columnCount - 1,
      ),
      '',
    ];

    final snapshot = await GoogleSheetsAppDataRepository(
      _FakeSheetsClient(tables),
    ).load();

    expect(snapshot.transactionTemplates, isEmpty);
  });

  test(
    'rejects duplicate daily dates before changing achievement state',
    () async {
      final tables = await _fixtureTables();
      tables[GoogleSheetsRanges.achievements] = [
        RuntimeTableSchemas.achievements.headers,
        ['ACH001', 'First milestone', '5000', 'TRUE'],
      ];
      tables[GoogleSheetsRanges.achievementSettings] = [
        RuntimeTableSchemas.achievementSettings.headers,
        ['2025-01-01'],
      ];
      tables[GoogleSheetsRanges.dailyNetWorth] = [
        RuntimeTableSchemas.dailyNetWorth.headers,
        ['first', '2025-01-01', '0', '2025-01-02T00:00:00Z'],
        ['second', '2025-01-01', '0', '2025-01-02T00:00:00Z'],
      ];
      final client = _FakeSheetsClient(tables);

      await expectLater(
        GoogleSheetsAppDataRepository(client).load(),
        throwsA(
          isA<DataValidationFailure>().having(
            (failure) => failure.issues,
            'issues',
            contains(
              isA<DataValidationIssue>().having(
                (issue) => issue.message,
                'message',
                contains('more than one snapshot for 2025-01-01'),
              ),
            ),
          ),
        ),
      );
      expect(client.replacedRanges[GoogleSheetsRanges.achievements], isNull);
      expect(tables[GoogleSheetsRanges.achievements]![1][3], 'TRUE');
    },
  );

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
      expect(
        await repository.updateAchievementEarned('ACH001', earned: true),
        same(acknowledged),
      );
      await expectLater(
        repository.updateAchievementEarned('missing-achievement', earned: true),
        throwsStateError,
      );
    },
  );
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

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

Future<Map<String, List<List<String>>>> _singlePendingMigrationTables() async {
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
  ];
  return tables;
}

class _ThrowingSheetsClient extends SheetsTableClient {
  @override
  Future<List<List<String>>> readRange(String range) async =>
      throw StateError('Sheets unavailable');

  @override
  Future<Map<String, List<List<String>>>> batchReadRanges(
    List<String> ranges,
  ) async => throw StateError('Sheets unavailable');

  @override
  Future<void> appendRow(String range, List<String> values) async {}

  @override
  Future<void> replaceRange(String range, List<List<String>> values) async {}
}

class _ScriptedRandom implements Random {
  _ScriptedRandom(this._values);

  final List<int> _values;
  var _index = 0;

  @override
  int nextInt(int max) => _values[_index++] % max;

  @override
  bool nextBool() => nextInt(2) == 1;

  @override
  double nextDouble() => nextInt(1 << 20) / (1 << 20);
}

class _ZeroRandom implements Random {
  @override
  int nextInt(int max) => 0;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}

class _FakeSheetsClient extends SheetsTableClient {
  _FakeSheetsClient(this.tables);

  final Map<String, List<List<String>>> tables;
  final List<List<String>> appendedRows = [];
  final Map<String, List<List<String>>> replacedRanges = {};
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
    replacedRanges[range] = values;
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

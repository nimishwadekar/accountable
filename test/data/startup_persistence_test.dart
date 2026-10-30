import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:accountable/data/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();

  final transaction = Transaction(
    id: 'tx-1',
    createdAt: DateTime.utc(2026, 1, 2, 3, 4),
    date: DateTime.utc(2026, 10, 10),
    type: TransactionType.expense,
    sourceAmount: const Money(minorUnits: 1250, currencyId: 'USD'),
    sourceAccountId: 'chase_checking',
    destinationAmount: null,
    destinationAccountId: null,
    categoryId: 'food_drink',
    tagId: 'boston',
    description: 'Lunch',
  );

  test(
    'form snapshot round trips versioned metadata and only form tables',
    () async {
      final store = MemoryFormSnapshotStore();
      final snapshot = FormSnapshot(
        schemaVersion: FormSnapshot.currentSchemaVersion,
        savedAt: DateTime.utc(2026, 1, 2),
        dataSource: 'sheets',
        tables: {
          for (final table in formSnapshotTableNames) table: '$table csv',
        },
      );
      await store.write(snapshot);

      final loaded = await store.read();
      expect(loaded?.schemaVersion, 1);
      expect(loaded?.savedAt, DateTime.utc(2026, 1, 2));
      expect(loaded?.dataSource, 'sheets');
      expect(loaded?.tables, snapshot.tables);
    },
  );

  test('creates a form snapshot from a data snapshot', () async {
    final data = await AssetAppDataRepository().load();
    final snapshot = FormSnapshot.fromData(
      data,
      dataSource: 'sheets',
      savedAt: DateTime.utc(2026, 1, 2),
    );

    expect(snapshot.tables.keys, containsAll(formSnapshotTableNames));
    expect(snapshot.tables['Accounts'], contains('account_id'));
    expect(snapshot.tables['Currencies'], contains('currency_id'));
    expect(snapshot.tables['TransactionTemplates'], contains('template_id'));
  });

  test(
    'form snapshot round-trips transfer amounts in each account currency',
    () async {
      final source = await AssetAppDataRepository().load();
      final checking = source.accountsById['chase_checking']!;
      final inrAccount = source.accountsById['sbi_nro']!;
      final date = DateTime.utc(2026, 10, 20);
      final template = TransactionTemplate(
        id: 'cross-currency-template',
        name: 'International transfer',
        type: TransactionType.transfer,
        description: 'Monthly transfer',
        categoryId: 'general',
        tagId: 'boston',
        sourceAccountId: checking.id,
        sourceAmount: Money(minorUnits: 12345, currencyId: checking.currencyId),
        destinationAccountId: inrAccount.id,
        destinationAmount: Money(
          minorUnits: 987654,
          currencyId: inrAccount.currencyId,
        ),
        createdAt: date,
        updatedAt: date,
      );
      final data = AppDataSnapshot(
        accounts: source.accounts,
        categories: source.categories,
        currencies: source.currencies,
        tags: source.tags,
        transactions: const [],
        exchangeRates: const [],
        dailyAccountBalances: const [],
        dailyNetWorth: const [],
        dailyManualValuations: const [],
        displayPreferences: source.displayPreferences,
        transactionTemplates: [template],
      );

      final saved = FormSnapshot.fromData(
        data,
        dataSource: 'sheets',
        savedAt: date,
      );
      final restored = saved.toDataSnapshot().transactionTemplates.single;

      expect(restored.sourceAmount?.minorUnits, 12345);
      expect(restored.sourceAmount?.currencyId, 'USD');
      expect(restored.destinationAmount?.minorUnits, 987654);
      expect(restored.destinationAmount?.currencyId, 'INR');
      expect(restored.sourceAccountId, checking.id);
      expect(restored.destinationAccountId, inrAccount.id);
    },
  );

  test('form snapshot rejects invalid metadata, unknown tables, and missing tables', () async {
    final data = await AssetAppDataRepository().load();
    final snapshot = FormSnapshot.fromData(
      data,
      dataSource: 'sheets',
      savedAt: DateTime.utc(2026, 10, 20),
    );
    Map<String, dynamic> jsonCopy() => {
      ...snapshot.toJson(),
      'tables': Map<String, String>.of(snapshot.tables),
    };

    final invalidMetadata = jsonCopy()..['schema_version'] = '1';
    expect(() => FormSnapshot.fromJson(invalidMetadata), throwsFormatException);

    final unknownTable = jsonCopy();
    (unknownTable['tables'] as Map<String, String>)['Transactions'] =
        'private data';
    expect(() => FormSnapshot.fromJson(unknownTable), throwsFormatException);

    final missingTable = jsonCopy();
    (missingTable['tables'] as Map<String, String>).remove('Accounts');
    expect(() => FormSnapshot.fromJson(missingTable), throwsFormatException);
  });

  test('form snapshot preserves template favorite state', () async {
    final source = await AssetAppDataRepository().load();
    final now = DateTime.utc(2026, 10, 20);
    final data = AppDataSnapshot(
      accounts: source.accounts,
      categories: source.categories,
      currencies: source.currencies,
      tags: source.tags,
      transactions: source.transactions,
      transactionsToMigrate: source.transactionsToMigrate,
      exchangeRates: source.exchangeRates,
      dailyAccountBalances: source.dailyAccountBalances,
      dailyNetWorth: source.dailyNetWorth,
      dailyManualValuations: source.dailyManualValuations,
      displayPreferences: source.displayPreferences,
      transactionTemplates: [
        TransactionTemplate(
          id: 'favorite-template',
          name: 'Coffee',
          type: TransactionType.expense,
          description: 'Coffee at {Merchant}',
          isFavorite: true,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      incomeAllocations: source.incomeAllocations,
    );
    final formSnapshot = FormSnapshot.fromData(
      data,
      dataSource: 'sheets',
      savedAt: now,
    );

    expect(
      formSnapshot.tables['TransactionTemplates'],
      contains('is_favorite'),
    );
    expect(formSnapshot.tables['TransactionTemplates'], contains('TRUE'));
    expect(
      formSnapshot.toDataSnapshot().transactionTemplates.single.isFavorite,
      isTrue,
    );
  });

  test(
    'form snapshot refuses a template whose amount has no referenced account',
    () async {
      final source = await AssetAppDataRepository().load();
      final date = DateTime.utc(2026, 10, 20);
      final template = TransactionTemplate(
        id: 'orphan-template',
        name: 'Orphaned account reference',
        type: TransactionType.expense,
        sourceAccountId: 'deleted-account',
        sourceAmount: const Money(minorUnits: 500, currencyId: 'USD'),
        createdAt: date,
        updatedAt: date,
      );
      final data = AppDataSnapshot(
        accounts: source.accounts,
        categories: source.categories,
        currencies: source.currencies,
        tags: source.tags,
        transactions: const [],
        exchangeRates: const [],
        dailyAccountBalances: const [],
        dailyNetWorth: const [],
        dailyManualValuations: const [],
        displayPreferences: source.displayPreferences,
        transactionTemplates: [template],
      );

      expect(
        () => FormSnapshot.fromData(data, dataSource: 'sheets', savedAt: date),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Unknown account: deleted-account.',
          ),
        ),
      );
    },
  );

  test('shared-preferences form snapshot survives and clears', () async {
    final preferences = SharedPreferencesAsync();
    final store = SharedPreferencesFormSnapshotStore(preferences: preferences);
    final data = await AssetAppDataRepository().load();
    final snapshot = FormSnapshot.fromData(
      data,
      dataSource: 'sheets',
      savedAt: DateTime.utc(2026, 1, 2),
    );

    await store.write(snapshot);
    final loaded = await store.read();
    expect(loaded?.tables, snapshot.tables);
    await store.clear();
    expect(await store.read(), isNull);
  });

  test(
    'outbox preserves transaction data and groups entries by batch',
    () async {
      final store = MemoryTransactionOutboxStore();
      await store.enqueueBatch(batchId: 'batch-1', transactions: [transaction]);
      await store.updateBatch(
        'batch-1',
        TransactionOutboxStatus.uncertain,
        lastError: 'network timeout',
      );

      final entries = await store.read();
      expect(entries, hasLength(1));
      expect(entries.single.batchId, 'batch-1');
      expect(entries.single.status, TransactionOutboxStatus.uncertain);
      expect(entries.single.lastError, 'network timeout');
      expect(entries.single.transaction.sourceAmount?.minorUnits, 1250);
      expect(entries.single.transaction.type, TransactionType.expense);

      await store.removeBatch('batch-1');
      expect(await store.read(), isEmpty);
    },
  );

  test(
    'outbox status changes preserve failures and clear them on retry',
    () async {
      final pending = PendingTransaction(
        transaction: transaction,
        batchId: 'retryable-batch',
        createdAt: DateTime.utc(2026, 1, 2),
        lastError: 'timeout after upload',
      );
      final uncertain = pending.copyWith(
        status: TransactionOutboxStatus.uncertain,
      );
      final retried = uncertain.copyWith(
        status: TransactionOutboxStatus.pending,
        clearLastError: true,
      );

      expect(uncertain.status, TransactionOutboxStatus.uncertain);
      expect(uncertain.lastError, 'timeout after upload');
      expect(retried.status, TransactionOutboxStatus.pending);
      expect(retried.lastError, isNull);
      expect(
        () => TransactionOutboxStatus.parse('complete'),
        throwsFormatException,
      );
      expect(
        () => PendingTransaction.fromJson({'status': 'pending'}),
        throwsFormatException,
      );
    },
  );

  test('shared-preferences outbox survives a new store instance', () async {
    final preferences = SharedPreferencesAsync();
    final first = SharedPreferencesTransactionOutboxStore(
      preferences: preferences,
    );
    await first.enqueueBatch(
      batchId: 'persistent-batch',
      transactions: [transaction],
    );

    final second = SharedPreferencesTransactionOutboxStore(
      preferences: SharedPreferencesAsync(),
    );
    final entries = await second.read();

    expect(entries.single.batchId, 'persistent-batch');
    expect(entries.single.transaction.id, transaction.id);
    await second.removeBatch('persistent-batch');
    expect(await first.read(), isEmpty);
  });

  test(
    'shared-preferences outbox persists and clears retry state atomically',
    () async {
      final first = SharedPreferencesTransactionOutboxStore();
      await first.enqueueBatch(
        batchId: 'retry-batch',
        transactions: [transaction],
      );
      await first.updateBatch(
        'retry-batch',
        TransactionOutboxStatus.uncertain,
        lastError: 'verification was inconclusive',
      );

      final second = SharedPreferencesTransactionOutboxStore();
      final uncertain = (await second.read()).single;
      expect(uncertain.transaction.id, transaction.id);
      expect(uncertain.status, TransactionOutboxStatus.uncertain);
      expect(uncertain.lastError, 'verification was inconclusive');

      await second.updateBatch('retry-batch', TransactionOutboxStatus.pending);
      final pending = (await first.read()).single;
      expect(pending.status, TransactionOutboxStatus.pending);
      expect(pending.lastError, isNull);
      await expectLater(
        first.updateBatch('missing-batch', TransactionOutboxStatus.pending),
        throwsStateError,
      );
      await expectLater(
        first.enqueueBatch(batchId: 'empty-batch', transactions: const []),
        throwsArgumentError,
      );
    },
  );

  test(
    'startup repository queues transactions and exposes them locally',
    () async {
      final base = await AssetAppDataRepository().load();
      final repository = StartupDataRepository(
        snapshot: base,
        outbox: MemoryTransactionOutboxStore(),
      );
      expect(await repository.load(), same(base));
      expect(await repository.reload(), same(base));
      final queued = await repository.addTransaction(transaction);

      expect(queued.transactionsById['tx-1'], isNotNull);
      expect((await repository.outbox.read()), hasLength(1));
      expect((await repository.reload()).transactionsById['tx-1'], isNotNull);
    },
  );

  test(
    'startup repository never queues a batch that fails financial validation',
    () async {
      final base = await AssetAppDataRepository().load();
      final outbox = MemoryTransactionOutboxStore();
      final repository = StartupDataRepository(snapshot: base, outbox: outbox);
      final invalid = Transaction(
        id: 'invalid-offline-transaction',
        createdAt: transaction.createdAt,
        date: transaction.date,
        type: TransactionType.expense,
        sourceAmount: transaction.sourceAmount,
        sourceAccountId: 'missing-account',
        destinationAmount: null,
        destinationAccountId: null,
        categoryId: 'food_drink',
        tagId: 'boston',
        description: 'Must not enter the outbox',
      );

      await expectLater(
        repository.addTransactions([invalid]),
        throwsStateError,
      );

      expect(await outbox.read(), isEmpty);
      expect(
        repository.snapshot.transactions,
        hasLength(base.transactions.length),
      );
      expect(
        (await repository.load()).transactionsById.containsKey(
          'invalid-offline-transaction',
        ),
        isFalse,
      );
    },
  );

  test(
    'startup repository blocks unsupported operations while offline',
    () async {
      final base = await AssetAppDataRepository().load();
      final repository = StartupDataRepository(
        snapshot: base,
        outbox: MemoryTransactionOutboxStore(),
      );

      expect(() => repository.addManualValuations([]), throwsStateError);
      expect(
        () => repository.addManualValuation(
          DailyManualValuation(
            id: 'offline-valuation',
            date: DateTime.utc(2026, 10, 10),
            accountId: 'fidelity-401k-2065',
            value: const Money(minorUnits: 100, currencyId: 'USD'),
          ),
        ),
        throwsStateError,
      );
      expect(() => repository.saveDisplayPreferences([]), throwsStateError);
      expect(
        () => repository.addIncomeAllocation(
          IncomeAllocation(
            id: 'allocation-1',
            name: 'Offline allocation',
            incomeCategoryId: 'salary',
            incomeAccountId: 'chase_checking',
            transferCategoryId: 'general',
            expectedAmountPerIncome: const Money(
              minorUnits: 100,
              currencyId: 'USD',
            ),
            startDate: DateTime.utc(2026, 1, 1),
            endDate: null,
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        ),
        throwsStateError,
      );
      final template = TransactionTemplate(
        id: 'offline-template',
        name: 'Offline template',
        type: TransactionType.expense,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      expect(
        () => repository.addTransactionTemplate(template),
        throwsStateError,
      );
      expect(
        () => repository.updateTransactionTemplate(template),
        throwsStateError,
      );
      expect(
        () => repository.deleteTransactionTemplate('offline-template'),
        throwsStateError,
      );
      expect(
        () => repository.updateAchievementEarned('ACH001', earned: true),
        throwsStateError,
      );
    },
  );

  test('outbox rejects duplicate batch IDs to keep enqueue atomic', () async {
    final store = MemoryTransactionOutboxStore();
    await store.enqueueBatch(batchId: 'batch-1', transactions: [transaction]);
    expect(
      () => store.enqueueBatch(batchId: 'batch-1', transactions: [transaction]),
      throwsStateError,
    );
  });
}

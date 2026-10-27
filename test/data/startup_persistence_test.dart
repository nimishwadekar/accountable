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
    'startup repository queues transactions and exposes them locally',
    () async {
      final base = await AssetAppDataRepository().load();
      final repository = StartupDataRepository(
        snapshot: base,
        outbox: MemoryTransactionOutboxStore(),
      );
      final queued = await repository.addTransaction(transaction);

      expect(queued.transactionsById['tx-1'], isNotNull);
      expect((await repository.outbox.read()), hasLength(1));
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

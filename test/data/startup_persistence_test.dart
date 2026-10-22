import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final transaction = Transaction(
    id: 'tx-1',
    createdAt: DateTime.utc(2026, 1, 2, 3, 4),
    date: DateTime.utc(2026, 1, 2),
    type: TransactionType.expense,
    sourceAmount: const Money(minorUnits: 1250, currencyId: 'USD'),
    sourceAccountId: 'chase_checking',
    destinationAmount: null,
    destinationAccountId: null,
    categoryId: 'dining',
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

  test('outbox rejects duplicate batch IDs to keep enqueue atomic', () async {
    final store = MemoryTransactionOutboxStore();
    await store.enqueueBatch(batchId: 'batch-1', transactions: [transaction]);
    expect(
      () => store.enqueueBatch(batchId: 'batch-1', transactions: [transaction]),
      throwsStateError,
    );
  });
}

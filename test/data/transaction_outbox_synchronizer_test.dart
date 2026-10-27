import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'uploads a pending batch once and verifies every row before removal',
    () async {
      final data = await AssetAppDataRepository().load();
      final repository = _MemoryRepository(data);
      final outbox = MemoryTransactionOutboxStore();
      final batch = [
        _transaction(data, id: 'outbox-transfer'),
        _transaction(data, id: 'outbox-fee', description: 'Transfer fee'),
      ];
      await outbox.enqueueBatch(batchId: 'transfer-batch', transactions: batch);

      await TransactionOutboxSynchronizer(outbox: outbox).flush(repository);

      expect(repository.writeCalls, 1);
      expect(repository.writtenBatches.single.map((item) => item.id), [
        'outbox-transfer',
        'outbox-fee',
      ]);
      expect(await outbox.read(), isEmpty);
    },
  );

  test(
    'uncertain batch already present with matching content is acknowledged',
    () async {
      final data = await AssetAppDataRepository().load();
      final transaction = _transaction(data, id: 'already-uploaded');
      final repository = _MemoryRepository(
        withAdditionalTransactions(data, [transaction]),
      );
      final outbox = MemoryTransactionOutboxStore();
      await outbox.enqueueBatch(batchId: 'batch', transactions: [transaction]);
      await outbox.updateBatch('batch', TransactionOutboxStatus.uncertain);

      await TransactionOutboxSynchronizer(outbox: outbox).flush(repository);

      expect(repository.writeCalls, 0);
      expect(await outbox.read(), isEmpty);
    },
  );

  test(
    'uncertain absent batch requires explicit retry before upload',
    () async {
      final data = await AssetAppDataRepository().load();
      final transaction = _transaction(data, id: 'retry-after-check');
      final repository = _MemoryRepository(data);
      final outbox = MemoryTransactionOutboxStore();
      await outbox.enqueueBatch(batchId: 'batch', transactions: [transaction]);
      await outbox.updateBatch(
        'batch',
        TransactionOutboxStatus.uncertain,
        lastError: 'network response lost',
      );
      final synchronizer = TransactionOutboxSynchronizer(outbox: outbox);

      await expectLater(synchronizer.flush(repository), throwsStateError);
      expect(repository.writeCalls, 0);
      expect(
        (await outbox.read()).single.status,
        TransactionOutboxStatus.uncertain,
      );

      await synchronizer.flush(repository, allowUncertainRetry: true);
      expect(repository.writeCalls, 1);
      expect(await outbox.read(), isEmpty);
    },
  );

  test(
    'same ID with different contents stays uncertain and is never overwritten',
    () async {
      final data = await AssetAppDataRepository().load();
      final queued = _transaction(data, id: 'conflict');
      final conflicting = _transaction(
        data,
        id: queued.id,
        description: 'Different source row',
      );
      final repository = _MemoryRepository(
        withAdditionalTransactions(data, [conflicting]),
      );
      final outbox = MemoryTransactionOutboxStore();
      await outbox.enqueueBatch(batchId: 'batch', transactions: [queued]);

      await expectLater(
        TransactionOutboxSynchronizer(outbox: outbox).flush(repository),
        throwsStateError,
      );

      expect(repository.writeCalls, 0);
      expect(
        (await outbox.read()).single.status,
        TransactionOutboxStatus.uncertain,
      );
    },
  );

  test(
    'failed post-upload verification retains the batch for recovery',
    () async {
      final data = await AssetAppDataRepository().load();
      final transaction = _transaction(data, id: 'unconfirmed');
      final repository = _MemoryRepository(data)..persistWrites = false;
      final outbox = MemoryTransactionOutboxStore();
      await outbox.enqueueBatch(batchId: 'batch', transactions: [transaction]);

      await expectLater(
        TransactionOutboxSynchronizer(outbox: outbox).flush(repository),
        throwsStateError,
      );

      expect(
        (await outbox.read()).single.status,
        TransactionOutboxStatus.uncertain,
      );
      expect(
        (await outbox.read()).single.lastError,
        contains('did not confirm'),
      );
    },
  );

  test(
    'an interrupted uploading status is not automatically replayed',
    () async {
      final data = await AssetAppDataRepository().load();
      final transaction = _transaction(data, id: 'interrupted');
      final repository = _MemoryRepository(data);
      final outbox = MemoryTransactionOutboxStore();
      await outbox.enqueueBatch(batchId: 'batch', transactions: [transaction]);
      await outbox.updateBatch('batch', TransactionOutboxStatus.uploading);

      await expectLater(
        TransactionOutboxSynchronizer(outbox: outbox).flush(repository),
        throwsStateError,
      );

      expect(repository.writeCalls, 0);
      expect(
        (await outbox.read()).single.status,
        TransactionOutboxStatus.uncertain,
      );
    },
  );
}

Transaction _transaction(
  AppDataSnapshot data, {
  required String id,
  String description = 'Queued transaction',
}) {
  final account = data.accountsById['chase_checking']!;
  final usd = data.currenciesById[account.currencyId]!;
  return Transaction(
    id: id,
    createdAt: DateTime.utc(2026, 10, 10, 12),
    date: DateTime.utc(2026, 10, 10),
    type: TransactionType.expense,
    sourceAmount: Money.fromMajorUnits(value: '12.34', currency: usd),
    sourceAccountId: account.id,
    destinationAmount: null,
    destinationAccountId: null,
    categoryId: 'food_drink',
    tagId: 'boston',
    description: description,
  );
}

class _MemoryRepository implements AppDataRepository {
  _MemoryRepository(this.snapshot);

  AppDataSnapshot snapshot;
  bool persistWrites = true;
  int writeCalls = 0;
  final List<List<Transaction>> writtenBatches = [];

  @override
  Future<AppDataSnapshot> load() async => snapshot;

  @override
  Future<AppDataSnapshot> reload() async => snapshot;

  @override
  Future<AppDataSnapshot> addTransaction(Transaction transaction) =>
      addTransactions([transaction]);

  @override
  Future<AppDataSnapshot> addTransactions(
    List<Transaction> transactions,
  ) async {
    writeCalls++;
    writtenBatches.add(List.unmodifiable(transactions));
    if (persistWrites) {
      snapshot = withAdditionalTransactions(snapshot, transactions);
    }
    return snapshot;
  }

  @override
  Future<AppDataSnapshot> addManualValuation(DailyManualValuation valuation) =>
      throw UnimplementedError();

  @override
  Future<AppDataSnapshot> addManualValuations(
    List<DailyManualValuation> valuations,
  ) => throw UnimplementedError();

  @override
  Future<AppDataSnapshot> saveDisplayPreferences(
    List<DisplayPreference> preferences,
  ) => throw UnimplementedError();

  @override
  Future<AppDataSnapshot> addIncomeAllocation(IncomeAllocation allocation) =>
      throw UnimplementedError();

  @override
  Future<AppDataSnapshot> addTransactionTemplate(
    TransactionTemplate template,
  ) => throw UnimplementedError();

  @override
  Future<AppDataSnapshot> updateTransactionTemplate(
    TransactionTemplate template,
  ) => throw UnimplementedError();

  @override
  Future<AppDataSnapshot> deleteTransactionTemplate(String templateId) =>
      throw UnimplementedError();
}

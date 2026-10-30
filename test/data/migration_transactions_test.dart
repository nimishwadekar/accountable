import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'classifies exact matches and conflicting imported transaction rows',
    () async {
      final source = await AssetAppDataRepository().load();
      final existing = source.transactions.first;
      final matching = _copyTransaction(existing);
      final conflicting = _copyTransaction(
        existing,
        description: '${existing.description} changed during import',
      );

      final imported = MigrationBatchStatus.fromSnapshot(
        _withMigration(source, [matching]),
      );
      final collision = MigrationBatchStatus.fromSnapshot(
        _withMigration(source, [conflicting]),
      );

      expect(imported.alreadyMigratedCount, 1);
      expect(imported.conflictingMigratedCount, 0);
      expect(imported.isFullyMigrated, isTrue);
      expect(imported.isPartiallyMigrated, isFalse);
      expect(collision.alreadyMigratedCount, 1);
      expect(collision.conflictingMigratedCount, 1);
      expect(collision.isFullyMigrated, isFalse);
      expect(collision.isPartiallyMigrated, isTrue);
    },
  );

  test(
    'only well-formed, ordered IDs with one token form a finalized batch',
    () async {
      final source = await AssetAppDataRepository().load();
      final createdAt = DateTime.utc(2026, 1, 1, 12);
      final first = _migrationTransaction(
        source,
        id: 'MIGABC1230001',
        createdAt: createdAt,
      );
      final second = _migrationTransaction(
        source,
        id: 'MIGABC1230002',
        createdAt: createdAt.add(const Duration(seconds: 10)),
      );

      final finalized = MigrationBatchStatus.fromSnapshot(
        _withMigration(source, [first, second]),
      );
      final badSequence = MigrationBatchStatus.fromSnapshot(
        _withMigration(source, [
          first,
          _migrationTransaction(
            source,
            id: 'MIGABC1230003',
            createdAt: createdAt.add(const Duration(seconds: 10)),
          ),
        ]),
      );
      final mixedToken = MigrationBatchStatus.fromSnapshot(
        _withMigration(source, [
          first,
          _migrationTransaction(
            source,
            id: 'MIGXYZ7890002',
            createdAt: createdAt.add(const Duration(seconds: 10)),
          ),
        ]),
      );
      final badSpacing = MigrationBatchStatus.fromSnapshot(
        _withMigration(source, [
          first,
          _migrationTransaction(
            source,
            id: 'MIGABC1230002',
            createdAt: createdAt.add(const Duration(seconds: 11)),
          ),
        ]),
      );

      expect(finalized.isFinalized, isTrue);
      expect(finalized.batchToken, 'ABC123');
      expect(badSequence.isFinalized, isFalse);
      expect(badSequence.batchToken, isNull);
      expect(mixedToken.isFinalized, isFalse);
      expect(badSpacing.isFinalized, isFalse);
    },
  );

  test('reports migration date ordering and handles an empty batch', () async {
    final source = await AssetAppDataRepository().load();
    final empty = MigrationBatchStatus.fromSnapshot(
      _withMigration(source, const []),
    );
    final migration = MigrationBatchStatus.fromSnapshot(
      _withMigration(source, [
        _migrationTransaction(
          source,
          id: 'pending',
          date: DateTime.utc(2026, 1, 1),
        ),
      ]),
    );

    expect(empty.datesStrictlyBeforeOldestMainTransaction, isNull);
    expect(empty.isFullyMigrated, isFalse);
    expect(empty.isPartiallyMigrated, isFalse);
    expect(migration.latestMigrationDate, DateTime.utc(2026, 1, 1));
    expect(migration.oldestMainTransactionDate, isNotNull);
    expect(migration.datesStrictlyBeforeOldestMainTransaction, isTrue);
  });

  test(
    'history repair errors state that migrated transactions remain saved',
    () {
      final error = MigrationHistoryRepairException(
        StateError('daily history write failed'),
      );

      expect(
        error.toString(),
        'Transactions were migrated, but daily history could not be refreshed: '
        'Bad state: daily history write failed',
      );
    },
  );
}

AppDataSnapshot _withMigration(
  AppDataSnapshot source,
  List<Transaction> transactions,
) => AppDataSnapshot(
  accounts: source.accounts,
  categories: source.categories,
  currencies: source.currencies,
  tags: source.tags,
  transactions: source.transactions,
  transactionsToMigrate: transactions,
  exchangeRates: source.exchangeRates,
  dailyAccountBalances: source.dailyAccountBalances,
  dailyNetWorth: source.dailyNetWorth,
  dailyManualValuations: source.dailyManualValuations,
);

Transaction _copyTransaction(Transaction source, {String? description}) =>
    Transaction(
      id: source.id,
      createdAt: source.createdAt,
      date: source.date,
      type: source.type,
      sourceAmount: source.sourceAmount,
      sourceAccountId: source.sourceAccountId,
      destinationAmount: source.destinationAmount,
      destinationAccountId: source.destinationAccountId,
      categoryId: source.categoryId,
      tagId: source.tagId,
      description: description ?? source.description,
    );

Transaction _migrationTransaction(
  AppDataSnapshot source, {
  required String id,
  DateTime? createdAt,
  DateTime? date,
}) {
  final account = source.accountsById['chase_checking']!;
  final currency = source.currenciesById[account.currencyId]!;
  return Transaction(
    id: id,
    createdAt: createdAt ?? DateTime.utc(2026, 10, 5),
    date: date ?? DateTime.utc(2026, 10, 5),
    type: TransactionType.expense,
    sourceAmount: Money.fromMajorUnits(value: '5', currency: currency),
    sourceAccountId: account.id,
    destinationAmount: null,
    destinationAccountId: null,
    categoryId: 'groceries',
    tagId: 'boston',
    description: 'Migrated expense',
  );
}

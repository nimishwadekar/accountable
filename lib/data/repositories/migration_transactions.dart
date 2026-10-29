import '../app_data_snapshot.dart';
import '../models/models.dart';

const maximumMigrationTransactionCount = 9999;

final _migrationIdPattern = RegExp(r'^MIG([A-Z0-9]{6})(\d{4})$');

class MigrationBatchStatus {
  const MigrationBatchStatus({
    required this.transactionCount,
    required this.isFinalized,
    required this.batchToken,
    required this.latestMigrationDate,
    required this.oldestMainTransactionDate,
    required this.alreadyMigratedCount,
    required this.conflictingMigratedCount,
  });

  final int transactionCount;
  final bool isFinalized;
  final String? batchToken;
  final DateTime? latestMigrationDate;
  final DateTime? oldestMainTransactionDate;
  final int alreadyMigratedCount;
  final int conflictingMigratedCount;

  bool? get datesStrictlyBeforeOldestMainTransaction {
    final oldest = oldestMainTransactionDate;
    final latest = latestMigrationDate;
    if (oldest == null || latest == null) return null;
    return latest.isBefore(oldest);
  }

  bool get isFullyMigrated =>
      transactionCount > 0 &&
      alreadyMigratedCount == transactionCount &&
      conflictingMigratedCount == 0;

  bool get isPartiallyMigrated =>
      (alreadyMigratedCount > 0 && alreadyMigratedCount < transactionCount) ||
      conflictingMigratedCount > 0;

  factory MigrationBatchStatus.fromSnapshot(AppDataSnapshot data) {
    final migration = data.transactionsToMigrate;
    final migrationDates = migration.map(_dateOnly).toList()..sort();
    final currentMigrationIds = migration.map((item) => item.id).toSet();
    final mainDates =
        data.transactions
            .where(
              (transaction) => !currentMigrationIds.contains(transaction.id),
            )
            .map(_dateOnly)
            .toList()
          ..sort();
    var migratedCount = 0;
    var conflictingMigratedCount = 0;
    final accountCurrencies = {
      for (final account in data.accounts) account.id: account.currencyId,
    };
    for (final transaction in migration) {
      final existing = data.transactionsById[transaction.id];
      if (existing == null) continue;
      migratedCount++;
      final expectedRow = transactionToRow(
        transaction,
        data.currenciesById,
        accountCurrencies,
      );
      final existingRow = transactionToRow(
        existing,
        data.currenciesById,
        accountCurrencies,
      );
      if (!expectedRow.keys.every(
        (key) => expectedRow[key] == existingRow[key],
      )) {
        conflictingMigratedCount++;
      }
    }

    String? token;
    var finalized =
        migration.isNotEmpty &&
        migration.length <= maximumMigrationTransactionCount;
    var previousCreatedAt = DateTime.utc(1970);
    for (var index = 0; index < migration.length; index++) {
      final transaction = migration[index];
      final match = _migrationIdPattern.firstMatch(transaction.id);
      if (match == null || int.parse(match.group(2)!) != index + 1) {
        finalized = false;
        break;
      }
      final currentToken = match.group(1)!;
      if (token != null && token != currentToken) {
        finalized = false;
        break;
      }
      if (index > 0 &&
          transaction.createdAt.difference(previousCreatedAt) !=
              const Duration(seconds: 10)) {
        finalized = false;
        break;
      }
      token = currentToken;
      previousCreatedAt = transaction.createdAt;
    }

    return MigrationBatchStatus(
      transactionCount: migration.length,
      isFinalized: finalized,
      batchToken: finalized ? token : null,
      latestMigrationDate: migrationDates.isEmpty ? null : migrationDates.last,
      oldestMainTransactionDate: mainDates.isEmpty ? null : mainDates.first,
      alreadyMigratedCount: migratedCount,
      conflictingMigratedCount: conflictingMigratedCount,
    );
  }
}

class MigrationExecutionResult {
  const MigrationExecutionResult({
    required this.transactionCount,
    required this.wasAlreadyMigrated,
  });

  final int transactionCount;
  final bool wasAlreadyMigrated;
}

class MigrationHistoryRepairException implements Exception {
  const MigrationHistoryRepairException(this.cause);

  final Object cause;

  @override
  String toString() =>
      'Transactions were migrated, but daily history could not be refreshed: '
      '$cause';
}

DateTime _dateOnly(Transaction transaction) => DateTime.utc(
  transaction.date.year,
  transaction.date.month,
  transaction.date.day,
);

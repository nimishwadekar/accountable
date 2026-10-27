import '../app_data_snapshot.dart';
import '../models/models.dart';
import '../sources/transaction_outbox_store.dart';
import '../sources/transaction_write_coordinator.dart';
import 'repositories.dart';

/// Verifies durable queued transactions before removing or retrying a batch.
class TransactionOutboxSynchronizer {
  const TransactionOutboxSynchronizer({
    required this.outbox,
    this.writeCoordinator = const TransactionWriteCoordinator(),
  });

  final TransactionOutboxStore outbox;
  final TransactionWriteCoordinator writeCoordinator;

  Future<void> flush(
    AppDataRepository repository, {
    bool allowUncertainRetry = false,
  }) => writeCoordinator.run(() async {
    final pending = await outbox.read();
    final batches = <String, List<Transaction>>{};
    final statusByBatch = <String, TransactionOutboxStatus>{};
    for (final item in pending) {
      batches.putIfAbsent(item.batchId, () => []).add(item.transaction);
      statusByBatch[item.batchId] = item.status;
    }
    for (final entry in batches.entries) {
      var status = statusByBatch[entry.key] ?? TransactionOutboxStatus.pending;
      if (status == TransactionOutboxStatus.uploading) {
        status = TransactionOutboxStatus.uncertain;
        await outbox.updateBatch(
          entry.key,
          status,
          lastError: 'An earlier upload was interrupted; verifying Sheets before retry.',
        );
      }
      try {
        final current = await repository.reload();
        final missing = <Transaction>[];
        for (final transaction in entry.value) {
          final existing = current.transactionsById[transaction.id];
          if (existing == null) {
            missing.add(transaction);
          } else if (!_sameTransaction(existing, transaction, current)) {
            throw StateError(
              'Transaction ID ${transaction.id} exists in Sheets with different contents. '
              'The pending batch was retained for manual review.',
            );
          }
        }
        if (missing.isNotEmpty &&
            (status == TransactionOutboxStatus.uncertain ||
                status == TransactionOutboxStatus.failed) &&
            !allowUncertainRetry) {
          throw StateError(
            'The pending batch is not present in Sheets. Verify the data, then choose Retry upload.',
          );
        }
        if (missing.isNotEmpty) {
          await outbox.updateBatch(
            entry.key,
            TransactionOutboxStatus.uploading,
            lastError: null,
          );
          await repository.addTransactions(missing);
          final verified = await repository.reload();
          for (final transaction in entry.value) {
            final existing = verified.transactionsById[transaction.id];
            if (existing == null ||
                !_sameTransaction(existing, transaction, verified)) {
              throw StateError(
                'Sheets did not confirm transaction ${transaction.id} after upload.',
              );
            }
          }
        }
        await outbox.removeBatch(entry.key);
      } catch (error) {
        await outbox.updateBatch(
          entry.key,
          TransactionOutboxStatus.uncertain,
          lastError: error.toString(),
        );
        rethrow;
      }
    }
  });

  bool _sameTransaction(
    Transaction first,
    Transaction second,
    AppDataSnapshot data,
  ) {
    final accountCurrencies = {
      for (final account in data.accounts) account.id: account.currencyId,
    };
    final firstRow = transactionToRow(
      first,
      data.currenciesById,
      accountCurrencies,
    );
    final secondRow = transactionToRow(
      second,
      data.currenciesById,
      accountCurrencies,
    );
    return firstRow.length == secondRow.length &&
        firstRow.entries.every((entry) => secondRow[entry.key] == entry.value);
  }
}

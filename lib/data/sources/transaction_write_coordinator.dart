import 'transaction_write_coordinator_stub.dart'
    if (dart.library.js_interop) 'transaction_write_coordinator_web.dart'
    as platform;

/// Serializes writes made by this app across tabs on the same browser origin.
class TransactionWriteCoordinator {
  const TransactionWriteCoordinator();

  Future<T> run<T>(Future<T> Function() operation) =>
      platform.runWithTransactionWriteLock(operation);
}

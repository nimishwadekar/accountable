import '../app_data_snapshot.dart';
import '../models/models.dart';
import '../sources/transaction_outbox_store.dart';
import '../sources/transaction_write_coordinator.dart';
import 'repositories.dart';
import 'transaction_write_validator.dart';

class StartupDataRepository implements AppDataRepository {
  StartupDataRepository({
    required this.snapshot,
    required this.outbox,
    this.writeCoordinator = const TransactionWriteCoordinator(),
  });

  AppDataSnapshot snapshot;
  final TransactionOutboxStore outbox;
  final TransactionWriteCoordinator writeCoordinator;

  @override
  Future<AppDataSnapshot> load() async => snapshot;

  @override
  Future<AppDataSnapshot> reload() async => snapshot;

  @override
  Future<AppDataSnapshot> addTransaction(Transaction transaction) =>
      addTransactions([transaction]);

  @override
  Future<AppDataSnapshot> addTransactions(List<Transaction> transactions) =>
      writeCoordinator.run(() async {
        final errors = validateTransactionsForWrite(transactions, snapshot);
        if (errors.isNotEmpty) throw StateError(errors.join(' '));
        final batchId = 'startup-${DateTime.now().microsecondsSinceEpoch}';
        await outbox.enqueueBatch(batchId: batchId, transactions: transactions);
        snapshot = withAdditionalTransactions(snapshot, transactions);
        return snapshot;
      });

  @override
  Future<AppDataSnapshot> addManualValuation(DailyManualValuation valuation) =>
      throw StateError('Manual valuations are unavailable during startup.');

  @override
  Future<AppDataSnapshot> addManualValuations(
    List<DailyManualValuation> valuations,
  ) => throw StateError('Manual valuations are unavailable during startup.');

  @override
  Future<AppDataSnapshot> saveDisplayPreferences(
    List<DisplayPreference> preferences,
  ) => throw StateError('Settings are unavailable during startup.');

  @override
  Future<AppDataSnapshot> addIncomeAllocation(IncomeAllocation allocation) =>
      throw StateError('Analysis is unavailable during startup.');

  @override
  Future<AppDataSnapshot> addTransactionTemplate(
    TransactionTemplate template,
  ) => throw StateError('Settings are unavailable during startup.');

  @override
  Future<AppDataSnapshot> updateTransactionTemplate(
    TransactionTemplate template,
  ) => throw StateError('Settings are unavailable during startup.');

  @override
  Future<AppDataSnapshot> deleteTransactionTemplate(String templateId) =>
      throw StateError('Settings are unavailable during startup.');
}

AppDataSnapshot withAdditionalTransactions(
  AppDataSnapshot data,
  List<Transaction> additional,
) => AppDataSnapshot(
  accounts: data.accounts,
  categories: data.categories,
  currencies: data.currencies,
  tags: data.tags,
  transactions: [...data.transactions, ...additional],
  transactionsToMigrate: data.transactionsToMigrate,
  exchangeRates: data.exchangeRates,
  dailyAccountBalances: data.dailyAccountBalances,
  dailyNetWorth: data.dailyNetWorth,
  dailyManualValuations: data.dailyManualValuations,
  displayPreferences: data.displayPreferences,
  transactionTemplates: data.transactionTemplates,
  incomeAllocations: data.incomeAllocations,
);

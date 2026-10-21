import 'package:accountable/data/data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('adds a transaction to the local dataset and reloads it', () async {
    final store = MemoryLocalDatasetStore();
    final repository = AssetAppDataRepository(store: store);
    final initial = await repository.load();
    final checking = initial.accountsById['chase_checking']!;
    final usd = initial.currenciesById[checking.currencyId]!;

    final transaction = Transaction(
      id: 'local-test-transaction',
      createdAt: DateTime.utc(2026, 10, 14, 3),
      date: DateTime.utc(2026, 10, 14),
      type: TransactionType.expense,
      sourceAmount: Money.fromMajorUnits(value: '12.34', currency: usd),
      sourceAccountId: checking.id,
      destinationAmount: null,
      destinationAccountId: null,
      categoryId: 'dining',
      tagId: 'boston',
      description: 'Test entry',
    );

    final updated = await repository.addTransaction(transaction);
    final reloaded = await repository.reload();

    expect(updated.transactionsById['local-test-transaction'], isNotNull);
    expect(reloaded.transactions, hasLength(initial.transactions.length + 1));
    expect(
      reloaded.transactionsById['local-test-transaction']?.description,
      'Test entry',
    );
  });

  test('asset repository remains read-only without a store', () async {
    final repository = AssetAppDataRepository();
    final data = await repository.load();
    final account = data.accountsById['chase_checking']!;
    final currency = data.currenciesById[account.currencyId]!;

    final transaction = Transaction(
      id: 'read-only-test',
      createdAt: DateTime.utc(2026, 10, 14),
      date: DateTime.utc(2026, 10, 14),
      type: TransactionType.expense,
      sourceAmount: Money.fromMajorUnits(value: '1', currency: currency),
      sourceAccountId: account.id,
      destinationAmount: null,
      destinationAccountId: null,
      categoryId: 'dining',
      tagId: 'boston',
      description: 'Read-only',
    );

    await expectLater(repository.addTransaction(transaction), throwsStateError);
  });
}

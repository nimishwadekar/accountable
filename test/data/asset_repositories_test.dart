import 'package:csv/csv.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('typed asset repositories load their own financial tables', () async {
    const reader = FlutterAssetReader();
    final currencies = await const AssetCurrencyRepository(reader).load();
    final currencyById = {for (final item in currencies) item.id: item};
    final accounts = await const AssetAccountRepository(reader)
        .load(currencies: currencyById);
    final accountById = {for (final item in accounts) item.id: item};
    final categories = await const AssetCategoryRepository(reader).load();
    final tags = await const AssetTagRepository(reader).load();
    final transactions = await const AssetTransactionRepository(reader)
        .load(accounts: accountById, currencies: currencyById);
    final rates = await const AssetExchangeRateRepository(reader).load();
    final balances = await const AssetDailyAccountBalanceRepository(reader)
        .load(accounts: accountById, currencies: currencyById);
    final valuations = await const AssetManualValuationRepository(reader)
        .load(accounts: accountById, currencies: currencyById);
    final netWorth = await const AssetDailyNetWorthRepository(reader)
        .load(currencies: currencyById);

    expect(currencies, hasLength(2));
    expect(accounts, hasLength(5));
    expect(categories, hasLength(15));
    expect(tags, hasLength(1));
    expect(transactions, hasLength(8));
    expect(rates, hasLength(6));
    expect(balances, hasLength(8));
    expect(valuations, hasLength(2));
    expect(netWorth, hasLength(3));
  });

  test('table loaders preserve table context when parsing fails', () async {
    const reader = _ThrowingAssetReader();

    await expectLater(
      const AssetManualValuationRepository(reader)
          .load(accounts: const {}, currencies: const {}),
      throwsA(
        isA<DataLoadException>().having(
          (error) => error.tableName,
          'tableName',
          'DailyManualValuations',
        ),
      ),
    );
  });

  test(
    'local transaction batches append valid rows and reject duplicate IDs',
    () async {
      final store = MemoryLocalDatasetStore();
      final repository = AssetAppDataRepository(store: store);
      final current = await repository.load();
      final checking = current.accountsById['chase_checking']!;
      final usd = current.currenciesById['USD']!;
      final transaction = Transaction(
        id: 'asset-repository-append',
        createdAt: DateTime.utc(2026, 10, 20),
        date: DateTime.utc(2026, 10, 20),
        type: TransactionType.expense,
        sourceAmount: Money.fromMajorUnits(value: '14.25', currency: usd),
        sourceAccountId: checking.id,
        destinationAmount: null,
        destinationAccountId: null,
        categoryId: 'food_drink',
        tagId: 'boston',
        description: 'Repository round trip',
      );

      final saved = await repository.addTransactions([transaction]);
      expect(
        saved.transactionsById[transaction.id]?.sourceAmount?.minorUnits,
        1425,
      );
      await expectLater(
        repository.addTransaction(transaction),
        throwsStateError,
      );
      final storedTransactions = csv.decode(
        (await store.read())![DataAssetPaths.transactions]!,
      );
      expect(
        storedTransactions.where((row) => row.first == transaction.id),
        hasLength(1),
      );
    },
  );

  test(
    'manual valuation saves preserve signed minor units and reject duplicates',
    () async {
      final store = MemoryLocalDatasetStore();
      final repository = AssetAppDataRepository(store: store);
      final current = await repository.load();
      final account = current.accountsById['hdfc-credila-loan']!;
      final inr = current.currenciesById['INR']!;
      final valuation = DailyManualValuation(
        id: 'repository-loan-valuation',
        date: DateTime.utc(2026, 10, 20),
        accountId: account.id,
        value: Money.fromMajorUnits(value: '-250.50', currency: inr),
      );

      final saved = await repository.addManualValuation(valuation);
      expect(
        saved.dailyManualValuationsById[valuation.id]?.value.minorUnits,
        -25050,
      );
      final table = (await store
          .read())![DataAssetPaths.dailyManualValuations]!;
      expect(table, contains('-250.5'));

      final duplicateDate = DailyManualValuation(
        id: 'another-id-same-date',
        date: valuation.date,
        accountId: valuation.accountId,
        value: valuation.value,
      );
      await expectLater(
        repository.addManualValuation(duplicateDate),
        throwsStateError,
      );
      expect(
        (await store.read())![DataAssetPaths.dailyManualValuations],
        table,
      );
    },
  );

  test(
    'display preference save requires a complete set and persists visibility',
    () async {
      final store = MemoryLocalDatasetStore();
      final repository = AssetAppDataRepository(store: store);
      final current = await repository.load();

      await expectLater(
        repository.saveDisplayPreferences(const []),
        throwsStateError,
      );
      final changed = [
        for (final preference in current.displayPreferences)
          preference.entityType == 'account' &&
                  preference.entityId == 'chase_checking'
              ? preference.copyWith(showInApp: false, showInEntryForms: false)
              : preference,
      ];
      final saved = await repository.saveDisplayPreferences(changed);

      expect(
        saved.displayPreferenceFor('account', 'chase_checking')?.showInApp,
        isFalse,
      );
      expect(
        saved
            .displayPreferenceFor('account', 'chase_checking')
            ?.showInEntryForms,
        isFalse,
      );
      expect(
        csv
            .decode((await store.read())![DataAssetPaths.displayPreferences]!)
            .skip(1)
            .where((row) => row[0] == 'account' && row[1] == 'chase_checking')
            .single[3],
        'FALSE',
      );
    },
  );

  test(
    'local template updates preserve currencies and enforce unique names',
    () async {
      final store = MemoryLocalDatasetStore();
      final repository = AssetAppDataRepository(store: store);
      final current = await repository.load();
      final checking = current.accountsById['chase_checking']!;
      final inrAccount = current.accountsById['sbi_nro']!;
      final now = DateTime.utc(2026, 10, 20);
      final template = TransactionTemplate(
        id: 'cross-currency-local-template',
        name: 'International transfer',
        type: TransactionType.transfer,
        sourceAccountId: checking.id,
        sourceAmount: Money(minorUnits: 1234, currencyId: checking.currencyId),
        destinationAccountId: inrAccount.id,
        destinationAmount: Money(
          minorUnits: 5678,
          currencyId: inrAccount.currencyId,
        ),
        createdAt: now,
        updatedAt: now,
      );

      final added = await repository.addTransactionTemplate(template);
      expect(
        added
            .transactionTemplatesById[template.id]
            ?.destinationAmount
            ?.minorUnits,
        5678,
      );
      await expectLater(
        repository.addTransactionTemplate(
          TransactionTemplate(
            id: 'duplicate-name',
            name: ' international transfer ',
            type: TransactionType.transfer,
            createdAt: now,
            updatedAt: now,
          ),
        ),
        throwsStateError,
      );
      await expectLater(
        repository.addTransactionTemplate(template),
        throwsStateError,
      );
      await expectLater(
        repository.updateTransactionTemplate(
          TransactionTemplate(
            id: 'missing-template',
            name: 'Missing template',
            type: TransactionType.expense,
            createdAt: now,
            updatedAt: now,
          ),
        ),
        throwsStateError,
      );

      final updated = await repository.updateTransactionTemplate(
        template.copyWith(name: 'Updated transfer', isFavorite: true),
      );
      expect(updated.transactionTemplatesById[template.id]?.isFavorite, isTrue);
      expect(
        csv
            .decode((await store.read())![DataAssetPaths.transactionTemplates]!)
            .last[10],
        '56.78',
      );
      final deleted = await repository.deleteTransactionTemplate(template.id);
      expect(
        deleted.transactionTemplatesById.containsKey(template.id),
        isFalse,
      );
      await expectLater(
        repository.deleteTransactionTemplate(template.id),
        throwsStateError,
      );
    },
  );

  test('asset mode explicitly rejects unsupported allocation writes', () async {
    final repository = AssetAppDataRepository(store: MemoryLocalDatasetStore());
    await repository.load();

    expect(
      () => repository.addIncomeAllocation(
        IncomeAllocation(
          id: 'local-allocation',
          name: 'Allocation',
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
  });

  test(
    'migration assistance reads the separate migration source table',
    () async {
      final snapshot = await AssetAppDataRepository(migrationAssistance: true)
          .load();

      expect(snapshot.transactionsToMigrate, isEmpty);
    },
  );

  test(
    'complete history resets and persists a stale earned milestone',
    () async {
      final tables = <String, String>{
        for (final schema in RuntimeTableSchemas.all)
          schema.assetPath: await rootBundle.loadString(schema.assetPath),
      };
      tables[DataAssetPaths.achievements] = csv.encode([
        RuntimeTableSchemas.achievements.headers,
        ['ACH001', 'First milestone', '5000', 'TRUE'],
      ]);
      tables[DataAssetPaths.achievementSettings] = csv.encode([
        RuntimeTableSchemas.achievementSettings.headers,
        ['2025-01-01'],
      ]);
      final historyEnd = DateTime.utc(
        DateTime.now().year,
        DateTime.now().month,
      ).subtract(const Duration(days: 1));
      final historyDates = <DateTime>[];
      for (
        var date = DateTime.utc(2025, 1, 1);
        !date.isAfter(historyEnd);
        date = date.add(const Duration(days: 1))
      ) {
        historyDates.add(date);
      }
      tables[DataAssetPaths.dailyNetWorth] = csv.encode([
        RuntimeTableSchemas.dailyNetWorth.headers,
        for (final date in historyDates)
          [
            '${date.year}-${date.month.toString().padLeft(2, '0')}-'
                '${date.day.toString().padLeft(2, '0')}-net',
            '${date.year}-${date.month.toString().padLeft(2, '0')}-'
                '${date.day.toString().padLeft(2, '0')}',
            '0',
            '2025-02-01T00:00:00Z',
          ],
      ]);
      final store = MemoryLocalDatasetStore(tables);

      final snapshot = await AssetAppDataRepository(store: store).load();

      expect(snapshot.achievements.single.earned, isFalse);
      expect(
        csv
            .decode((await store.read())![DataAssetPaths.achievements]!)
            .last
            .last,
        'FALSE',
      );
    },
  );

  test(
    'a saved template cannot serialize an amount for a missing account',
    () async {
      final store = MemoryLocalDatasetStore();
      final repository = AssetAppDataRepository(store: store);
      await repository.load();
      final now = DateTime.utc(2026, 10, 20);
      final template = TransactionTemplate(
        id: 'orphan-template',
        name: 'Orphaned account reference',
        type: TransactionType.expense,
        sourceAccountId: 'deleted-account',
        sourceAmount: const Money(minorUnits: 500, currencyId: 'USD'),
        createdAt: now,
        updatedAt: now,
      );

      await expectLater(
        repository.addTransactionTemplate(template),
        throwsStateError,
      );
      expect(
        (await store.read())![DataAssetPaths.transactionTemplates],
        contains('template_id'),
      );
      expect(
        (await store.read())![DataAssetPaths.transactionTemplates],
        isNot(contains('orphan-template')),
      );
    },
  );

  test('achievement writes distinguish no-op, missing IDs, and missing stored rows', () async {
    final tables = <String, String>{
      for (final schema in RuntimeTableSchemas.all)
        schema.assetPath: await rootBundle.loadString(schema.assetPath),
    };
    tables[DataAssetPaths.achievements] = csv.encode([
      RuntimeTableSchemas.achievements.headers,
      ['ACH001', 'First milestone', '1000', 'FALSE'],
    ]);
    final store = MemoryLocalDatasetStore(tables);
    final repository = AssetAppDataRepository(store: store);
    final loaded = await repository.load();

    expect(
      await repository.updateAchievementEarned('ACH001', earned: false),
      same(loaded),
    );
    await expectLater(
      repository.updateAchievementEarned('missing-achievement', earned: true),
      throwsStateError,
    );

    final stored = Map<String, String>.from((await store.read())!);
    stored[DataAssetPaths.achievements] = csv.encode([
      RuntimeTableSchemas.achievements.headers,
    ]);
    await store.write(stored);
    await expectLater(
      repository.updateAchievementEarned('ACH001', earned: true),
      throwsStateError,
    );
  });

  test(
    'rejects duplicate daily dates as a dataset validation failure',
    () async {
      final tables = <String, String>{
        for (final schema in RuntimeTableSchemas.all)
          schema.assetPath: await rootBundle.loadString(schema.assetPath),
      };
      tables[DataAssetPaths.achievementSettings] = csv.encode([
        RuntimeTableSchemas.achievementSettings.headers,
        ['2025-01-01'],
      ]);
      tables[DataAssetPaths.dailyNetWorth] = csv.encode([
        RuntimeTableSchemas.dailyNetWorth.headers,
        ['first', '2025-01-01', '10', '2025-01-02T00:00:00Z'],
        ['second', '2025-01-01', '10', '2025-01-02T00:00:00Z'],
      ]);

      await expectLater(
        AssetAppDataRepository(store: MemoryLocalDatasetStore(tables)).load(),
        throwsA(
          isA<DataValidationFailure>().having(
            (failure) => failure.issues,
            'issues',
            contains(
              isA<DataValidationIssue>().having(
                (issue) => issue.message,
                'message',
                contains('more than one snapshot for 2025-01-01'),
              ),
            ),
          ),
        ),
      );
    },
  );

  test('wraps corrupt cached CSV with a dataset validation issue', () async {
    final tables = <String, String>{
      for (final schema in RuntimeTableSchemas.all)
        schema.assetPath: await rootBundle.loadString(schema.assetPath),
    };
    tables[DataAssetPaths.currencies] =
        'currency_id,currency_symbol,decimal_places\nUSD,\$,not-a-number';

    await expectLater(
      AssetAppDataRepository(store: MemoryLocalDatasetStore(tables)).load(),
      throwsA(
        isA<DataValidationFailure>().having(
          (failure) => failure.issues.single.table,
          'table',
          'Local dataset',
        ),
      ),
    );
  });
}

class _ThrowingAssetReader implements AssetReader {
  const _ThrowingAssetReader();

  @override
  Future<String> readString(String assetPath) async =>
      throw const FormatException('Invalid CSV');
}

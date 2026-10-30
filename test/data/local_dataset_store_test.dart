import 'package:csv/csv.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:accountable/data/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('memory dataset store copies values', () async {
    final store = MemoryLocalDatasetStore({'table': 'initial'});
    final first = await store.read();
    expect(first?['table'], 'initial');

    await store.write({'table': 'updated'});
    expect((await store.read())?['table'], 'updated');
  });

  test(
    'shared-preferences dataset survives a new store and isolates reads',
    () async {
      final first = SharedPreferencesLocalDatasetStore();
      await first.write({
        'Transactions': 'transaction_id,amount\ntx-1,12.34',
        'Accounts': 'account_id,currency\nchecking,USD',
      });

      final second = SharedPreferencesLocalDatasetStore();
      final loaded = await second.read();
      expect(loaded, {
        'Transactions': 'transaction_id,amount\ntx-1,12.34',
        'Accounts': 'account_id,currency\nchecking,USD',
      });

      loaded!['Transactions'] = 'corrupted by caller';
      expect((await first.read())!['Transactions'], contains('tx-1,12.34'));
    },
  );

  test('shared-preferences dataset rejects corrupt non-object JSON', () async {
    final preferences = SharedPreferencesAsync();
    await preferences.setString('accountable.local_dataset', '[]');
    final store = SharedPreferencesLocalDatasetStore();

    await expectLater(store.read(), throwsFormatException);
  });

  test('does not rewrite an unchanged local dataset during reload', () async {
    final store = _CountingDatasetStore();
    final repository = AssetAppDataRepository(store: store);
    await repository.load();
    final writesAfterInitialization = store.writeCount;
    expect(writesAfterInitialization, greaterThan(0));

    await repository.reload();

    expect(store.writeCount, writesAfterInitialization);
  });

  test('migrates local template rows and persists favorite changes', () async {
    final tables = <String, String>{
      for (final schema in RuntimeTableSchemas.all)
        schema.assetPath: await rootBundle.loadString(schema.assetPath),
    };
    final templatePath = DataAssetPaths.transactionTemplates;
    final oldTemplateRows = csv.decode(tables[templatePath]!);
    tables[templatePath] = csv.encode([
      oldTemplateRows.first.take(13).toList(),
      [
        'legacy-template',
        'Coffee',
        'expense',
        '',
        'Coffee at {Merchant}',
        'food_drink',
        'boston',
        'chase_checking',
        '4.50',
        '',
        '',
        '2026-10-20T00:00:00Z',
        '2026-10-20T00:00:00Z',
      ],
    ]);
    final store = MemoryLocalDatasetStore(tables);
    final repository = AssetAppDataRepository(store: store);

    final loaded = await repository.load();
    expect(loaded.transactions, hasLength(8));
    expect(loaded.transactionTemplates.single.isFavorite, isFalse);
    expect(
      csv.decode((await store.read())![templatePath]!).first.last,
      'is_favorite',
    );

    final updated = await repository.updateTransactionTemplate(
      loaded.transactionTemplates.single.copyWith(isFavorite: true),
    );
    expect(updated.transactionTemplates.single.isFavorite, isTrue);
  });

  test(
    'adds achievement fixtures when migrating an older local dataset',
    () async {
      final oldTables = <String, String>{
        for (final schema in RuntimeTableSchemas.all)
          if (schema != RuntimeTableSchemas.achievements &&
              schema != RuntimeTableSchemas.achievementSettings)
            schema.assetPath: await rootBundle.loadString(schema.assetPath),
      };
      final store = MemoryLocalDatasetStore(oldTables);
      final repository = AssetAppDataRepository(store: store);

      final loaded = await repository.load();
      expect(loaded.transactions, hasLength(8));
      expect(loaded.achievements, isEmpty);
      expect(loaded.achievementStartDate, DateTime.utc(2026, 10, 1));
      expect(
        (await store.read())!.containsKey(DataAssetPaths.achievements),
        isTrue,
      );
    },
  );

  test('persists achievement acknowledgement in local storage', () async {
    final tables = <String, String>{
      for (final schema in RuntimeTableSchemas.all)
        schema.assetPath: await rootBundle.loadString(schema.assetPath),
    };
    tables[DataAssetPaths.achievements] = csv.encode([
      RuntimeTableSchemas.achievements.headers,
      ['ACH001', 'A fresh start', '-12000', 'FALSE'],
    ]);
    final store = MemoryLocalDatasetStore(tables);
    final repository = AssetAppDataRepository(store: store);
    final loaded = await repository.load();
    expect(loaded.achievements.single.earned, isFalse);

    final updated = await repository.updateAchievementEarned(
      'ACH001',
      earned: true,
    );

    expect(updated.achievements.single.earned, isTrue);
    expect(
      csv.decode((await store.read())![DataAssetPaths.achievements]!).last.last,
      'TRUE',
    );
  });
}

class _CountingDatasetStore implements LocalDatasetStore {
  Map<String, String>? _tables;
  int writeCount = 0;

  @override
  Future<Map<String, String>?> read() async =>
      _tables == null ? null : Map<String, String>.unmodifiable(_tables!);

  @override
  Future<void> write(Map<String, String> tables) async {
    writeCount++;
    _tables = Map.of(tables);
  }
}

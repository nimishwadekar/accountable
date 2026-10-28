import 'package:csv/csv.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('memory dataset store copies values', () async {
    final store = MemoryLocalDatasetStore({'table': 'initial'});
    final first = await store.read();
    expect(first?['table'], 'initial');

    await store.write({'table': 'updated'});
    expect((await store.read())?['table'], 'updated');
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

import 'package:accountable/config/data_source_config.dart';
import 'package:accountable/data/data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('asset repository loads one immutable snapshot', () async {
    final repository = AssetAppDataRepository();

    final snapshot = await repository.load();
    final cachedSnapshot = await repository.load();
    final reloadedSnapshot = await repository.reload();

    expect(identical(snapshot, cachedSnapshot), isTrue);
    expect(identical(snapshot, reloadedSnapshot), isFalse);
    expect(snapshot.accounts, hasLength(5));
    expect(snapshot.transactions, hasLength(8));
    expect(snapshot.dailyNetWorth, hasLength(3));
    expect(snapshot.accountsById['chase_checking']?.name, 'Chase Checking');
    expect(snapshot.transactionsById['t001']?.description, 'Lunch');
    expect(
      () => snapshot.accounts.add(snapshot.accounts.first),
      throwsUnsupportedError,
    );
    expect(
      () => snapshot.accountsById['new'] = snapshot.accounts.first,
      throwsUnsupportedError,
    );
  });

  test('factory creates local asset data when configured', () async {
    final repository = createAppDataRepository(
      config: const AppDataConfig(dataSourceMode: DataSourceMode.localAssets),
    );

    final snapshot = await repository.load();

    expect(snapshot.currenciesById.keys, containsAll(<String>['USD', 'INR']));
  });

  test('google sheets mode requires an API client', () {
    expect(
      () => createAppDataRepository(
        config: const AppDataConfig(
          dataSourceMode: DataSourceMode.googleSheets,
        ),
      ),
      throwsStateError,
    );
  });

  test('asset failures include the table name', () async {
    final repository = AssetAppDataRepository(reader: _ThrowingAssetReader());

    await expectLater(
      repository.load(),
      throwsA(
        isA<DataLoadException>().having(
          (error) => error.tableName,
          'tableName',
          'Currencies',
        ),
      ),
    );
  });
}

class _ThrowingAssetReader implements AssetReader {
  @override
  Future<String> readString(String assetPath) {
    throw StateError('Missing asset: $assetPath');
  }
}

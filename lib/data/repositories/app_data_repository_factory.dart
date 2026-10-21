import '../../config/accountable_config.dart';
import '../sources/asset_reader.dart';
import '../sources/google_sheets_api.dart';
import '../sources/local_dataset_store.dart';
import 'asset_repositories.dart';
import 'google_sheets_repository.dart';
import 'repositories.dart';

AppDataRepository createAppDataRepository({
  AccountableConfig config = const AccountableConfig(
    dataSource: AccountableDataSource.csv,
  ),
  AssetReader? assetReader,
  GoogleSheetsApi? googleSheetsApi,
}) {
  return switch (config.dataSource) {
    AccountableDataSource.csv => AssetAppDataRepository(
        reader: assetReader,
        store: SharedPreferencesLocalDatasetStore(),
      ),
    AccountableDataSource.sheets => googleSheetsApi == null
        ? throw StateError('A Google Sheets API client is required.')
        : GoogleSheetsAppDataRepository(googleSheetsApi),
  };
}

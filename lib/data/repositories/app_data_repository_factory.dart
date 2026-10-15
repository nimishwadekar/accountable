import '../../config/data_source_config.dart';
import '../sources/asset_reader.dart';
import '../sources/google_sheets_api.dart';
import '../sources/local_dataset_store.dart';
import 'asset_repositories.dart';
import 'google_sheets_repository.dart';
import 'repositories.dart';

AppDataRepository createAppDataRepository({
  AppDataConfig config = const AppDataConfig(
    dataSourceMode: DataSourceMode.localAssets,
  ),
  AssetReader? assetReader,
  GoogleSheetsApi? googleSheetsApi,
}) {
  return switch (config.dataSourceMode) {
    DataSourceMode.localAssets => AssetAppDataRepository(
        reader: assetReader,
        store: SharedPreferencesLocalDatasetStore(),
      ),
    DataSourceMode.googleSheets => googleSheetsApi == null
        ? throw StateError('A Google Sheets API client is required.')
        : GoogleSheetsAppDataRepository(googleSheetsApi),
  };
}

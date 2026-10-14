import '../../config/data_source_config.dart';
import '../sources/asset_reader.dart';
import 'asset_repositories.dart';
import 'repositories.dart';

AppDataRepository createAppDataRepository({
  AppDataConfig config = const AppDataConfig(),
  AssetReader? assetReader,
}) {
  return switch (config.dataSourceMode) {
    DataSourceMode.localAssets =>
      AssetAppDataRepository(reader: assetReader),
    DataSourceMode.googleSheets => throw UnsupportedError(
        'Google Sheets data access has not been implemented yet.',
      ),
  };
}

enum DataSourceMode {
  localAssets,
  googleSheets,
}

class AppDataConfig {
  const AppDataConfig({this.dataSourceMode = DataSourceMode.localAssets});

  final DataSourceMode dataSourceMode;
}

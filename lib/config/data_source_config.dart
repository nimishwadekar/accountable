enum DataSourceMode {
  localAssets,
  googleSheets,
}

class AppDataConfig {
  const AppDataConfig({required this.dataSourceMode});

  final DataSourceMode dataSourceMode;
}

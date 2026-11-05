/// Game storage configuration — the analogue of the main app's config,
/// nested under a `citysim` object so the same file can configure the
/// game once it runs inside the Accountable app.
///
/// `dataSource` selects where game data lives: `csv` (the four sheet
/// tables persisted as CSV documents through the local editor server,
/// `serverUrl`, which writes `assets/test_sheets/` — the same format the
/// real spreadsheet will use) or `sheets` (the game's own Google
/// Spreadsheet). `spreadsheetId` stays empty until that spreadsheet is
/// created.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

enum CitysimDataSource {
  csv,
  sheets;

  static CitysimDataSource fromJsonValue(Object? value) {
    return switch (value?.toString().trim().toLowerCase()) {
      'csv' => CitysimDataSource.csv,
      'sheets' => CitysimDataSource.sheets,
      _ => throw const FormatException(
        'assets/config.json citysim.dataSource must be "csv" or "sheets".',
      ),
    };
  }
}

class CitysimConfig {
  const CitysimConfig({
    required this.dataSource,
    this.spreadsheetId = '',
    this.serverUrl = '',
  });

  final CitysimDataSource dataSource;
  final String spreadsheetId;

  /// Base URL of the local editor server — the CSV-mode save transport.
  final String serverUrl;

  static Future<CitysimConfig> load() async {
    final contents = await rootBundle.loadString('assets/config.json');
    final decoded = jsonDecode(contents);
    if (decoded is! Map) {
      throw const FormatException(
        'assets/config.json must contain a JSON object.',
      );
    }
    final citysim = decoded['citysim'];
    if (citysim is! Map) {
      throw const FormatException(
        'assets/config.json must contain a "citysim" object.',
      );
    }
    return CitysimConfig.fromJson(
      citysim.map((key, value) => MapEntry(key as String, value)),
    );
  }

  factory CitysimConfig.fromJson(Map<String, Object?> json) => CitysimConfig(
    dataSource: CitysimDataSource.fromJsonValue(json['dataSource']),
    spreadsheetId: json['spreadsheetId'] as String? ?? '',
    serverUrl: json['serverUrl'] as String? ?? '',
  );
}

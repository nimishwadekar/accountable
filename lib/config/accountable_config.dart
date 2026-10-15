import 'dart:convert';

import 'package:flutter/services.dart';

enum AccountableDataSource {
  csv,
  sheets;

  static AccountableDataSource fromJsonValue(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    return switch (normalized) {
      'csv' => AccountableDataSource.csv,
      'sheets' => AccountableDataSource.sheets,
      _ => throw const FormatException(
        'assets/config.json dataSource must be either "csv" or "sheets".',
      ),
    };
  }
}

final class AccountableConfig {
  const AccountableConfig({
    required this.dataSource,
    required this.googleClientId,
    required this.spreadsheetId,
    required this.allowedEmail,
    required this.oauthOrigin,
    required this.sheetsScope,
  });

  final AccountableDataSource dataSource;
  final String googleClientId;
  final String spreadsheetId;
  final String allowedEmail;
  final String oauthOrigin;
  final String sheetsScope;

  bool get isCsvDataSource => dataSource == AccountableDataSource.csv;

  bool get isGoogleSheetsDataSource =>
      dataSource == AccountableDataSource.sheets;

  bool get hasConfiguredGoogleSheets =>
      _isConfiguredValue(googleClientId) &&
      _isConfiguredValue(spreadsheetId) &&
      _isConfiguredValue(allowedEmail) &&
      _isConfiguredValue(oauthOrigin) &&
      _isConfiguredValue(sheetsScope);

  static Future<AccountableConfig> load({AssetBundle? bundle}) async {
    final contents = await (bundle ?? rootBundle).loadString(
      'assets/config.json',
    );
    final decoded = jsonDecode(contents);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'assets/config.json must contain a JSON object.',
      );
    }
    return AccountableConfig.fromJson(decoded);
  }

  factory AccountableConfig.fromJson(Map<String, dynamic> json) {
    return AccountableConfig(
      dataSource: AccountableDataSource.fromJsonValue(json['dataSource']),
      googleClientId: _requireString(json, 'googleClientId'),
      spreadsheetId: _requireString(json, 'spreadsheetId'),
      allowedEmail: _requireString(json, 'allowedEmail'),
      oauthOrigin: _requireString(json, 'oauthOrigin'),
      sheetsScope: _requireString(json, 'sheetsScope'),
    );
  }

  static String _requireString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw FormatException('assets/config.json is missing "$key".');
  }

  static bool _isConfiguredValue(String value) {
    final trimmed = value.trim();
    return trimmed.isNotEmpty &&
        !trimmed.startsWith('YOUR_') &&
        !trimmed.contains('<') &&
        !trimmed.contains('>');
  }
}

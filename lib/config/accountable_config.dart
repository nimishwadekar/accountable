import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum StartupScenario {
  off,
  delayAutoSignIn,
  autoSignInFailure,
  delayAndAutoSignInFailure,
  sheetsAuthorizationFailure,
  dataLoadFailure;

  static StartupScenario parse(Object? value) {
    return switch (value?.toString().trim().toLowerCase()) {
      null || '' || 'off' => StartupScenario.off,
      'delay_auto_sign_in' => StartupScenario.delayAutoSignIn,
      'auto_sign_in_failure' => StartupScenario.autoSignInFailure,
      'delay_and_auto_sign_in_failure' =>
        StartupScenario.delayAndAutoSignInFailure,
      'sheets_authorization_failure' =>
        StartupScenario.sheetsAuthorizationFailure,
      'data_load_failure' => StartupScenario.dataLoadFailure,
      _ => throw const FormatException(
        'assets/config.json debug_startup_scenario is invalid.',
      ),
    };
  }
}

enum AccountableDataSource {
  csv,
  sheets;

  static AccountableDataSource fromJsonValue(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    return switch (normalized) {
      'csv' => AccountableDataSource.csv,
      'sheets' => AccountableDataSource.sheets,
      _ => throw const FormatException(
        'assets/config.json dataSource must be "csv" or "sheets".',
      ),
    };
  }
}

final class AccountableConfig {
  const AccountableConfig({
    required this.dataSource,
    this.googleClientId = '',
    this.spreadsheetId = '',
    this.allowedEmail = '',
    this.oauthOrigin = '',
    this.sheetsScope = '',
    this.additionalOauthOrigins = const [],
    this.migrationAssistance = false,
    this.debugStartupScenario = StartupScenario.off,
  });

  final AccountableDataSource dataSource;
  final String googleClientId;
  final String spreadsheetId;
  final String allowedEmail;
  final String oauthOrigin;
  final List<String> additionalOauthOrigins;
  final String sheetsScope;
  final bool migrationAssistance;
  final StartupScenario debugStartupScenario;

  List<String> get oauthOrigins => [oauthOrigin, ...additionalOauthOrigins];

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
      additionalOauthOrigins: _optionalStringList(
        json,
        'additionalOauthOrigins',
      ),
      sheetsScope: _requireString(json, 'sheetsScope'),
      migrationAssistance: _optionalBoolean(json, 'migration_assistance'),
      debugStartupScenario: _parseDebugStartupScenario(
        json['debug_startup_scenario'],
      ),
    );
  }

  static String _requireString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw FormatException('assets/config.json is missing "$key".');
  }

  static StartupScenario _parseDebugStartupScenario(Object? value) {
    final scenario = StartupScenario.parse(value);
    if (!kDebugMode && scenario != StartupScenario.off) {
      throw const FormatException(
        'debug_startup_scenario must be "off" in release mode.',
      );
    }
    return scenario;
  }

  static bool _optionalBoolean(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return false;
    if (value is! bool) {
      throw FormatException('assets/config.json "$key" must be a boolean.');
    }
    return value;
  }

  static List<String> _optionalStringList(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = json[key];
    if (value == null) {
      return const [];
    }
    if (value is! List || value.any((item) => item is! String)) {
      throw FormatException(
        'assets/config.json "$key" must be a list of strings.',
      );
    }
    return value.cast<String>();
  }

  static bool _isConfiguredValue(String value) {
    final trimmed = value.trim();
    return trimmed.isNotEmpty &&
        !trimmed.startsWith('YOUR_') &&
        !trimmed.contains('<') &&
        !trimmed.contains('>');
  }
}

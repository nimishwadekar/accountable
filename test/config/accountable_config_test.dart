import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/config/accountable_config.dart';

void main() {
  test('parses the committed JSON configuration shape', () {
    final config = AccountableConfig.fromJson({
      'dataSource': 'csv',
      'googleClientId': 'client-id',
      'spreadsheetId': 'sheet-id',
      'allowedEmail': 'owner@example.com',
      'oauthOrigin': 'https://nimishwadekar.github.io',
      'additionalOauthOrigins': ['http://localhost:9000'],
      'sheetsScope': 'https://www.googleapis.com/auth/spreadsheets',
    });

    expect(config.isCsvDataSource, isTrue);
    expect(config.spreadsheetId, 'sheet-id');
    expect(config.oauthOrigins, [
      'https://nimishwadekar.github.io',
      'http://localhost:9000',
    ]);
  });

  test('supports Sheets configuration and rejects invalid values', () {
    final config = AccountableConfig.fromJson({
      'dataSource': 'sheets',
      'googleClientId': 'client-id',
      'spreadsheetId': 'sheet-id',
      'allowedEmail': 'owner@example.com',
      'oauthOrigin': 'https://example.com',
      'sheetsScope': 'scope',
    });

    expect(config.isGoogleSheetsDataSource, isTrue);
    expect(config.hasConfiguredGoogleSheets, isTrue);
    expect(
      () => AccountableConfig.fromJson({'dataSource': 'unknown'}),
      throwsFormatException,
    );
    expect(
      () => AccountableConfig.fromJson({
        'dataSource': 'csv',
        'additionalOauthOrigins': [1],
      }),
      throwsFormatException,
    );
  });
}

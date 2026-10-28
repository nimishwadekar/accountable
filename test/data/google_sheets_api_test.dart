import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:accountable/data/data.dart';

void main() {
  test('updates before clearing stale trailing rows', () async {
    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add(request.method);
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'range': 'Transactions!A1:K3',
            'majorDimension': 'ROWS',
            'values': [
              ['header'],
              ['old-row-1'],
              ['old-row-2'],
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response(
        '{}',
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final api = GoogleSheetsApi(
      spreadsheetId: 'spreadsheet-id',
      accessTokenProvider: ({forceRefresh = false}) async => 'token',
      client: client,
    );

    await api.replaceRange('Transactions!A:K', [
      ['header'],
      ['new-row'],
    ]);

    expect(requests, ['GET', 'PUT', 'POST']);
  });

  test('writes numeric sheet values as numbers, not text', () async {
    Object? requestBody;
    Uri? requestUri;
    final client = MockClient((request) async {
      requestUri = request.url;
      requestBody = jsonDecode(request.body);
      return http.Response(
        '{}',
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final api = GoogleSheetsApi(
      spreadsheetId: 'spreadsheet-id',
      accessTokenProvider: ({forceRefresh = false}) async => 'token',
      client: client,
    );

    await api.appendRow('DailyManualValuations!A:D', [
      '2026-10-16-hdfc_credila_loan',
      '2026-10-16',
      'hdfc_credila_loan',
      '-2862922.00',
    ]);

    final request = requestBody as Map<String, dynamic>;
    expect(requestUri?.queryParameters['valueInputOption'], 'USER_ENTERED');
    final values = request['values'] as List;
    expect(values.first[3], -2862922.00);
    expect(values.first[3], isA<num>());
  });

  test('writes template favorite state as a Sheets boolean', () async {
    Object? requestBody;
    final client = MockClient((request) async {
      requestBody = jsonDecode(request.body);
      return http.Response(
        '{}',
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final api = GoogleSheetsApi(
      spreadsheetId: 'spreadsheet-id',
      accessTokenProvider: ({forceRefresh = false}) async => 'token',
      client: client,
    );

    await api.appendRow('TransactionTemplates!A:N', [
      'template-id',
      'Coffee',
      'expense',
      '',
      'Coffee at {Merchant}',
      'food_drink',
      'boston',
      'checking',
      '4.50',
      '',
      '',
      '2026-10-20T00:00:00Z',
      '2026-10-20T00:00:00Z',
      'TRUE',
    ]);

    final values = (requestBody as Map<String, dynamic>)['values'] as List;
    expect(values.single[13], isTrue);
    expect(values.single[13], isA<bool>());
  });

  test('writes acknowledged achievement values as a Sheets boolean', () async {
    Object? updateBody;
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'values': [
              ['achievement_id', 'name', 'target_usd', 'earned'],
              ['ACH001', 'A fresh start', -12000, false],
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      updateBody = jsonDecode(request.body);
      return http.Response(
        '{}',
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final api = GoogleSheetsApi(
      spreadsheetId: 'spreadsheet-id',
      accessTokenProvider: ({forceRefresh = false}) async => 'token',
      client: client,
    );

    await api.replaceRange('Achievements!A:D', [
      RuntimeTableSchemas.achievements.headers,
      ['ACH001', 'A fresh start', '-12000', 'TRUE'],
    ]);

    final values = (updateBody as Map<String, dynamic>)['values'] as List;
    expect(values[1][2], -12000);
    expect(values[1][3], isTrue);
  });
}

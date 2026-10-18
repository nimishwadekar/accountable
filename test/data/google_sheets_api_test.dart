import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:accountable/data/data.dart';

void main() {
  test('writes numeric sheet values as numbers, not text', () async {
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

    await api.appendRow('DailyManualValuations!A:D', [
      '2026-10-16-hdfc_credila_loan',
      '2026-10-16',
      'hdfc_credila_loan',
      '-2862922.00',
    ]);

    final values = (requestBody as Map<String, dynamic>)['values'] as List;
    expect(values.first[3], -2862922.00);
    expect(values.first[3], isA<num>());
  });
}

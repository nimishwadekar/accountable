import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:accountable/data/data.dart';

void main() {
  test('appends a transaction batch in one Sheets request', () async {
    var requestCount = 0;
    Object? body;
    final client = MockClient((request) async {
      requestCount++;
      body = jsonDecode(request.body);
      return http.Response(
        '{}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = GoogleSheetsApi(
      spreadsheetId: 'spreadsheet-id',
      accessTokenProvider: ({forceRefresh = false}) async => 'token',
      client: client,
    );

    await api.appendRows('Transactions!A:K', [
      ['fee', '2026-10-20', 'Transfer Fee', 'financial_fees'],
      ['transfer', '2026-10-20', 'Loan Payment', ''],
    ]);

    expect(requestCount, 1);
    expect((body as Map<String, dynamic>)['values'], hasLength(2));
  });
}

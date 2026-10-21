import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:accountable/data/data.dart';

void main() {
  test('replaces derived tables in one Sheets update request', () async {
    var requestCount = 0;
    Object? body;
    final client = MockClient((request) async {
      requestCount++;
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'valueRanges': [
              {
                'values': [
                  ['header'],
                ],
              },
              {
                'values': [
                  ['header'],
                ],
              },
              {
                'values': [
                  ['header'],
                ],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
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

    await api.replaceRanges({
      'DailyExchangeRates!A:F': [
        [
          'rate_id',
          'rate_date',
          'currency',
          'rate_to_usd',
          'source_rate_date',
          'retrieved_at',
        ],
      ],
      'DailyAccountBalances!A:F': [
        [
          'balance_id',
          'balance_date',
          'account_id',
          'balance',
          'balance_usd',
          'retrieved_at',
        ],
      ],
      'DailyNetWorth!A:D': [
        ['net_worth_id', 'net_worth_date', 'amount', 'retrieved_at'],
      ],
    });

    expect(requestCount, 2);
    final request = body as Map<String, dynamic>;
    expect(request['valueInputOption'], 'USER_ENTERED');
    expect(request['data'], hasLength(3));
  });

  test('appends a transaction batch in one Sheets request', () async {
    var requestCount = 0;
    Object? body;
    Uri? requestUri;
    final client = MockClient((request) async {
      requestUri = request.url;
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
    final request = body as Map<String, dynamic>;
    expect(requestUri?.queryParameters['valueInputOption'], 'USER_ENTERED');
    expect(request['values'], hasLength(2));
  });
}

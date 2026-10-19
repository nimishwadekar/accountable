import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:accountable/data/data.dart';

void main() {
  test('loads requested tables through an authenticated POST', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode({
          'ok': true,
          'tables': {
            'Accounts': [
              ['account_id', 'name'],
            ],
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final tableClient = AppsScriptTableClient(
      endpoint: 'https://script.example/exec',
      idTokenProvider: () async => 'id-token',
      client: client,
    );

    final tables = await tableClient.batchReadRanges(['Accounts!A:H']);

    expect(tables['Accounts!A:H'], [
      ['account_id', 'name'],
    ]);
    expect(requests, hasLength(1));
    expect(requests.single.method, 'POST');
    expect(requests.single.headers['content-type'], startsWith('text/plain'));
    expect(jsonDecode(requests.single.body), {
      'action': 'loadSnapshot',
      'idToken': 'id-token',
    });
  });

  test('surfaces Apps Script error responses', () async {
    final tableClient = AppsScriptTableClient(
      endpoint: 'https://script.example/exec',
      idTokenProvider: () async => 'id-token',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'ok': false, 'error': 'Invalid Google ID token.'}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

    expect(
      () => tableClient.batchReadRanges(['Accounts!A:H']),
      throwsA(
        predicate<Object>(
          (error) => error.toString().contains('Invalid Google ID token.'),
        ),
      ),
    );
  });
}

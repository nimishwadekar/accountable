import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:accountable/data/sources/bearer_client.dart';

void main() {
  test(
    'adds a bearer token and retries once after an unauthorized response',
    () async {
      final innerClient = _FakeHttpClient(<int>[401, 200]);
      final requestedRefreshes = <bool>[];
      final client = BearerClient(({bool forceRefresh = false}) async {
        requestedRefreshes.add(forceRefresh);
        return forceRefresh ? 'fresh-token' : 'initial-token';
      }, innerClient: innerClient);

      final response = await client.get(Uri.parse('https://example.com/data'));

      expect(response.statusCode, 200);
      expect(requestedRefreshes, [false, true]);
      expect(innerClient.authorizationHeaders, [
        'Bearer initial-token',
        'Bearer fresh-token',
      ]);
    },
  );

  test('does not refresh a successful request', () async {
    final innerClient = _FakeHttpClient(<int>[200]);
    var refreshRequested = false;
    final client = BearerClient(({bool forceRefresh = false}) async {
      refreshRequested = forceRefresh;
      return 'token';
    }, innerClient: innerClient);

    final response = await client.get(Uri.parse('https://example.com/data'));

    expect(response.statusCode, 200);
    expect(refreshRequested, isFalse);
    expect(innerClient.authorizationHeaders, ['Bearer token']);
  });
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this.statusCodes);

  final List<int> statusCodes;
  final List<String?> authorizationHeaders = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    authorizationHeaders.add(request.headers['Authorization']);
    final statusCode = statusCodes.removeAt(0);
    return http.StreamedResponse(
      Stream<List<int>>.empty(),
      statusCode,
      request: request,
    );
  }
}

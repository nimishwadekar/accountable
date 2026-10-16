import 'package:http/http.dart' as http;

typedef SheetsAccessTokenProvider = Future<String> Function({
  bool forceRefresh,
});

class BearerClient extends http.BaseClient {
  BearerClient(this._accessTokenProvider, {http.Client? innerClient})
      : _innerClient = innerClient ?? http.Client();

  final SheetsAccessTokenProvider _accessTokenProvider;
  final http.Client _innerClient;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final accessToken = await _accessTokenProvider();
    request.headers['Authorization'] = 'Bearer $accessToken';
    final response = await _innerClient.send(request);
    if (response.statusCode != 401 || request is! http.Request) {
      return response;
    }

    await response.stream.drain<void>();
    final retryRequest = _copyRequest(request);
    final refreshedToken = await _accessTokenProvider(forceRefresh: true);
    retryRequest.headers['Authorization'] = 'Bearer $refreshedToken';
    return _innerClient.send(retryRequest);
  }

  static http.Request _copyRequest(http.Request request) {
    return http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = request.bodyBytes
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection;
  }

  @override
  void close() {
    _innerClient.close();
    super.close();
  }
}

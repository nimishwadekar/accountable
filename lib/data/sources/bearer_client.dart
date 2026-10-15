import 'package:http/http.dart' as http;

class BearerClient extends http.BaseClient {
  BearerClient(this.accessToken, {http.Client? innerClient})
      : _innerClient = innerClient ?? http.Client();

  final String accessToken;
  final http.Client _innerClient;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $accessToken';
    return _innerClient.send(request);
  }

  @override
  void close() {
    _innerClient.close();
    super.close();
  }
}

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Talks to the content editor server (see tool/content_editor/server.dart).
class ContentApi {
  ContentApi({http.Client? client, this.baseUrl = 'http://localhost:9200'})
    : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  /// Raw decoded category maps keyed by file name (manifest.json, …).
  Future<Map<String, Object?>> loadContent() async {
    return _decode(await _get('/api/content'));
  }

  /// Validates the given category maps. Returns the server's response with
  /// `ok` and `issues` fields.
  Future<Map<String, Object?>> validate(Map<String, Object?> categories) async {
    return _decode(await _postJson('/api/content/validate', body: categories));
  }

  /// Saves the given category maps atomically after validation. On
  /// validation failure the response has status 422 and `ok == false`.
  Future<Map<String, Object?>> save(Map<String, Object?> categories) async {
    final response = await _postJson('/api/content', body: categories);
    final decoded = _decode(response);
    if (response.statusCode >= 400) {
      throw ContentApiException(
        decoded['error'] as String? ?? 'Save failed',
        issues: (decoded['issues'] as List?)?.cast<String>() ?? const [],
      );
    }
    return decoded;
  }

  Future<List<String>> listBackups() async {
    final decoded = _decode(await _get('/api/backups'));
    return ((decoded['backups'] as List?) ?? []).cast<String>();
  }

  Future<void> restoreBackup(String name) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/backups/restore/$name'),
    );
    if (response.statusCode != 200) {
      throw ContentApiException('Restore failed (${response.statusCode})');
    }
  }

  /// URL for an asset file (sprite or character art) served by the
  /// editor server from the package's assets directory.
  String assetUrl(String path) => '$baseUrl/api/asset/${Uri.encodeFull(path)}';

  Future<http.Response> _get(String path) async {
    final response = await _client.get(Uri.parse('$baseUrl$path'));
    if (response.statusCode != 200) {
      throw ContentApiException('GET $path failed (${response.statusCode})');
    }
    return response;
  }

  Future<http.Response> _postJson(String path, {required Object body}) =>
      _client.post(
        Uri.parse('$baseUrl$path'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode(body),
      );

  Map<String, Object?> _decode(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw ContentApiException('Unexpected response from $baseUrl');
    }
    return decoded.cast<String, Object?>();
  }
}

class ContentApiException implements Exception {
  ContentApiException(this.message, {this.issues = const []});

  final String message;
  final List<String> issues;

  @override
  String toString() => message;
}

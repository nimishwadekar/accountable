import 'dart:convert';

import 'package:http/http.dart' as http;

import 'google_sheets_api.dart';

typedef IdTokenProvider = Future<String> Function();

class AppsScriptTableClient implements SheetsTableClient {
  AppsScriptTableClient({
    required String endpoint,
    required this.idTokenProvider,
    http.Client? client,
  }) : endpoint = Uri.parse(endpoint),
       _client = client ?? http.Client();

  final Uri endpoint;
  final IdTokenProvider idTokenProvider;
  final http.Client _client;

  @override
  Future<Map<String, List<List<String>>>> batchReadRanges(
    List<String> ranges,
  ) async {
    final response = await _client.post(
      endpoint,
      headers: {'Content-Type': 'text/plain'},
      body: jsonEncode({
        'action': 'loadSnapshot',
        'idToken': await idTokenProvider(),
      }),
    );
    _ensureSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['ok'] != true) {
      throw StateError(_errorMessage(decoded));
    }
    final tables = decoded['tables'];
    if (tables is! Map<String, dynamic>) {
      throw const FormatException('Apps Script response is missing tables.');
    }
    return {
      for (final range in ranges)
        range: _rowsForTable(tables, _tableName(range)),
    };
  }

  @override
  Future<List<List<String>>> readRange(String range) async {
    final values = await batchReadRanges([range]);
    return values[range] ?? const [];
  }

  @override
  Future<void> appendRow(String range, List<String> values) async {
    if (_tableName(range) != 'DisplayPreferences') {
      throw UnsupportedError(
        'Apps Script proof-of-concept mode is read-only for $range.',
      );
    }
    final response = await _client.post(
      endpoint,
      headers: {'Content-Type': 'text/plain'},
      body: jsonEncode({
        'action': 'appendDisplayPreference',
        'idToken': await idTokenProvider(),
        'row': values,
      }),
    );
    _ensureSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['ok'] != true) {
      throw StateError(_errorMessage(decoded));
    }
  }

  @override
  Future<void> replaceRange(String range, List<List<String>> values) {
    throw UnsupportedError(
      'Apps Script proof-of-concept mode is read-only for $range.',
    );
  }

  static String _tableName(String range) => range.split('!').first;

  static List<List<String>> _rowsForTable(
    Map<String, dynamic> tables,
    String tableName,
  ) {
    final rows = tables[tableName];
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (row is List) [for (final value in row) value.toString()],
    ];
  }

  static void _ensureSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Apps Script request failed with HTTP ${response.statusCode}.',
      );
    }
  }

  static String _errorMessage(Object? decoded) {
    if (decoded is Map<String, dynamic> && decoded['error'] != null) {
      return decoded['error'].toString();
    }
    return 'Apps Script returned an invalid response.';
  }

  void close() => _client.close();
}

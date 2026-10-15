import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:http/http.dart' as http;

import 'bearer_client.dart';

abstract interface class SheetsTableClient {
  Future<List<List<String>>> readRange(String range);

  Future<Map<String, List<List<String>>>> batchReadRanges(List<String> ranges);

  Future<void> appendRow(String range, List<String> values);

  Future<void> replaceRange(String range, List<List<String>> values);
}

class GoogleSheetsApi implements SheetsTableClient {
  GoogleSheetsApi({required this.spreadsheetId, required String accessToken})
    : _client = BearerClient(accessToken) {
    _sheetsApi = sheets.SheetsApi(_client);
  }

  final String spreadsheetId;
  final http.Client _client;
  late final sheets.SheetsApi _sheetsApi;

  @override
  Future<List<List<String>>> readRange(String range) async {
    final response = await _sheetsApi.spreadsheets.values.get(
      spreadsheetId,
      range,
      valueRenderOption: 'UNFORMATTED_VALUE',
      dateTimeRenderOption: 'FORMATTED_STRING',
    );
    return _normalizeRows(response.values);
  }

  @override
  Future<Map<String, List<List<String>>>> batchReadRanges(
    List<String> ranges,
  ) async {
    final response = await _sheetsApi.spreadsheets.values.batchGet(
      spreadsheetId,
      ranges: ranges,
      valueRenderOption: 'UNFORMATTED_VALUE',
      dateTimeRenderOption: 'FORMATTED_STRING',
    );
    final valueRanges = response.valueRanges ?? const <sheets.ValueRange>[];
    return {
      for (var index = 0; index < ranges.length; index++)
        ranges[index]: index < valueRanges.length
            ? _normalizeRows(valueRanges[index].values)
            : const <List<String>>[],
    };
  }

  @override
  Future<void> appendRow(String range, List<String> values) async {
    await _sheetsApi.spreadsheets.values.append(
      sheets.ValueRange(values: [values]),
      spreadsheetId,
      range,
      valueInputOption: 'RAW',
      insertDataOption: 'INSERT_ROWS',
    );
  }

  @override
  Future<void> replaceRange(String range, List<List<String>> values) async {
    await _sheetsApi.spreadsheets.values.clear(
      sheets.ClearValuesRequest(),
      spreadsheetId,
      range,
    );
    await _sheetsApi.spreadsheets.values.update(
      sheets.ValueRange(values: values),
      spreadsheetId,
      range,
      valueInputOption: 'RAW',
    );
  }

  void close() => _client.close();

  static List<List<String>> _normalizeRows(List<List<Object?>>? rows) {
    return [
      for (final row in rows ?? const <List<Object?>>[])
        [for (final value in row) value?.toString() ?? ''],
    ];
  }
}

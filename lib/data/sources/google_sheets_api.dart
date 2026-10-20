import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:http/http.dart' as http;

import 'bearer_client.dart';

abstract class SheetsTableClient {
  Future<List<List<String>>> readRange(String range);

  Future<Map<String, List<List<String>>>> batchReadRanges(List<String> ranges);

  Future<void> appendRow(String range, List<String> values);

  Future<void> appendRows(String range, List<List<String>> values) async {
    for (final row in values) {
      await appendRow(range, row);
    }
  }

  Future<void> replaceRange(String range, List<List<String>> values);
}

class GoogleSheetsApi implements SheetsTableClient {
  GoogleSheetsApi({
    required this.spreadsheetId,
    required SheetsAccessTokenProvider accessTokenProvider,
    http.Client? client,
  }) : _client = BearerClient(accessTokenProvider, innerClient: client) {
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
  Future<void> appendRow(String range, List<String> values) {
    return appendRows(range, [values]);
  }

  @override
  Future<void> appendRows(String range, List<List<String>> values) async {
    await _sheetsApi.spreadsheets.values.append(
      sheets.ValueRange(
        values: [for (final row in values) _coerceValues(range, row)],
      ),
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
      sheets.ValueRange(
        values: [for (final row in values) _coerceValues(range, row)],
      ),
      spreadsheetId,
      range,
      valueInputOption: 'RAW',
    );
  }

  void close() => _client.close();

  static List<Object?> _coerceValues(String range, List<String> values) {
    final table = range.split('!').first;
    final numericColumns = switch (table) {
      'Accounts' => const {4},
      'Currencies' => const {2},
      'DailyAccountBalances' => const {3, 4},
      'DailyExchangeRates' => const {3},
      'DailyManualValuations' => const {3},
      'DailyNetWorth' => const {2},
      'DisplayPreferences' => const {2},
      'Transactions' => const {5, 7},
      _ => const <int>{},
    };
    final booleanColumns = table == 'DisplayPreferences'
        ? const {3, 4}
        : const <int>{};
    return [
      for (var index = 0; index < values.length; index++)
        if (numericColumns.contains(index) &&
            num.tryParse(values[index]) != null)
          num.parse(values[index])
        else if (booleanColumns.contains(index) &&
            (values[index].toUpperCase() == 'TRUE' ||
                values[index].toUpperCase() == 'FALSE'))
          values[index].toUpperCase() == 'TRUE'
        else
          values[index],
    ];
  }

  static List<List<String>> _normalizeRows(List<List<Object?>>? rows) {
    return [
      for (final row in rows ?? const <List<Object?>>[])
        [for (final value in row) value?.toString() ?? ''],
    ];
  }
}

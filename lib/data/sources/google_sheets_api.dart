import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:http/http.dart' as http;

import 'bearer_client.dart';
import '../table_schema.dart';

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

  Future<void> replaceRanges(Map<String, List<List<String>>> ranges) async {
    for (final entry in ranges.entries) {
      await replaceRange(entry.key, entry.value);
    }
  }

  /// Updates multiple explicit A1 ranges in a single values batch request.
  Future<void> updateRanges(Map<String, List<List<String>>> ranges) async {
    for (final entry in ranges.entries) {
      await replaceRange(entry.key, entry.value);
    }
  }

  /// Inserts rows beneath a header and copies values from another sheet.
  Future<void> insertRowsAndCopyValues({
    required String sourceSheetName,
    required String destinationSheetName,
    required int rowCount,
    required int columnCount,
  }) => throw UnsupportedError(
    'This Sheets client cannot insert and copy spreadsheet rows.',
  );
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
      valueInputOption: 'USER_ENTERED',
      insertDataOption: 'INSERT_ROWS',
    );
  }

  @override
  Future<void> replaceRange(String range, List<List<String>> values) async {
    final existing = await _sheetsApi.spreadsheets.values.get(
      spreadsheetId,
      range,
      valueRenderOption: 'UNFORMATTED_VALUE',
      dateTimeRenderOption: 'FORMATTED_STRING',
    );
    await _sheetsApi.spreadsheets.values.update(
      sheets.ValueRange(
        values: [for (final row in values) _coerceValues(range, row)],
      ),
      spreadsheetId,
      range,
      valueInputOption: 'USER_ENTERED',
    );

    final existingRowCount = existing.values?.length ?? 0;
    if (existingRowCount > values.length) {
      final trailingRange = _trailingRange(
        range,
        firstRow: values.length + 1,
        lastRow: existingRowCount,
      );
      if (trailingRange != null) {
        await _sheetsApi.spreadsheets.values.clear(
          sheets.ClearValuesRequest(),
          spreadsheetId,
          trailingRange,
        );
      }
    }
  }

  @override
  Future<void> replaceRanges(Map<String, List<List<String>>> ranges) async {
    if (ranges.isEmpty) return;
    final rangeNames = ranges.keys.toList();
    final existing = await batchReadRanges(rangeNames);
    final updates = <sheets.ValueRange>[];
    for (final entry in ranges.entries) {
      final schema = RuntimeTableSchemas.byRange(entry.key);
      final rows = [
        for (final row in entry.value)
          _coerceValues(entry.key, [
            ...row,
            for (var index = row.length; index < schema.columnCount; index++)
              '',
          ]),
      ];
      final existingRowCount = existing[entry.key]?.length ?? 0;
      while (rows.length < existingRowCount) {
        rows.add(List<Object?>.filled(schema.columnCount, ''));
      }
      updates.add(sheets.ValueRange(range: entry.key, values: rows));
    }
    await _sheetsApi.spreadsheets.values.batchUpdate(
      sheets.BatchUpdateValuesRequest(
        valueInputOption: 'USER_ENTERED',
        data: updates,
      ),
      spreadsheetId,
    );
  }

  @override
  Future<void> updateRanges(Map<String, List<List<String>>> ranges) async {
    if (ranges.isEmpty) return;
    await _sheetsApi.spreadsheets.values.batchUpdate(
      sheets.BatchUpdateValuesRequest(
        valueInputOption: 'USER_ENTERED',
        data: [
          for (final entry in ranges.entries)
            sheets.ValueRange(
              range: entry.key,
              values: [
                for (final row in entry.value) _coerceValues(entry.key, row),
              ],
            ),
        ],
      ),
      spreadsheetId,
    );
  }

  @override
  Future<void> insertRowsAndCopyValues({
    required String sourceSheetName,
    required String destinationSheetName,
    required int rowCount,
    required int columnCount,
  }) async {
    if (rowCount <= 0 || columnCount <= 0) {
      throw ArgumentError('Row and column counts must be positive.');
    }
    final spreadsheet = await _sheetsApi.spreadsheets.get(
      spreadsheetId,
      $fields: 'sheets(properties(sheetId,title))',
    );
    int sheetIdFor(String title) {
      for (final sheet in spreadsheet.sheets ?? const <sheets.Sheet>[]) {
        final properties = sheet.properties;
        if (properties?.title == title && properties?.sheetId != null) {
          return properties!.sheetId!;
        }
      }
      throw StateError('Spreadsheet sheet "$title" was not found.');
    }

    final sourceSheetId = sheetIdFor(sourceSheetName);
    final destinationSheetId = sheetIdFor(destinationSheetName);
    await _sheetsApi.spreadsheets.batchUpdate(
      sheets.BatchUpdateSpreadsheetRequest(
        requests: [
          sheets.Request(
            insertDimension: sheets.InsertDimensionRequest(
              range: sheets.DimensionRange(
                sheetId: destinationSheetId,
                dimension: 'ROWS',
                startIndex: 1,
                endIndex: rowCount + 1,
              ),
              inheritFromBefore: false,
            ),
          ),
          sheets.Request(
            copyPaste: sheets.CopyPasteRequest(
              source: sheets.GridRange(
                sheetId: sourceSheetId,
                startRowIndex: 1,
                endRowIndex: rowCount + 1,
                startColumnIndex: 0,
                endColumnIndex: columnCount,
              ),
              destination: sheets.GridRange(
                sheetId: destinationSheetId,
                startRowIndex: 1,
                endRowIndex: rowCount + 1,
                startColumnIndex: 0,
                endColumnIndex: columnCount,
              ),
              pasteType: 'PASTE_VALUES',
              pasteOrientation: 'NORMAL',
            ),
          ),
        ],
      ),
      spreadsheetId,
    );
  }

  static String? _trailingRange(
    String range, {
    required int firstRow,
    required int lastRow,
  }) {
    final separator = range.indexOf('!');
    if (separator < 0) return null;
    final sheet = range.substring(0, separator);
    final columns = range.substring(separator + 1).split(':');
    if (columns.length != 2) return null;
    final startColumn = columns.first.replaceAll(RegExp(r'\d'), '');
    final endColumn = columns.last.replaceAll(RegExp(r'\d'), '');
    if (startColumn.isEmpty || endColumn.isEmpty) return null;
    return '$sheet!$startColumn$firstRow:$endColumn$lastRow';
  }

  void close() => _client.close();

  static List<Object?> _coerceValues(String range, List<String> values) {
    final schema = RuntimeTableSchemas.byName(range.split('!').first);
    final numericColumns = schema.numericColumns;
    final booleanColumns = schema.booleanColumns;
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

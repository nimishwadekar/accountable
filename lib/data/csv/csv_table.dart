import 'package:csv/csv.dart';

class CsvTable {
  CsvTable._(this.tableName, this.headers, this.rows, this.rowNumbers);

  final String tableName;
  final List<String> headers;
  final List<Map<String, String>> rows;
  final List<int> rowNumbers;

  factory CsvTable.parse(String source, {required String tableName}) {
    final rawRows = csv.decode(source);
    if (rawRows.isEmpty) {
      throw CsvFormatException(tableName, 'The file is empty.');
    }

    final headers = rawRows.first.map((value) => value.toString().trim()).toList();
    if (headers.isEmpty || headers.any((header) => header.isEmpty)) {
      throw CsvFormatException(tableName, 'The header row contains an empty field.');
    }
    if (headers.toSet().length != headers.length) {
      throw CsvFormatException(tableName, 'The header row contains duplicate fields.');
    }

    final rows = <Map<String, String>>[];
    final rowNumbers = <int>[];
    for (var index = 1; index < rawRows.length; index++) {
      final values = rawRows[index].map((value) => value.toString().trim()).toList();
      if (values.every((value) => value.isEmpty)) {
        continue;
      }
      if (values.length != headers.length) {
        throw CsvFormatException(
          tableName,
          'Row ${index + 1} has ${values.length} fields; expected ${headers.length}.',
        );
      }

      rows.add({
        for (var column = 0; column < headers.length; column++)
          headers[column]: values[column],
      });
      rowNumbers.add(index + 1);
    }

    return CsvTable._(
      tableName,
      List.unmodifiable(headers),
      List.unmodifiable(rows),
      List.unmodifiable(rowNumbers),
    );
  }
}

class CsvFormatException implements Exception {
  const CsvFormatException(this.tableName, this.message);

  final String tableName;
  final String message;

  @override
  String toString() => 'Invalid $tableName CSV: $message';
}

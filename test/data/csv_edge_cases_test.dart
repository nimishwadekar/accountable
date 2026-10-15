import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/csv/csv.dart';

void main() {
  test('CSV parser skips blank rows and rejects malformed rows', () {
    final table = CsvTable.parse(
      'id,name\n1,One\n,\n2,Two\n',
      tableName: 'Example',
    );
    expect(table.rows, hasLength(2));

    expect(
      () => CsvTable.parse('id,id\n1,One\n', tableName: 'Duplicate'),
      throwsA(isA<CsvFormatException>()),
    );
    expect(
      () => CsvTable.parse('id,name\n1\n', tableName: 'Malformed'),
      throwsA(isA<CsvFormatException>()),
    );
  });

  test('date and timestamp helpers reject malformed values', () {
    expect(
      () => parseDateOnly('2026-02-30', fieldName: 'date'),
      throwsFormatException,
    );
    expect(
      () => parseUtcTimestamp('not-a-timestamp', fieldName: 'created_at'),
      throwsFormatException,
    );
    expect(requiredValue({'name': 'value'}, 'name'), 'value');
    expect(optionalValue({'name': ''}, 'name'), isNull);
  });
}

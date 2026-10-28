import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';

void main() {
  test(
    'parses descriptive labels, de-duplicates inputs, and composes text',
    () {
      final pattern = TransactionDescriptionPattern.parse(
        'Dinner at {Restaurant Name} with {Person} and {Person}',
      );

      expect(pattern.placeholders, ['Restaurant Name', 'Person']);
      expect(
        pattern.compose({'Restaurant Name': 'Cafe Luna', 'Person': 'Ari'}),
        'Dinner at Cafe Luna with Ari and Ari',
      );
    },
  );

  test('supports escaped braces as literal text', () {
    final pattern = TransactionDescriptionPattern.parse(
      'Save as {{literal braces}} for {Month}',
    );

    expect(pattern.placeholders, ['Month']);
    expect(
      pattern.compose({'Month': 'October'}),
      'Save as {literal braces} for October',
    );
  });

  test('rejects malformed, empty, and unfilled placeholders', () {
    expect(
      () => TransactionDescriptionPattern.parse('At {Restaurant'),
      throwsFormatException,
    );
    expect(
      () => TransactionDescriptionPattern.parse('At {}'),
      throwsFormatException,
    );
    expect(
      () => TransactionDescriptionPattern.parse('At }'),
      throwsFormatException,
    );
    expect(
      () => TransactionDescriptionPattern.parse('At {Restaurant}').compose({}),
      throwsFormatException,
    );
  });
}

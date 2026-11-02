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

  test('parses placeholder choices and composes the selected choice', () {
    final pattern = TransactionDescriptionPattern.parse(
      'Coffee at {Merchant~Cafe;^Office}',
    );

    expect(pattern.placeholders, ['Merchant']);
    expect(
      pattern.placeholderOptions['Merchant']!.map((option) => option.value),
      ['Cafe', 'Office'],
    );
    expect(pattern.compose({'Merchant': 'Office'}), 'Coffee at Office');
  });

  test('encodes placeholder choices separately from the placeholder label', () {
    expect(
      TransactionDescriptionPattern.encodePlaceholderOptions(
        'Coffee at {Merchant}',
        {
          'Merchant': const [
            TemplateOption(value: 'Cafe'),
            TemplateOption(value: 'Office', isDefault: true),
          ],
        },
      ),
      'Coffee at {Merchant~Cafe;^Office}',
    );
  });

  test(
    'rejects inconsistent repeated placeholder choices and reserved literals',
    () {
      expect(
        () => TransactionDescriptionPattern.parse(
          '{Place~Cafe;^Office} then {Place~Cafe;^Home}',
        ),
        throwsFormatException,
      );
      expect(
        () => TransactionDescriptionPattern.parse('Coffee; cake'),
        throwsFormatException,
      );
      expect(
        () => TransactionDescriptionPattern.parse(
          'At {Place~Cafe;^Office;^Home}',
        ),
        throwsFormatException,
      );
    },
  );

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

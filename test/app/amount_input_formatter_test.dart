import 'package:accountable/app/amount_input_formatter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const formatter = ThousandsSeparatorInputFormatter();

  test('groups integer digits and keeps the caret with the digits', () {
    final result = formatter.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(
        text: '1234567',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );

    expect(result.text, '1,234,567');
    expect(result.selection, const TextSelection.collapsed(offset: 3));
  });

  test('preserves decimal digits and a trailing decimal point', () {
    final withFraction = formatter.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(
        text: '1234567.89',
        selection: TextSelection.collapsed(offset: 10),
      ),
    );
    final trailingPoint = formatter.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(
        text: '1234.',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );

    expect(withFraction.text, '1,234,567.89');
    expect(withFraction.selection, const TextSelection.collapsed(offset: 12));
    expect(trailingPoint.text, '1,234.');
    expect(trailingPoint.selection, const TextSelection.collapsed(offset: 6));
  });

  test('regroups as digits are deleted', () {
    final result = formatter.formatEditUpdate(
      const TextEditingValue(
        text: '1,234,567',
        selection: TextSelection.collapsed(offset: 8),
      ),
      const TextEditingValue(
        text: '1,234,56',
        selection: TextSelection.collapsed(offset: 8),
      ),
    );

    expect(result.text, '123,456');
    expect(result.selection, const TextSelection.collapsed(offset: 7));
  });
}

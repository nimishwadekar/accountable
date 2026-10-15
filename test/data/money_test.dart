import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';

void main() {
  const usd = CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2);
  const inr = CurrencyDefinition(id: 'INR', symbol: '₹', decimalPlaces: 2);

  test('rounds major-unit input to currency minor units', () {
    final money = Money.fromMajorUnits(value: '12.345', currency: usd);

    expect(money.minorUnits, 1235);
    expect(money.toMajorUnitsString(usd), '12.35');
  });

  test('does not combine different currencies', () {
    final dollars = Money.fromMajorUnits(value: '1', currency: usd);
    final rupees = Money.fromMajorUnits(value: '1', currency: inr);

    expect(() => dollars + rupees, throwsArgumentError);
    expect(() => dollars - rupees, throwsArgumentError);
  });

  test('preserves signed balances for subtraction', () {
    final balance = Money.fromMajorUnits(value: '-450', currency: usd);
    final expense = Money.fromMajorUnits(value: '35', currency: usd);

    expect((balance - expense).minorUnits, -48500);
  });
}

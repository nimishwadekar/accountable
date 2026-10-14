import 'package:decimal/decimal.dart';

import 'currency.dart';

class Money {
  const Money({required this.minorUnits, required this.currencyId});

  final int minorUnits;
  final String currencyId;

  factory Money.fromMajorUnits({
    required String value,
    required CurrencyDefinition currency,
  }) {
    final majorUnits = Decimal.parse(value.trim());
    final scale = Decimal.fromInt(_powerOfTen(currency.decimalPlaces));
    final minorUnits = (majorUnits * scale).round().toBigInt().toInt();

    return Money(minorUnits: minorUnits, currencyId: currency.id);
  }

  factory Money.zero(CurrencyDefinition currency) {
    return Money(minorUnits: 0, currencyId: currency.id);
  }

  Money operator +(Money other) {
    _requireSameCurrency(other);
    return Money(
      minorUnits: minorUnits + other.minorUnits,
      currencyId: currencyId,
    );
  }

  Money operator -(Money other) {
    _requireSameCurrency(other);
    return Money(
      minorUnits: minorUnits - other.minorUnits,
      currencyId: currencyId,
    );
  }

  Money operator -() {
    return Money(minorUnits: -minorUnits, currencyId: currencyId);
  }

  Decimal toMajorUnits(CurrencyDefinition currency) {
    if (currency.id != currencyId) {
      throw ArgumentError('Currency mismatch: $currencyId and ${currency.id}.');
    }

    return (Decimal.fromInt(minorUnits) /
            Decimal.fromInt(_powerOfTen(currency.decimalPlaces)))
        .toDecimal();
  }

  String toMajorUnitsString(CurrencyDefinition currency) {
    return toMajorUnits(currency).toString();
  }

  void _requireSameCurrency(Money other) {
    if (currencyId != other.currencyId) {
      throw ArgumentError(
        'Cannot combine $currencyId with ${other.currencyId}.',
      );
    }
  }

  static int _powerOfTen(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }

  @override
  String toString() => '$currencyId:$minorUnits';
}

import '../data/models/models.dart';

String formatMoney(
  Money money,
  Map<String, CurrencyDefinition> currencies,
) {
  final currency = currencies[money.currencyId];
  if (currency == null) return '—';
  final amount = money.toMajorUnits(currency).toStringAsFixed(
        currency.decimalPlaces,
      );
  return '${currency.symbol}$amount';
}

String formatDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

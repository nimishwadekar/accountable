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
  final parts = amount.split('.');
  final integerPart = parts.first;
  final sign = integerPart.startsWith('-') ? '-' : '';
  final unsigned = sign.isEmpty ? integerPart : integerPart.substring(1);
  final grouped = unsigned.replaceAllMapped(
    RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final formatted = '$sign$grouped${parts.length > 1 ? '.${parts[1]}' : ''}';
  return '${currency.symbol} $formatted';
}

String formatDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

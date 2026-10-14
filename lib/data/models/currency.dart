class CurrencyDefinition {
  const CurrencyDefinition({
    required this.id,
    required this.symbol,
    required this.decimalPlaces,
  });

  final String id;
  final String symbol;
  final int decimalPlaces;

  factory CurrencyDefinition.fromRow(Map<String, String> row) {
    final rawDecimalPlaces = row['decimal_places']?.trim();
    final decimalPlaces = rawDecimalPlaces == null || rawDecimalPlaces.isEmpty
        ? 2
        : int.tryParse(rawDecimalPlaces);
    if (decimalPlaces == null || decimalPlaces < 0) {
      throw FormatException(
        'Currency ${row['currency_id']} has a negative decimal_places value.',
      );
    }

    return CurrencyDefinition(
      id: _required(row, 'currency_id'),
      symbol: _required(row, 'currency_symbol'),
      decimalPlaces: decimalPlaces,
    );
  }

  static String _required(Map<String, String> row, String key) {
    final value = row[key]?.trim();
    if (value == null || value.isEmpty) {
      throw FormatException('Missing required currency field: $key.');
    }
    return value;
  }
}

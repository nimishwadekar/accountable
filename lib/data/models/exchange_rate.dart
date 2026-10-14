import 'package:decimal/decimal.dart';

class ExchangeRate {
  const ExchangeRate({
    required this.id,
    required this.date,
    required this.currencyId,
    required this.rateToUsd,
    required this.retrievedAt,
  });

  final String id;
  final DateTime date;
  final String currencyId;
  final Decimal rateToUsd;
  final DateTime retrievedAt;
}

import 'money.dart';

class DailyNetWorth {
  const DailyNetWorth({
    required this.id,
    required this.date,
    required this.amount,
    required this.retrievedAt,
  });

  final String id;
  final DateTime date;
  final Money amount;
  final DateTime retrievedAt;
}

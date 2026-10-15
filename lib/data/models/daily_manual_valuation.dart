import 'money.dart';

class DailyManualValuation {
  const DailyManualValuation({
    required this.id,
    required this.date,
    required this.accountId,
    required this.value,
  });

  final String id;
  final DateTime date;
  final String accountId;
  final Money value;
}

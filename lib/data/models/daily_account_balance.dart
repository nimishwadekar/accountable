import 'money.dart';

class DailyAccountBalance {
  const DailyAccountBalance({
    required this.id,
    required this.date,
    required this.accountId,
    required this.balance,
    required this.balanceUsd,
    required this.retrievedAt,
  });

  final String id;
  final DateTime date;
  final String accountId;
  final Money balance;
  final Money balanceUsd;
  final DateTime retrievedAt;
}

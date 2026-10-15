import 'money.dart';

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.accountType,
    required this.currencyId,
    required this.openingBalance,
    required this.currentBalance,
    required this.openingDate,
    required this.closingDate,
  });

  final String id;
  final String name;
  final String accountType;
  final String currencyId;
  final Money openingBalance;
  final Money currentBalance;
  final DateTime openingDate;
  final DateTime? closingDate;

  bool get isValuationAccount {
    final normalized = accountType.trim().toLowerCase();
    return normalized == 'asset' || normalized == 'liability';
  }

  bool get isLedgerAccount => !isValuationAccount;

  bool get isLiability => accountType.trim().toLowerCase() == 'liability' ||
      accountType.trim().toLowerCase() == 'credit';
}

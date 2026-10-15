import 'money.dart';

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.accountType,
    required this.currencyId,
    required this.openingBalance,
    required this.openingDate,
    required this.closingDate,
    required this.usesManualValuations,
  });

  final String id;
  final String name;
  final String accountType;
  final String currencyId;
  final Money openingBalance;
  final DateTime openingDate;
  final DateTime? closingDate;
  final bool usesManualValuations;

  bool get isValuationAccount => usesManualValuations;

  bool get hasValidManualValuationOpeningBalance =>
      !usesManualValuations || openingBalance.minorUnits == 0;

  bool get isLedgerAccount => !isValuationAccount;

  bool get isLiability =>
      accountType.trim().toLowerCase() == 'liability' ||
      accountType.trim().toLowerCase() == 'credit';
}

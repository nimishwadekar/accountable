import 'money.dart';

enum AccountType {
  cash,
  asset,
  liability;

  static AccountType parse(String value) {
    return switch (value.trim().toLowerCase()) {
      'cash' => AccountType.cash,
      'asset' => AccountType.asset,
      'liability' => AccountType.liability,
      _ => throw FormatException('Unsupported account_type: $value.'),
    };
  }

  String get displayName => switch (this) {
    AccountType.cash => 'Cash',
    AccountType.asset => 'Asset',
    AccountType.liability => 'Liability',
  };
}

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

  AccountType get accountTypeKind => AccountType.parse(accountType);

  bool get isValuationAccount => usesManualValuations;

  bool get hasValidManualValuationOpeningBalance =>
      !usesManualValuations || openingBalance.minorUnits == 0;

  bool get isLedgerAccount => !isValuationAccount;

  bool get isLiability => accountTypeKind == AccountType.liability;
}

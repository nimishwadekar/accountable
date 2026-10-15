import 'models/models.dart';

class AccountBalanceCalculator {
  const AccountBalanceCalculator();

  Map<String, Money> calculate({
    required Iterable<Account> accounts,
    required Iterable<Transaction> transactions,
  }) {
    final balances = <String, Money>{
      for (final account in accounts) account.id: account.openingBalance,
    };

    for (final transaction in transactions) {
      if (transaction.sourceAccountId != null &&
          transaction.sourceAmount != null) {
        final accountId = transaction.sourceAccountId!;
        final balance = balances[accountId];
        if (balance == null) {
          throw StateError('Unknown source account: $accountId.');
        }
        balances[accountId] = balance - transaction.sourceAmount!;
      }
      if (transaction.destinationAccountId != null &&
          transaction.destinationAmount != null) {
        final accountId = transaction.destinationAccountId!;
        final balance = balances[accountId];
        if (balance == null) {
          throw StateError('Unknown destination account: $accountId.');
        }
        balances[accountId] = balance + transaction.destinationAmount!;
      }
    }

    return Map.unmodifiable(balances);
  }
}

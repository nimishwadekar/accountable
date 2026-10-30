import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';

void main() {
  test('requires TRUE/FALSE and zero opening balance for manual accounts', () {
    const currencies = {
      'USD': CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2),
    };

    expect(
      () => ModelParsers.parseAccounts(
        'account_id,name,account_type,currency,opening_balance,opening_date,closing_date,uses_manual_valuations\n'
        'brokerage,Brokerage,asset,USD,100,2026-01-01,,TRUE\n',
        currencies,
      ),
      throwsFormatException,
    );
    expect(
      () => ModelParsers.parseAccounts(
        'account_id,name,account_type,currency,opening_balance,opening_date,closing_date,uses_manual_valuations\n'
        'checking,Checking,cash,USD,0,2026-01-01,,true\n',
        currencies,
      ),
      throwsFormatException,
    );
  });

  test('rejects closing dates before opening dates', () {
    const currencies = {
      'USD': CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2),
    };

    expect(
      () => ModelParsers.parseAccounts(
        'account_id,name,account_type,currency,opening_balance,opening_date,closing_date,uses_manual_valuations\n'
        'checking,Checking,cash,USD,0,2026-01-02,2026-01-01,FALSE\n',
        currencies,
      ),
      throwsFormatException,
    );
  });

  test('account type and valuation predicates preserve account semantics', () {
    const usd = CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2);
    Account account(
      String id,
      String type, {
      bool manual = false,
      int opening = 0,
    }) => Account(
      id: id,
      name: id,
      accountType: type,
      currencyId: usd.id,
      openingBalance: Money(minorUnits: opening, currencyId: usd.id),
      openingDate: DateTime.utc(2026, 1, 1),
      closingDate: null,
      usesManualValuations: manual,
    );
    final cash = account('cash', 'cash');
    final asset = account('asset', 'asset', manual: true);
    final liability = account('liability', 'liability', manual: true);

    expect(cash.accountTypeKind, AccountType.cash);
    expect(cash.accountTypeKind.displayName, 'Cash');
    expect(cash.isLedgerAccount, isTrue);
    expect(cash.isLiability, isFalse);
    expect(asset.accountTypeKind.displayName, 'Asset');
    expect(asset.isValuationAccount, isTrue);
    expect(asset.hasValidManualValuationOpeningBalance, isTrue);
    expect(liability.accountTypeKind.displayName, 'Liability');
    expect(liability.isLiability, isTrue);
    expect(liability.isLedgerAccount, isFalse);
    expect(
      account(
        'invalid-manual',
        'asset',
        manual: true,
        opening: 1,
      ).hasValidManualValuationOpeningBalance,
      isFalse,
    );
  });
}

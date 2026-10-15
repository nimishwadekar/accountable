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
}

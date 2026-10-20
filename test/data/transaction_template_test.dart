import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';

void main() {
  test('parses partially completed transaction templates', () {
    const currencies = {
      'USD': CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2),
    };
    final accounts = {
      'checking': Account(
        id: 'checking',
        name: 'Checking',
        accountType: 'cash',
        currencyId: 'USD',
        openingBalance: Money.zero(currencies['USD']!),
        openingDate: DateTime.utc(2026, 1, 1),
        closingDate: null,
        usesManualValuations: false,
      ),
    };
    final templates = ModelParsers.parseTransactionTemplates(
      'template_id,name,transaction_type,date,description,category,tag,source_account_id,source_amount,dest_account_id,dest_amount,created_at,updated_at\n'
      'coffee,Coffee,expense,,Morning,dining,,checking,4.50,,,2026-10-20T00:00:00Z,2026-10-20T00:00:00Z\n',
      accounts: accounts,
      currencies: currencies,
    );

    expect(templates.single.name, 'Coffee');
    expect(templates.single.sourceAmount?.minorUnits, 450);
    expect(templates.single.date, isNull);
    expect(templates.single.tagId, isNull);
  });
}

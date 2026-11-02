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
      'coffee,Coffee,expense,,Morning,food_drink,,checking,4.50,,,2026-10-20T00:00:00Z,2026-10-20T00:00:00Z\n',
      accounts: accounts,
      currencies: currencies,
    );

    expect(templates.single.name, 'Coffee');
    expect(templates.single.sourceAmount?.minorUnits, 450);
    expect(templates.single.date, isNull);
    expect(templates.single.tagId, isNull);
    expect(templates.single.isFavorite, isFalse);
  });

  test('parses a favorite flag and defaults a missing flag to false', () {
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
    final template = ModelParsers.parseTransactionTemplates(
      'template_id,name,transaction_type,date,description,category,tag,source_account_id,source_amount,dest_account_id,dest_amount,created_at,updated_at,is_favorite\n'
      'favorite,Coffee,expense,,Coffee,food_drink,boston,checking,4.50,,,2026-10-20T00:00:00Z,2026-10-20T00:00:00Z,TRUE',
      accounts: accounts,
      currencies: currencies,
    ).single;

    expect(template.isFavorite, isTrue);
  });

  test('reports populated fields and updates template names', () {
    final now = DateTime.utc(2026, 10, 20);
    final template = TransactionTemplate(
      id: 'template',
      name: 'Coffee',
      type: TransactionType.expense,
      date: now,
      description: 'Morning coffee',
      categoryId: 'food_drink',
      tagId: 'home',
      sourceAccountId: 'checking',
      sourceAmount: const Money(minorUnits: 450, currencyId: 'USD'),
      createdAt: now,
      updatedAt: now,
    );

    expect(template.hasDescription, isTrue);
    expect(template.hasCategory, isTrue);
    expect(template.hasTag, isTrue);
    expect(template.hasSourceAccount, isTrue);
    expect(template.hasSourceAmount, isTrue);
    expect(template.hasDestinationAccount, isFalse);
    expect(template.hasDestinationAmount, isFalse);
    expect(template.copyWith(name: 'Lunch').name, 'Lunch');
    expect(template.copyWith(isFavorite: true).isFavorite, isTrue);
  });

  test('parses and round-trips encoded field options and nested description choices', () {
    const usd = CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2);
    final accounts = {
      for (final id in ['checking', 'savings'])
        id: Account(
          id: id,
          name: id,
          accountType: 'cash',
          currencyId: 'USD',
          openingBalance: Money.zero(usd),
          openingDate: DateTime.utc(2026, 1, 1),
          closingDate: null,
          usesManualValuations: false,
        ),
    };
    final header = RuntimeTableSchemas.transactionTemplates.headers.join(',');
    final source = [
      header,
      'options,Choice,transfer,2026-10-20;^2026-10-21,'
          '^Coffee at {Merchant~Cafe;^Office};Lunch at {Place},'
          'food_drink;^shopping,home;^work,checking;^savings,4.50;^8.25,'
          'checking;^savings,10.00;^15.00,'
          '2026-10-20T00:00:00Z,2026-10-20T00:00:00Z,FALSE',
    ].join('\n');

    final template = ModelParsers.parseTransactionTemplates(
      source,
      accounts: accounts,
      currencies: {'USD': usd},
    ).single;

    expect(template.dateOptions.map((option) => option.value), [
      DateTime.utc(2026, 10, 20),
      DateTime.utc(2026, 10, 21),
    ]);
    expect(template.dateOptions.map((option) => option.isDefault), [
      false,
      true,
    ]);
    expect(template.descriptionOptions.map((option) => option.isDefault), [
      true,
      false,
    ]);
    final pattern = TransactionDescriptionPattern.parse(
      template.descriptionOptions.first.value,
    );
    expect(pattern.placeholders, ['Merchant']);
    expect(
      pattern.placeholderOptions['Merchant']!.map((option) => option.value),
      ['Cafe', 'Office'],
    );
    expect(
      pattern.placeholderOptions['Merchant']!.map((option) => option.isDefault),
      [false, true],
    );
    expect(template.categoryId, 'shopping');
    expect(template.tagId, 'work');
    expect(template.sourceAccountId, 'savings');
    expect(template.sourceAmount?.minorUnits, 825);
    expect(template.destinationAccountId, 'savings');
    expect(template.destinationAmount?.minorUnits, 1500);

    final row = TransactionTemplateCodec.encodeRow(
      template,
      accounts: accounts,
      currencies: {'USD': usd},
    );
    final reparsed = ModelParsers.parseTransactionTemplates(
      '$header\n${row.join(',')}',
      accounts: accounts,
      currencies: {'USD': usd},
    ).single;
    expect(reparsed.dateOptions.map((option) => option.isDefault), [
      false,
      true,
    ]);
    expect(
      reparsed.descriptionOptions.map((option) => option.value),
      template.descriptionOptions.map((option) => option.value),
    );
    expect(reparsed.sourceAmountOptions.map((option) => option.value), [
      '4.50',
      '8.25',
    ]);
    expect(reparsed.sourceAmountOptions.map((option) => option.isDefault), [
      false,
      true,
    ]);
    expect(reparsed.destinationAccountOptions.map((option) => option.value), [
      'checking',
      'savings',
    ]);
    expect(reparsed.destinationAmountOptions.map((option) => option.value), [
      '10.00',
      '15.00',
    ]);
  });

  test('rejects duplicate options and multiple defaults', () {
    expect(
      () => parseTemplateOptions('checking;checking', fieldName: 'account'),
      throwsFormatException,
    );
    expect(
      () =>
          parseTemplateOptions('checking;^savings;^cash', fieldName: 'account'),
      throwsFormatException,
    );
    expect(
      () => TransactionTemplateCodec.parseDescriptionOptions(
        'First at {Place~Cafe;^Office;^Home}',
      ),
      throwsFormatException,
    );
  });
}

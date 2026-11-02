import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/pages/transaction_form.dart';
import 'package:accountable/app/pages/account_visuals.dart';
import 'package:accountable/app/pages/category_visuals.dart';
import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDataSnapshot fixtureData;
  setUpAll(() async {
    fixtureData = await AssetAppDataRepository().load();
  });

  testWidgets('type chooser displays all supported transaction types', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: TransactionTypeChooser()),
      ),
    );

    expect(find.text('New Transaction'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.text('Expense'), findsOneWidget);
    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Reimbursement'), findsOneWidget);
    expect(find.text('Transfer'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'template browser groups, favorites, searches, and updates favorites',
    (tester) async {
      final source = fixtureData;
      final now = DateTime.utc(2026, 10, 20);
      TransactionTemplate template(
        String id,
        String name, {
        String? categoryId,
        TransactionType type = TransactionType.expense,
        bool favorite = false,
      }) => TransactionTemplate(
        id: id,
        name: name,
        type: type,
        categoryId: categoryId,
        isFavorite: favorite,
        createdAt: now,
        updatedAt: now,
      );
      final data = AppDataSnapshot(
        accounts: source.accounts,
        categories: source.categories,
        currencies: source.currencies,
        tags: source.tags,
        transactions: source.transactions,
        exchangeRates: source.exchangeRates,
        dailyAccountBalances: source.dailyAccountBalances,
        dailyNetWorth: source.dailyNetWorth,
        dailyManualValuations: source.dailyManualValuations,
        transactionTemplates: [
          template(
            'favorite-z',
            'Zebra',
            categoryId: 'food_drink',
            favorite: true,
          ),
          template('regular-a', 'Alpha', categoryId: 'groceries'),
          template('favorite-b', 'Bravo', categoryId: 'bills', favorite: true),
          template('income', 'Salary Template', type: TransactionType.income),
        ],
      );
      TransactionTemplate? updatedTemplate;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: TransactionTemplateBrowser(
              data: data,
              onTemplateUpdated: (template) async {
                updatedTemplate = template;
              },
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Dining'), findsOneWidget);
      expect(find.text('INCOME'), findsOneWidget);
      expect(find.text('New Transaction'), findsOneWidget);
      expect(find.text('Create Template'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Zebra')).dy,
        lessThan(tester.getTopLeft(find.text('Bravo')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Bravo')).dy,
        lessThan(tester.getTopLeft(find.text('Alpha')).dy),
      );

      await tester.tap(find.byTooltip('Add favorite: Alpha'));
      await tester.pump();
      expect(updatedTemplate?.id, 'regular-a');
      expect(updatedTemplate?.isFavorite, isTrue);

      await tester.enterText(find.byType(TextField), 'Groceries');
      await tester.pump();
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Groceries'), findsNWidgets(2));
      expect(find.text('Zebra'), findsNothing);
      FocusManager.instance.primaryFocus?.unfocus();
      tester.testTextInput.hide();
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('New Transaction advances to type and entry form in one dialog', (
    tester,
  ) async {
    final data = fixtureData;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560, maxHeight: 540),
              child: TransactionEntryFlowDialog(
                data: data,
                onTemplateUpdated: (_) async {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'New Transaction'));
    await tester.pump();
    expect(find.text('Transaction Type'), findsOneWidget);

    await tester.tap(find.text('Expense'));
    await tester.pump();
    expect(find.byType(TransactionEntryFlowDialog), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('same-currency source fees reduce the transferred amount', () {
    const usd = CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2);
    final amounts = calculateTransferAmounts(
      sameCurrency: true,
      sourceAmount: Money.fromMajorUnits(value: '100', currency: usd),
      destinationAmount: Money.fromMajorUnits(value: '100', currency: usd),
      sourceFee: Money.fromMajorUnits(value: '3', currency: usd),
    );

    expect(amounts.source?.minorUnits, 9700);
    expect(amounts.destination?.minorUnits, 9700);
  });

  test('cross-currency source fees only reduce the source amount', () {
    const usd = CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2);
    const inr = CurrencyDefinition(id: 'INR', symbol: '₹', decimalPlaces: 2);
    final amounts = calculateTransferAmounts(
      sameCurrency: false,
      sourceAmount: Money.fromMajorUnits(value: '100', currency: usd),
      destinationAmount: Money.fromMajorUnits(value: '8300', currency: inr),
      sourceFee: Money.fromMajorUnits(value: '3', currency: usd),
    );

    expect(amounts.source?.minorUnits, 9700);
    expect(amounts.destination?.minorUnits, 830000);
  });

  test('account cash icon uses the currency table symbol', () {
    const inr = CurrencyDefinition(id: 'INR', symbol: '₹', decimalPlaces: 2);
    final account = Account(
      id: 'cash',
      name: 'Cash',
      accountType: 'cash',
      currencyId: 'INR',
      openingBalance: Money.zero(inr),
      openingDate: DateTime.utc(2026, 1, 1),
      closingDate: null,
      usesManualValuations: false,
    );
    expect(accountTypeLabel(account), 'Cash');
    expect(accountTypeColor(account), isNotNull);
  });

  test('category icon mapping uses category semantics', () {
    const foodDrink = Category(
      id: 'food_drink',
      name: 'Food & Drink',
      allowedTransactionTypes: {},
    );
    const personalCare = Category(
      id: 'personal_care',
      name: 'Personal Care',
      allowedTransactionTypes: {},
    );

    expect(categoryIcon(foodDrink), Icons.restaurant);
    expect(categoryIcon(personalCare), Icons.spa);
    expect(
      categoryIcon(
        const Category(id: 'bills', name: 'Bills', allowedTransactionTypes: {}),
      ),
      Icons.note_alt,
    );
    expect(
      categoryIcon(
        const Category(
          id: 'travel',
          name: 'Travel',
          allowedTransactionTypes: {},
        ),
      ),
      Icons.directions_car,
    );
    expect(
      categoryIcon(
        const Category(
          id: 'nightlife',
          name: 'Nightlife',
          allowedTransactionTypes: {},
        ),
      ),
      Icons.wine_bar,
    );
    expect(
      categoryIcon(
        const Category(id: 'gifts', name: 'Gifts', allowedTransactionTypes: {}),
      ),
      Icons.card_giftcard,
    );
    expect(
      categoryIcon(
        const Category(
          id: 'groceries',
          name: 'Groceries',
          allowedTransactionTypes: {},
        ),
      ),
      Icons.eco,
    );
    expect(
      categoryColor(foodDrink),
      isNot(equals(categoryColor(personalCare))),
    );
    expect(
      categoryIcon(
        const Category(
          id: 'loan_repayment',
          name: 'Loan Repayment',
          allowedTransactionTypes: {TransactionType.transfer},
        ),
      ),
      Icons.account_balance,
    );
    expect(
      categoryIcon(
        const Category(
          id: 'credit_repayment',
          name: 'Credit Repayment',
          allowedTransactionTypes: {TransactionType.transfer},
        ),
      ),
      Icons.credit_card,
    );
    expect(
      categoryIcon(
        const Category(
          id: 'emergency_fund',
          name: 'Emergency Fund',
          allowedTransactionTypes: {TransactionType.transfer},
        ),
      ),
      Icons.health_and_safety,
    );
    expect(
      categoryIcon(
        const Category(
          id: 'general',
          name: 'General',
          allowedTransactionTypes: {TransactionType.transfer},
        ),
      ),
      Icons.swap_horiz,
    );
  });

  testWidgets('template type chooser has its own title and close action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: TransactionTypeChooser(createTemplate: true),
        ),
      ),
    );

    expect(find.text('Create Template'), findsOneWidget);
    expect(find.text('Add Transaction'), findsNothing);
    expect(find.text('Transaction Type'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('transfer templates do not show fee controls', (tester) async {
    const usd = CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2);
    final account = Account(
      id: 'checking',
      name: 'Checking',
      accountType: 'cash',
      currencyId: usd.id,
      openingBalance: Money.zero(usd),
      openingDate: DateTime.utc(2026, 1, 1),
      closingDate: null,
      usesManualValuations: false,
    );
    final data = AppDataSnapshot(
      accounts: [account],
      categories: const [],
      currencies: [usd],
      tags: const [],
      transactions: const [],
      exchangeRates: const [],
      dailyAccountBalances: const [],
      dailyNetWorth: const [],
      dailyManualValuations: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: TransactionFormSheet(
            type: TransactionType.transfer,
            data: data,
            createTemplate: true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Source Account Fee'), findsNothing);
    expect(find.text('Destination Account Fee'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('expense form places description first and requires tag', (
    tester,
  ) async {
    final data = fixtureData;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: TransactionFormSheet(type: TransactionType.expense, data: data),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Tag'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('Source Account'), findsNothing);
    expect(find.text('Source Amount'), findsNothing);
    expect(find.text('Tag (optional)'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('groups large transaction amounts while typing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: TransactionFormSheet(
            type: TransactionType.expense,
            data: fixtureData,
          ),
        ),
      ),
    );

    final amountField = find.widgetWithText(TextFormField, 'Amount');
    await tester.enterText(amountField, '1234567.89');

    expect(
      tester.widget<TextFormField>(amountField).controller!.text,
      '1,234,567.89',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('template entry hides fixed values and asks for placeholders', (
    tester,
  ) async {
    final source = fixtureData;
    final now = DateTime.utc(2026, 10, 20);
    final template = TransactionTemplate(
      id: 'coffee-template',
      name: 'Coffee',
      type: TransactionType.expense,
      description: 'Coffee at {Merchant}',
      categoryId: 'food_drink',
      tagId: 'boston',
      sourceAccountId: 'chase_checking',
      sourceAmount: Money.fromMajorUnits(
        value: '4.50',
        currency: source.currenciesById['USD']!,
      ),
      isFavorite: true,
      createdAt: now,
      updatedAt: now,
    );
    final data = AppDataSnapshot(
      accounts: source.accounts,
      categories: source.categories,
      currencies: source.currencies,
      tags: source.tags,
      transactions: source.transactions,
      exchangeRates: source.exchangeRates,
      dailyAccountBalances: source.dailyAccountBalances,
      dailyNetWorth: source.dailyNetWorth,
      dailyManualValuations: source.dailyManualValuations,
      transactionTemplates: [template],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: TransactionFormSheet(
            type: template.type,
            data: data,
            template: template,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Coffee'), findsOneWidget);
    expect(find.text('Account: Chase Checking'), findsOneWidget);
    expect(find.textContaining('Amount:'), findsOneWidget);
    expect(find.text('Merchant'), findsOneWidget);
    expect(find.text('Description: Coffee at {Merchant}'), findsOneWidget);
    expect(find.text('Account'), findsNothing);
    expect(find.text('Amount'), findsNothing);
    expect(find.text('Category'), findsNothing);
    expect(find.text('Tag'), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Merchant'),
      'Cafe Luna',
    );
    await tester.pump();
    expect(find.text('Description: Coffee at Cafe Luna'), findsOneWidget);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'template builder saves ordered description options and default',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final source = fixtureData;
      TransactionTemplate? created;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: TransactionFormSheet(
              type: TransactionType.expense,
              data: source,
              createTemplate: true,
              onResult: (result) => created = result as TransactionTemplate,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Date'), findsOneWidget);
      expect(find.text('Description'), findsOneWidget);
      expect(find.text('Account'), findsOneWidget);
      expect(find.text('Amount'), findsOneWidget);
      expect(find.byTooltip('Add Description option'), findsOneWidget);
      expect(find.byTooltip('Add Account option'), findsOneWidget);
      expect(find.byTooltip('Add Amount option'), findsOneWidget);
      expect(find.text('Description pattern'), findsNothing);

      await tester.enterText(find.byType(TextFormField).first, 'Cafe');
      await tester.tap(find.byTooltip('Add Description option'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('template-description-option-0')),
        'Coffee at {Merchant~Cafe;^Office}',
      );
      await tester.tap(find.text('Save Template'));
      await tester.pump();
      expect(
        find.text(
          'Enter placeholder names as {Name}; add their choices below the description.',
        ),
        findsOneWidget,
      );
      expect(created, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('template-description-option-0')),
        'Coffee at {Merchant}',
      );
      await tester.pump();
      expect(find.text('Merchant'), findsOneWidget);
      await tester.ensureVisible(
        find.byTooltip('Add Merchant option for description 1'),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Add Merchant option for description 1'));
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(
          const ValueKey('description-0-placeholder-Merchant-option-0'),
        ),
      );
      await tester.enterText(
        find.byKey(
          const ValueKey('description-0-placeholder-Merchant-option-0'),
        ),
        'Cafe',
      );
      await tester.ensureVisible(
        find.byTooltip('Add Merchant option for description 1'),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Add Merchant option for description 1'));
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(
          const ValueKey('description-0-placeholder-Merchant-option-1'),
        ),
      );
      await tester.enterText(
        find.byKey(
          const ValueKey('description-0-placeholder-Merchant-option-1'),
        ),
        'Office',
      );
      await tester.ensureVisible(find.byType(Checkbox).last);
      await tester.pump();
      final placeholderDefaultLabel = find.text('Default').last;
      expect(tester.widget<Text>(placeholderDefaultLabel).maxLines, 1);
      expect(tester.widget<Text>(placeholderDefaultLabel).softWrap, isFalse);
      await tester.tap(find.byType(Checkbox).last);
      await tester.pump();
      await tester.ensureVisible(find.byTooltip('Add Description option'));
      await tester.pump();
      await tester.tap(find.byTooltip('Add Description option'));
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('template-description-option-1')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('template-description-option-1')),
        'Lunch at {Place}',
      );
      await tester.ensureVisible(find.byType(CheckboxListTile).first);
      await tester.pump();
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();
      await tester.tap(find.text('Save Template'));
      await tester.pump();

      expect(created, isNotNull);
      expect(created!.name, 'Cafe');
      expect(created!.descriptionOptions.map((option) => option.value), [
        'Coffee at {Merchant~Cafe;^Office}',
        'Lunch at {Place}',
      ]);
      expect(created!.descriptionOptions.map((option) => option.isDefault), [
        true,
        false,
      ]);
      expect(created!.effectiveSourceAccountOptions, isEmpty);
      expect(created!.sourceAmountOptions, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'template option defaults apply and placeholder dropdowns remain editable',
    (tester) async {
      final source = fixtureData;
      final now = DateTime.utc(2026, 10, 20);
      final usd = source.currenciesById['USD']!;
      final template = TransactionTemplate(
        id: 'choice-template',
        name: 'Coffee choices',
        type: TransactionType.expense,
        date: now,
        dateOptions: [
          TemplateOption(value: now.subtract(const Duration(days: 1))),
          TemplateOption(value: now, isDefault: true),
        ],
        description: 'Coffee at {Merchant~Cafe;^Office}',
        descriptionOptions: [
          const TemplateOption(
            value: 'Coffee at {Merchant~Cafe;^Office}',
            isDefault: true,
          ),
          const TemplateOption(value: 'Lunch at {Place}'),
        ],
        categoryId: 'groceries',
        categoryOptions: const [
          TemplateOption(value: 'food_drink'),
          TemplateOption(value: 'groceries', isDefault: true),
        ],
        tagId: 'boston',
        sourceAccountId: 'chase_checking',
        sourceAmount: Money.fromMajorUnits(value: '4.50', currency: usd),
        sourceAmountOptions: const [TemplateOption(value: '4.50')],
        createdAt: now,
        updatedAt: now,
      );
      Transaction? created;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: TransactionFormSheet(
              type: template.type,
              data: source,
              template: template,
              onResult: (result) => created = result as Transaction,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('template-description-options')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('placeholder-options-Merchant')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('template-date-options')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('template-category-options')),
        findsOneWidget,
      );
      expect(find.text('Office'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('placeholder-options-Merchant')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cafe').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Transaction'));
      await tester.pump();

      expect(created, isNotNull);
      expect(created!.description, 'Coffee at Cafe');
      expect(created!.sourceAmount?.minorUnits, 450);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('multi-option fields without a default require a selection', (
    tester,
  ) async {
    final source = fixtureData;
    final now = DateTime.utc(2026, 10, 20);
    final usd = source.currenciesById['USD']!;
    final template = TransactionTemplate(
      id: 'no-default-template',
      name: 'Choose description',
      type: TransactionType.expense,
      date: now,
      descriptionOptions: const [
        TemplateOption(value: 'Coffee'),
        TemplateOption(value: 'Lunch'),
      ],
      categoryId: 'food_drink',
      tagId: 'boston',
      sourceAccountId: 'chase_checking',
      sourceAmount: Money.fromMajorUnits(value: '4.50', currency: usd),
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: TransactionFormSheet(
            type: template.type,
            data: source,
            template: template,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Add Transaction'));
    await tester.pump();
    expect(find.text('Choose a description.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('template fields without options remain normal entry fields', (
    tester,
  ) async {
    final source = fixtureData;
    final now = DateTime.utc(2026, 10, 10);
    final template = TransactionTemplate(
      id: 'empty-template',
      name: 'Fill each time',
      type: TransactionType.expense,
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: TransactionFormSheet(
            type: template.type,
            data: source,
            template: template,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.widgetWithText(TextFormField, 'Description'), findsOneWidget);
    expect(find.byIcon(Icons.calendar_today_outlined), findsOneWidget);
    expect(find.text('Select account'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Amount'), findsOneWidget);
    expect(find.text('Select category'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String?>), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('ordinary descriptions reject the reserved option characters', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: TransactionFormSheet(
            type: TransactionType.expense,
            data: fixtureData,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Description'),
      'Coffee; cake',
    );
    await tester.tap(find.text('Add Transaction'));
    await tester.pump();

    expect(
      find.text(
        'The characters ;, ^, and ~ are reserved for template options.',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('entry form avoids flex overflow during tiny viewport layouts', (
    tester,
  ) async {
    for (final size in [const Size(1, 1), const Size(390, 160)]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: TransactionFormSheet(
                  type: TransactionType.expense,
                  data: fixtureData,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: '${size.width}x${size.height}',
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('account and amount option choices use the selected currency', (
    tester,
  ) async {
    final source = fixtureData;
    final now = DateTime.utc(2026, 10, 10);
    final usd = source.currenciesById['USD']!;
    final template = TransactionTemplate(
      id: 'currency-choice-template',
      name: 'Choose account and amount',
      type: TransactionType.expense,
      date: now,
      description: 'Purchase',
      categoryId: 'food_drink',
      tagId: 'boston',
      sourceAccountId: 'chase_checking',
      sourceAccountOptions: const [
        TemplateOption(value: 'chase_checking', isDefault: true),
        TemplateOption(value: 'sbi_nro'),
      ],
      sourceAmount: Money.fromMajorUnits(value: '8.25', currency: usd),
      sourceAmountOptions: const [
        TemplateOption(value: '4.50'),
        TemplateOption(value: '8.25', isDefault: true),
      ],
      createdAt: now,
      updatedAt: now,
    );
    Transaction? created;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: TransactionFormSheet(
            type: template.type,
            data: source,
            template: template,
            onResult: (result) => created = result as Transaction,
          ),
        ),
      ),
    );
    await tester.pump();

    final accountDropdown = find.byKey(
      const ValueKey('template-account-options-Account'),
    );
    final amountDropdown = find.byKey(
      const ValueKey('template-amount-options-Amount'),
    );
    expect(accountDropdown, findsOneWidget);
    expect(amountDropdown, findsOneWidget);
    await tester.tap(accountDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('SBI NRO · INR').last);
    await tester.pumpAndSettle();
    expect(find.text('SBI NRO · INR'), findsOneWidget);
    await tester.tap(amountDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('4.50').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Transaction'));
    await tester.pump();

    expect(created, isNotNull);
    expect(created!.sourceAccountId, 'sbi_nro');
    expect(created!.sourceAmount!.currencyId, 'INR');
    expect(created!.sourceAmount!.minorUnits, 450);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'same-currency transfer template preserves a saved destination amount',
    (tester) async {
      final source = fixtureData;
      final now = DateTime.utc(2026, 10, 20);
      final usd = source.currenciesById['USD']!;
      final template = TransactionTemplate(
        id: 'same-currency-transfer',
        name: 'Card Payment',
        type: TransactionType.transfer,
        date: null,
        description: 'Card payment',
        categoryId: 'general',
        tagId: 'boston',
        sourceAccountId: 'chase_checking',
        destinationAccountId: 'chase_freedom_rise',
        destinationAmount: Money.fromMajorUnits(value: '50', currency: usd),
        createdAt: now,
        updatedAt: now,
      );
      final data = AppDataSnapshot(
        accounts: source.accounts,
        categories: source.categories,
        currencies: source.currencies,
        tags: source.tags,
        transactions: source.transactions,
        exchangeRates: source.exchangeRates,
        dailyAccountBalances: source.dailyAccountBalances,
        dailyNetWorth: source.dailyNetWorth,
        dailyManualValuations: source.dailyManualValuations,
      );
      List<Transaction>? created;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  final result = await showDialog<Object>(
                    context: context,
                    builder: (context) => Dialog(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: TransactionFormSheet(
                          type: TransactionType.transfer,
                          data: data,
                          template: template,
                        ),
                      ),
                    ),
                  );
                  if (result is List<Transaction>) created = result;
                },
                child: const Text('Open form'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();

      expect(find.text('Card Payment'), findsOneWidget);
      expect(find.text('Source Amount'), findsNothing);
      expect(find.text('Destination Amount'), findsNothing);
      expect(find.text('Source Account'), findsNothing);
      expect(find.text('Destination Account'), findsNothing);

      await tester.ensureVisible(find.text('Add Transaction'));
      await tester.tap(find.text('Add Transaction'));
      await tester.pumpAndSettle();
      expect(created, hasLength(1));
      expect(created!.single.sourceAmount?.minorUnits, 5000);
      expect(created!.single.destinationAmount?.minorUnits, 5000);
      expect(created!.single.sourceAccountId, 'chase_checking');
      expect(created!.single.destinationAccountId, 'chase_freedom_rise');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

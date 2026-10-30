import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const usd = CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2);
  const inr = CurrencyDefinition(id: 'INR', symbol: '₹', decimalPlaces: 2);
  final currencies = {'USD': usd, 'INR': inr};
  final checking = _account('checking', usd);
  final savings = _account('savings', inr);
  final accounts = {checking.id: checking, savings.id: savings};
  const incomeCategory = Category(
    id: 'salary',
    name: 'Salary',
    allowedTransactionTypes: {TransactionType.income},
  );
  const expenseCategory = Category(
    id: 'expense',
    name: 'Expense',
    allowedTransactionTypes: {TransactionType.expense},
  );
  const transferCategory = Category(
    id: 'transfer',
    name: 'Transfer',
    allowedTransactionTypes: {TransactionType.transfer},
  );
  const tag = Tag(id: 'tag', name: 'Tag');

  test(
    'income allocation parsing preserves account currency and date bounds',
    () {
      final rows = [
        [
          'alloc-1',
          'Monthly savings',
          'salary',
          'checking',
          'transfer',
          '12.34',
          '2026-01-01',
          '',
          '2026-01-01T00:00:00Z',
          '2026-01-02T00:00:00Z',
        ],
      ];
      final parsed = ModelParsers.parseIncomeAllocations(
        _table(RuntimeTableSchemas.incomeAllocations, rows),
        accounts: accounts,
        currencies: currencies,
        categories: {
          incomeCategory.id: incomeCategory,
          transferCategory.id: transferCategory,
        },
      );

      expect(parsed.single.expectedAmountPerIncome.minorUnits, 1234);
      expect(parsed.single.expectedAmountPerIncome.currencyId, 'USD');
      expect(parsed.single.startDate, DateTime.utc(2026, 1, 1));
      expect(parsed.single.endDate, isNull);
    },
  );

  test(
    'income allocations reject invalid accounts, categories, and duplicates',
    () {
      List<IncomeAllocation> parse(
        List<List<String>> rows, {
        Map<String, Account>? accountMap,
        Map<String, Category>? categoryMap,
      }) => ModelParsers.parseIncomeAllocations(
        _table(RuntimeTableSchemas.incomeAllocations, rows),
        accounts: accountMap ?? accounts,
        currencies: currencies,
        categories:
            categoryMap ??
            {
              incomeCategory.id: incomeCategory,
              transferCategory.id: transferCategory,
            },
      );

      List<String> row({
        String id = 'alloc-1',
        String categoryId = 'salary',
        String accountId = 'checking',
        String transferId = 'transfer',
      }) => [
        id,
        'Monthly savings',
        categoryId,
        accountId,
        transferId,
        '12.34',
        '2026-01-01',
        '',
        '2026-01-01T00:00:00Z',
        '2026-01-02T00:00:00Z',
      ];
      expect(
        () => parse([row(accountId: 'missing-account')]),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('unknown income account'),
          ),
        ),
      );
      expect(
        () => parse(
          [row(categoryId: 'expense')],
          categoryMap: {
            expenseCategory.id: expenseCategory,
            transferCategory.id: transferCategory,
          },
        ),
        throwsFormatException,
      );
      expect(
        () => parse(
          [row(transferId: 'salary')],
          categoryMap: {
            incomeCategory.id: incomeCategory,
            transferCategory.id: transferCategory,
          },
        ),
        throwsFormatException,
      );
      expect(
        () => parse([row(), row(id: 'alloc-2')]),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Duplicate income allocation transfer category'),
          ),
        ),
      );
    },
  );

  test('display preferences enforce visibility and supported entity types', () {
    final preferences = ModelParsers.parseDisplayPreferences(
      _table(RuntimeTableSchemas.displayPreferences, [
        ['account', 'checking', '0', 'TRUE', 'TRUE'],
      ]),
    );
    expect(preferences.single.showInApp, isTrue);
    expect(preferences.single.showInEntryForms, isTrue);

    expect(
      () => ModelParsers.parseDisplayPreferences(
        _table(RuntimeTableSchemas.displayPreferences, [
          ['account', 'checking', '0', 'FALSE', 'TRUE'],
        ]),
      ),
      throwsFormatException,
    );
    expect(
      () => ModelParsers.parseDisplayPreferences(
        _table(RuntimeTableSchemas.displayPreferences, [
          ['currency', 'USD', '0', 'TRUE', 'FALSE'],
        ]),
      ),
      throwsFormatException,
    );
    expect(
      () => ModelParsers.parseDisplayPreferences(
        _table(RuntimeTableSchemas.displayPreferences, [
          ['account', 'checking', '0', 'maybe', 'FALSE'],
        ]),
      ),
      throwsFormatException,
    );
  });

  test('achievement settings require exactly one correctly named date row', () {
    expect(
      ModelParsers.parseAchievementSettings(
        _table(RuntimeTableSchemas.achievementSettings, [
          ['2026-01-01'],
        ]),
      ).trackingStartDate,
      DateTime.utc(2026, 1, 1),
    );
    expect(
      () => ModelParsers.parseAchievementSettings('wrong_header\n2026-01-01\n'),
      throwsFormatException,
    );
    expect(
      () => ModelParsers.parseAchievementSettings(
        _table(RuntimeTableSchemas.achievementSettings, [
          ['2026-01-01'],
          ['2026-02-01'],
        ]),
      ),
      throwsFormatException,
    );
  });

  test(
    'transaction templates parse both currency legs and reject orphan amounts',
    () {
      final template = ModelParsers.parseTransactionTemplates(
        _table(RuntimeTableSchemas.transactionTemplates, [
          [
            'cross-currency',
            'International transfer',
            'transfer',
            '',
            'Monthly transfer',
            'transfer',
            'tag',
            'checking',
            '12.34',
            'savings',
            '56.78',
            '2026-01-01T00:00:00Z',
            '2026-01-02T00:00:00Z',
            'TRUE',
          ],
        ]),
        accounts: accounts,
        currencies: currencies,
      ).single;

      expect(template.sourceAmount?.minorUnits, 1234);
      expect(template.sourceAmount?.currencyId, 'USD');
      expect(template.destinationAmount?.minorUnits, 5678);
      expect(template.destinationAmount?.currencyId, 'INR');
      expect(template.isFavorite, isTrue);

      final orphanedAmount = [
        'orphan',
        'Broken template',
        'expense',
        '',
        '',
        'expense',
        'tag',
        '',
        '1.00',
        '',
        '',
        '2026-01-01T00:00:00Z',
        '2026-01-02T00:00:00Z',
        'FALSE',
      ];
      expect(
        () => ModelParsers.parseTransactionTemplates(
          _table(RuntimeTableSchemas.transactionTemplates, [orphanedAmount]),
          accounts: accounts,
          currencies: currencies,
        ),
        throwsFormatException,
      );
    },
  );

  test('strict migration parsing assigns deterministic IDs and timestamps', () {
    final parsed = ModelParsers.parseMigrationTransactions(
      _table(RuntimeTableSchemas.transactionsToMigrate, [
        [
          '',
          '2026-01-10',
          'Historical groceries',
          'expense',
          'expense',
          '5',
          'checking',
          '',
          '',
          'tag',
          '',
        ],
      ]),
      accounts: accounts,
      currencies: currencies,
      categories: {expenseCategory.id: expenseCategory},
      tags: {tag.id: tag},
    );

    expect(parsed.single.id, 'migration-pending-2');
    expect(
      parsed.single.createdAt,
      DateTime.utc(2026, 1, 10).add(const Duration(microseconds: 2)),
    );
  });

  test(
    'issue parsers retain valid rows and report malformed financial references',
    () {
      final result = ModelParsers.parseAccountsWithIssues(
        _table(RuntimeTableSchemas.accounts, [
          [
            'checking',
            'Checking',
            'cash',
            'USD',
            '10.00',
            '2026-01-01',
            '',
            'FALSE',
          ],
          [
            'broken',
            'Broken',
            'cash',
            'XXX',
            '10.00',
            '2026-01-01',
            '',
            'FALSE',
          ],
        ]),
        currencies,
      );

      expect(result.values.map((account) => account.id), ['checking']);
      expect(result.issues, hasLength(1));
      expect(result.issues.single.row, 3);
      expect(result.issues.single.message, contains('Unknown currency: XXX.'));
      expect(
        result.issues.single.technicalDetails,
        contains('FormatException'),
      );
    },
  );

  test(
    'historical valuation parsers reject unknown and non-valuation accounts',
    () {
      final accountRows = ModelParsers.parseDailyAccountBalancesWithIssues(
        _table(RuntimeTableSchemas.dailyAccountBalances, [
          [
            '2026-01-01-missing',
            '2026-01-01',
            'missing',
            '1.00',
            '1.00',
            '2026-01-01T00:00:00Z',
          ],
        ]),
        accounts: accounts,
        currencies: currencies,
      );
      final valuationRows = ModelParsers.parseDailyManualValuationsWithIssues(
        _table(RuntimeTableSchemas.dailyManualValuations, [
          ['unknown', '2026-01-01', 'missing', '1.00'],
          ['ledger', '2026-01-01', 'checking', '1.00'],
        ]),
        accounts: accounts,
        currencies: currencies,
      );

      expect(accountRows.values, isEmpty);
      expect(
        accountRows.issues.single.message,
        contains('unknown account: missing'),
      );
      expect(valuationRows.values, isEmpty);
      expect(valuationRows.issues, hasLength(2));
      expect(
        valuationRows.issues.first.message,
        contains('unknown account: missing'),
      );
      expect(
        valuationRows.issues.last.message,
        contains('non-valuation account: checking'),
      );
    },
  );

  test('issue parsers accept typed rows for every financial source table', () {
    final categoryResult = ModelParsers.parseCategoriesWithIssues(
      _table(RuntimeTableSchemas.categories, [
        ['salary', 'Salary', 'income'],
      ]),
    );
    final tagResult = ModelParsers.parseTagsWithIssues(
      _table(RuntimeTableSchemas.tags, [
        ['tag', 'Tag'],
      ]),
    );
    final preferenceResult = ModelParsers.parseDisplayPreferencesWithIssues(
      _table(RuntimeTableSchemas.displayPreferences, [
        ['account', 'checking', '0', 'TRUE', 'TRUE'],
      ]),
    );
    final transactionResult = ModelParsers.parseTransactionsWithIssues(
      _table(RuntimeTableSchemas.transactions, [
        [
          'income-1',
          '2026-01-10',
          'Paycheck',
          'salary',
          'income',
          '',
          '',
          '100.00',
          'checking',
          'tag',
          '2026-01-10T12:00:00Z',
        ],
      ]),
      accounts: accounts,
      currencies: currencies,
      categories: {incomeCategory.id: incomeCategory},
      tags: {tag.id: tag},
    );
    final exchangeRateResult = ModelParsers.parseExchangeRatesWithIssues(
      _table(RuntimeTableSchemas.dailyExchangeRates, [
        [
          '2026-01-10-USD',
          '2026-01-10',
          'USD',
          '1',
          '2026-01-10',
          '2026-01-10T12:00:00Z',
        ],
      ]),
    );
    final balanceResult = ModelParsers.parseDailyAccountBalancesWithIssues(
      _table(RuntimeTableSchemas.dailyAccountBalances, [
        [
          '2026-01-10-checking',
          '2026-01-10',
          'checking',
          '100.00',
          '100.00',
          '2026-01-10T12:00:00Z',
        ],
      ]),
      accounts: accounts,
      currencies: currencies,
    );
    final netWorthResult = ModelParsers.parseDailyNetWorthWithIssues(
      _table(RuntimeTableSchemas.dailyNetWorth, [
        ['2026-01-10-net', '2026-01-10', '100.00', '2026-01-10T12:00:00Z'],
      ]),
      currencies,
    );

    expect(categoryResult.values.single.allowedTransactionTypes, {
      TransactionType.income,
    });
    expect(tagResult.values.single.id, 'tag');
    expect(preferenceResult.values.single.showInEntryForms, isTrue);
    expect(
      transactionResult.values.single.destinationAmount?.minorUnits,
      10000,
    );
    expect(exchangeRateResult.values.single.rateToUsd.toString(), '1');
    expect(balanceResult.values.single.balance.minorUnits, 10000);
    expect(netWorthResult.values.single.amount.minorUnits, 10000);
    expect(
      [
        categoryResult,
        tagResult,
        preferenceResult,
        transactionResult,
        exchangeRateResult,
        balanceResult,
        netWorthResult,
      ].every((result) => result.issues.isEmpty),
      isTrue,
    );
  });

  test('strict transaction parsing rejects partial amounts, bad accounts, categories, and IDs', () {
    String transactionRow({
      String id = 'expense-1',
      String amount = '5',
      String accountId = 'checking',
      String categoryId = 'expense',
      String destinationAmount = '',
      String destinationAccountId = '',
    }) => _table(RuntimeTableSchemas.transactions, [
      [
        id,
        '2026-01-10',
        'Expense',
        categoryId,
        'expense',
        amount,
        accountId,
        destinationAmount,
        destinationAccountId,
        'tag',
        '2026-01-10T12:00:00Z',
      ],
    ]);

    List<Transaction> parse(
      String source, {
      Map<String, Category>? categoryMap,
    }) => ModelParsers.parseTransactions(
      source,
      accounts: accounts,
      currencies: currencies,
      categories: categoryMap,
      tags: {tag.id: tag},
    );

    expect(
      () => parse(transactionRow(accountId: 'missing')),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('unknown account: missing'),
        ),
      ),
    );
    expect(
      () => parse(
        transactionRow(categoryId: 'missing'),
        categoryMap: {incomeCategory.id: incomeCategory},
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Unknown category: missing.'),
        ),
      ),
    );
    expect(
      () => parse(
        transactionRow(destinationAmount: '5'),
        categoryMap: {expenseCategory.id: expenseCategory},
      ),
      throwsFormatException,
    );
    expect(
      () => parse(
        _table(RuntimeTableSchemas.transactions, [
          for (var index = 0; index < 2; index++)
            [
              'same-id',
              '2026-01-10',
              'Expense',
              'expense',
              'expense',
              '5',
              'checking',
              '',
              '',
              'tag',
              '2026-01-10T12:00:00Z',
            ],
        ]),
        categoryMap: {expenseCategory.id: expenseCategory},
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Duplicate ID in Transactions: same-id.'),
        ),
      ),
    );
  });

  test(
    'achievement parsers report missing USD and reject malformed strict rows',
    () {
      final missingUsd = ModelParsers.parseAchievementsWithIssues(
        _table(RuntimeTableSchemas.achievements, [
          ['target-1', 'Target', '100', 'FALSE'],
        ]),
        currencies: {'INR': inr},
      );
      expect(missingUsd.issues, isNotEmpty);
      expect(
        missingUsd.issues.single.message,
        contains('Unknown currency: USD.'),
      );

      expect(
        () => ModelParsers.parseAchievements(
          _table(RuntimeTableSchemas.achievements, [
            ['target-1', 'Target', 'not-money', 'FALSE'],
          ]),
          currencies: currencies,
        ),
        throwsFormatException,
      );
    },
  );

  test('template parsing rejects references without valid account context', () {
    final unknownAccount = [
      'unknown-account',
      'Unknown account',
      'expense',
      '',
      '',
      'expense',
      'tag',
      'missing',
      '5.00',
      '',
      '',
      '2026-01-01T00:00:00Z',
      '2026-01-02T00:00:00Z',
      'FALSE',
    ];
    expect(
      () => ModelParsers.parseTransactionTemplates(
        _table(RuntimeTableSchemas.transactionTemplates, [unknownAccount]),
        accounts: accounts,
        currencies: currencies,
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Template references unknown account: missing.'),
        ),
      ),
    );
  });
}

Account _account(String id, CurrencyDefinition currency) => Account(
  id: id,
  name: id,
  accountType: 'cash',
  currencyId: currency.id,
  openingBalance: Money.zero(currency),
  openingDate: DateTime.utc(2026, 1, 1),
  closingDate: null,
  usesManualValuations: false,
);

String _table(RuntimeTableSchema schema, List<List<String>> rows) =>
    csv.encode([schema.headers, ...rows]);

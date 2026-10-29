import 'dart:convert';
import 'dart:async';

import 'package:csv/csv.dart';
import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';

String _dateString(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('daily USD balances preserve currency minor units', () async {
    final data = await AssetAppDataRepository().load();
    final client = _FakeSheetsClient({
      'DailyExchangeRates!B:B': [
        ['rate_date'],
        ['2026-10-12'],
      ],
      'DailyAccountBalances!B:B': [
        ['balance_date'],
        ['2026-10-12'],
      ],
      'DailyNetWorth!B:B': [
        ['net_worth_date'],
        ['2026-10-12'],
      ],
    });
    final httpClient = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'rates': {'INR': 96.4},
        }),
        200,
      ),
    );

    await DailyMaintenanceService(
      client: client,
      data: data,
      httpClient: httpClient,
    ).catchUp(yesterday: DateTime.utc(2026, 10, 13));

    final checkingBalance = client.appendedRows.firstWhere(
      (row) => row.isNotEmpty && row.first == '2026-10-13-chase_checking',
    );
    expect(checkingBalance[3], '1560');
    expect(checkingBalance[4], '1560');
    expect(
      client.appendedRows.any((row) => row.first == '2026-10-13-INR'),
      isTrue,
    );
    expect(
      client.appendedRows.any((row) => row.first == '2026-10-13-sbi_nro'),
      isFalse,
    );
  });

  test('reuses successful provider dates within a rebuild only', () async {
    const usd = CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2);
    const eur = CurrencyDefinition(id: 'EUR', symbol: '€', decimalPlaces: 2);
    final account = Account(
      id: 'euro-cash',
      name: 'Euro cash',
      accountType: 'cash',
      currencyId: 'EUR',
      openingBalance: Money.fromMajorUnits(value: '100', currency: eur),
      openingDate: DateTime.utc(2026, 1, 1),
      closingDate: null,
      usesManualValuations: false,
    );
    final transaction = Transaction(
      id: 'first-euro-expense',
      createdAt: DateTime.utc(2026, 1, 2),
      date: DateTime.utc(2026, 1, 2),
      type: TransactionType.expense,
      sourceAmount: Money.fromMajorUnits(value: '1', currency: eur),
      sourceAccountId: account.id,
      destinationAmount: null,
      destinationAccountId: null,
      categoryId: null,
      tagId: null,
      description: 'Expense',
    );
    final data = AppDataSnapshot(
      accounts: [account],
      categories: const [],
      currencies: const [usd, eur],
      tags: const [],
      transactions: [transaction],
      exchangeRates: const [],
      dailyAccountBalances: const [],
      dailyNetWorth: const [],
      dailyManualValuations: const [],
    );
    final client = _FakeSheetsClient({});
    var requests = 0;
    final httpClient = MockClient((request) async {
      requests++;
      if (request.url.path.endsWith('2026-01-03') ||
          request.url.path.endsWith('2026-01-04')) {
        return http.Response('', 404);
      }
      return http.Response(
        jsonEncode({
          'rates': {'EUR': 0.9},
        }),
        200,
      );
    });
    final service = DailyMaintenanceService(
      client: client,
      data: data,
      httpClient: httpClient,
    );

    await service.rebuild(yesterday: DateTime.utc(2026, 1, 4));
    expect(
      requests,
      4,
      reason: 'the successful Friday source response is reused',
    );
    final rateRows =
        client.replacedRanges[GoogleSheetsRanges.dailyExchangeRates]!;
    expect(rateRows.skip(1).map((row) => row[4]), everyElement('2026-01-02'));

    await service.rebuild(yesterday: DateTime.utc(2026, 1, 4));
    expect(requests, 8, reason: 'a separate full rebuild fetches fresh rates');
  });

  test('historical rate requests have a finite configurable timeout', () async {
    final source = await AssetAppDataRepository().load();
    final withoutRates = _copySnapshot(source, exchangeRates: const []);
    final client = _FakeSheetsClient({});
    final pendingHttp = MockClient((_) => Completer<http.Response>().future);

    await expectLater(
      DailyMaintenanceService(
        client: client,
        data: withoutRates,
        httpClient: pendingHttp,
        httpRequestTimeout: const Duration(milliseconds: 1),
      ).rebuild(yesterday: DateTime.utc(2026, 10, 12)),
      throwsA(isA<TimeoutException>()),
    );
    expect(client.replacedRanges, isEmpty);
  });

  test('manual valuation changes replace an existing net-worth row', () async {
    final source = await AssetAppDataRepository().load();
    final targetDate = source.dailyNetWorth.first.date;
    final account = source.dailyManualValuations.first;
    final changed = DailyManualValuation(
      id: '${_dateString(targetDate)}-${account.accountId}',
      date: targetDate,
      accountId: account.accountId,
      value: Money(
        minorUnits: account.value.minorUnits + 100,
        currencyId: account.value.currencyId,
      ),
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
      dailyManualValuations: [...source.dailyManualValuations, changed],
    );
    final client = _FakeSheetsClient({});
    final usd = data.currenciesById['USD']!;
    final oldNetWorth = data
        .dailyNetWorthById['${_dateString(targetDate)}-net']
        ?.amount
        .toMajorUnitsString(usd);

    await DailyMaintenanceService(
      client: client,
      data: data,
    ).rebuildNetWorth(startDate: targetDate, yesterday: targetDate);

    final rows = client.replacedRanges[GoogleSheetsRanges.dailyNetWorth]!;
    final updated = rows.firstWhere(
      (row) => row.first == '${_dateString(targetDate)}-net',
    );
    expect(updated[2], isNot(oldNetWorth));
  });

  test(
    'partial catch-up does not count an existing tail balance twice',
    () async {
      final source = await AssetAppDataRepository().load();
      final day13 = DateTime.utc(2026, 10, 13);
      final rates = [
        ...source.exchangeRates.where((rate) => rate.date.isBefore(day13)),
        ExchangeRate(
          id: '2026-10-12-INR',
          date: DateTime.utc(2026, 10, 12),
          currencyId: 'INR',
          rateToUsd: Decimal.parse('0.01'),
          sourceRateDate: DateTime.utc(2026, 10, 12),
          retrievedAt: DateTime.utc(2026, 10, 14),
        ),
        ExchangeRate(
          id: '2026-10-13-USD',
          date: day13,
          currencyId: 'USD',
          rateToUsd: Decimal.one,
          sourceRateDate: day13,
          retrievedAt: DateTime.utc(2026, 10, 14),
        ),
        ExchangeRate(
          id: '2026-10-13-INR',
          date: day13,
          currencyId: 'INR',
          rateToUsd: Decimal.parse('0.01'),
          sourceRateDate: day13,
          retrievedAt: DateTime.utc(2026, 10, 14),
        ),
      ];
      final existingTailBalance = DailyAccountBalance(
        id: '2026-10-13-chase_checking',
        date: day13,
        accountId: 'chase_checking',
        balance: source.ledgerBalances['chase_checking']!,
        balanceUsd: source.ledgerBalances['chase_checking']!,
        retrievedAt: DateTime.utc(2026, 10, 14),
      );

      Future<String> rebuildExpectedAmount({
        required bool partialBalance,
      }) async {
        final data = _copySnapshot(
          source,
          exchangeRates: rates,
          dailyAccountBalances: [
            ...source.dailyAccountBalances,
            if (partialBalance) existingTailBalance,
          ],
        );
        final client = _FakeSheetsClient({
          'DailyExchangeRates!A:A': [
            ['rate_id'],
            for (final rate in rates) [rate.id],
          ],
          'DailyAccountBalances!A:A': [
            ['balance_id'],
            for (final balance in data.dailyAccountBalances) [balance.id],
          ],
          'DailyNetWorth!A:A': [
            ['net_worth_id'],
            for (final value in source.dailyNetWorth) [value.id],
          ],
        });
        await DailyMaintenanceService(
          client: client,
          data: data,
        ).catchUp(yesterday: day13);
        final row = client.appendedRows.singleWhere(
          (item) => item.first == '2026-10-13-net',
        );
        expect(
          client.appendedRows.any(
            (item) => item.first == existingTailBalance.id,
          ),
          !partialBalance,
        );
        return row[2];
      }

      final completeCalculation = await rebuildExpectedAmount(
        partialBalance: false,
      );
      final recoveredCalculation = await rebuildExpectedAmount(
        partialBalance: true,
      );
      expect(recoveredCalculation, completeCalculation);
    },
  );

  test(
    'reconciliation repairs historical edits and clears empty-ledger history',
    () async {
      final source = await AssetAppDataRepository().load();
      final original = source.transactions.first;
      final edited = Transaction(
        id: original.id,
        createdAt: original.createdAt,
        date: original.date,
        type: original.type,
        sourceAmount: Money(
          minorUnits: original.sourceAmount!.minorUnits + 500,
          currencyId: original.sourceAmount!.currencyId,
        ),
        sourceAccountId: original.sourceAccountId,
        destinationAmount: original.destinationAmount,
        destinationAccountId: original.destinationAccountId,
        categoryId: original.categoryId,
        tagId: original.tagId,
        description: original.description,
      );
      final changedData = _copySnapshot(
        source,
        transactions: [edited, ...source.transactions.skip(1)],
      );
      final changedClient = _FakeSheetsClient({});
      var httpRequests = 0;
      final changed = await DailyMaintenanceService(
        client: changedClient,
        data: changedData,
        httpClient: MockClient((_) async {
          httpRequests++;
          return http.Response(
            jsonEncode({
              'rates': {'INR': 96.4},
            }),
            200,
          );
        }),
      ).reconcile(yesterday: DateTime.utc(2026, 10, 12));

      expect(changed, isTrue);
      expect(httpRequests, 1, reason: 'only the missing INR rate is fetched');
      expect(
        changedClient.replacedRanges.keys,
        containsAll([
          GoogleSheetsRanges.dailyAccountBalances,
          GoogleSheetsRanges.dailyNetWorth,
        ]),
      );

      final emptyLedger = _copySnapshot(source, transactions: const []);
      final clearedClient = _FakeSheetsClient({});
      await DailyMaintenanceService(
        client: clearedClient,
        data: emptyLedger,
      ).reconcile(yesterday: DateTime.utc(2026, 10, 12));

      expect(
        clearedClient.replacedRanges[GoogleSheetsRanges.dailyExchangeRates],
        [RuntimeTableSchemas.dailyExchangeRates.headers],
      );
      expect(
        clearedClient.replacedRanges[GoogleSheetsRanges.dailyAccountBalances],
        [RuntimeTableSchemas.dailyAccountBalances.headers],
      );
      expect(clearedClient.replacedRanges[GoogleSheetsRanges.dailyNetWorth], [
        RuntimeTableSchemas.dailyNetWorth.headers,
      ]);
    },
  );

  test(
    'reconciliation skips writes when stored derived values are current',
    () async {
      final source = await AssetAppDataRepository().load();
      final rebuildClient = _FakeSheetsClient({});
      await DailyMaintenanceService(
        client: rebuildClient,
        data: source,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'rates': {'INR': 96.4},
            }),
            200,
          ),
        ),
      ).rebuild(yesterday: DateTime.utc(2026, 10, 12));

      final currencies = source.currenciesById;
      final rates = ModelParsers.parseExchangeRates(
        csv.encode(
          rebuildClient.replacedRanges[GoogleSheetsRanges.dailyExchangeRates]!,
        ),
      );
      final balances = ModelParsers.parseDailyAccountBalances(
        csv.encode(
          rebuildClient.replacedRanges[GoogleSheetsRanges
              .dailyAccountBalances]!,
        ),
        accounts: source.accountsById,
        currencies: currencies,
      );
      final netWorth = ModelParsers.parseDailyNetWorth(
        csv.encode(
          rebuildClient.replacedRanges[GoogleSheetsRanges.dailyNetWorth]!,
        ),
        currencies,
      );
      final currentData = _copySnapshot(
        source,
        exchangeRates: rates,
        dailyAccountBalances: balances,
        dailyNetWorth: netWorth,
      );
      final reconcileClient = _FakeSheetsClient({});

      final changed = await DailyMaintenanceService(
        client: reconcileClient,
        data: currentData,
      ).reconcile(yesterday: DateTime.utc(2026, 10, 12));

      expect(changed, isFalse);
      expect(reconcileClient.replacedRanges, isEmpty);
    },
  );

  test('idempotent catch-up skips rows whose IDs already exist', () async {
    final data = await AssetAppDataRepository().load();
    final client = _FakeSheetsClient({
      'DailyExchangeRates!A:A': [
        ['rate_id'],
        for (final date in [
          '2026-10-10',
          '2026-10-11',
          '2026-10-12',
          '2026-10-13',
        ]) ...[
          ['$date-USD'],
          ['$date-INR'],
        ],
      ],
      'DailyAccountBalances!A:A': [
        ['balance_id'],
        for (final date in ['2026-10-10', '2026-10-11']) ...[
          ['$date-chase_checking'],
          ['$date-sbi_nro'],
          ['$date-chase_freedom_rise'],
        ],
        for (final date in ['2026-10-12', '2026-10-13']) ...[
          ['$date-chase_checking'],
          ['$date-chase_freedom_rise'],
        ],
      ],
      'DailyNetWorth!A:A': [
        ['net_worth_id'],
        for (final date in [
          '2026-10-10',
          '2026-10-11',
          '2026-10-12',
          '2026-10-13',
        ])
          ['$date-net'],
      ],
      'DailyExchangeRates!B:B': [
        ['rate_date'],
        ['2026-10-13'],
      ],
      'DailyAccountBalances!B:B': [
        ['balance_date'],
        ['2026-10-13'],
      ],
      'DailyNetWorth!B:B': [
        ['net_worth_date'],
        ['2026-10-13'],
      ],
    });
    await DailyMaintenanceService(
      client: client,
      data: data,
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'rates': {'INR': 96.4},
          }),
          200,
        ),
      ),
    ).catchUp(yesterday: DateTime.utc(2026, 10, 13));

    expect(client.appendedRows, isEmpty);
  });

  test('rebuilds when a derived date is missing in the middle', () async {
    final data = await AssetAppDataRepository().load();
    final client = _FakeSheetsClient({
      'DailyExchangeRates!A:A': [
        ['rate_id'],
        for (final rate in data.exchangeRates) [rate.id],
        ['2026-10-12-INR'],
      ],
      'DailyAccountBalances!A:A': [
        ['balance_id'],
        for (final balance in data.dailyAccountBalances) [balance.id],
      ],
      'DailyNetWorth!A:A': [
        ['net_worth_id'],
        for (final value in data.dailyNetWorth)
          if (value.date == DateTime.utc(2026, 10, 10) ||
              value.date == DateTime.utc(2026, 10, 12))
            [value.id],
      ],
    });

    await DailyMaintenanceService(
      client: client,
      data: data,
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'rates': {'INR': 96.4},
          }),
          200,
        ),
      ),
    ).catchUp(yesterday: DateTime.utc(2026, 10, 12));

    expect(
      client.replacedRanges.keys,
      contains(GoogleSheetsRanges.dailyNetWorth),
    );
    expect(client.appendedRows, isEmpty);
  });

  test('appends only the missing tail dates', () async {
    final data = await AssetAppDataRepository().load();
    final client = _FakeSheetsClient({
      'DailyExchangeRates!A:A': [
        ['rate_id'],
        for (final rate in data.exchangeRates) [rate.id],
      ],
      'DailyAccountBalances!A:A': [
        ['balance_id'],
        for (final balance in data.dailyAccountBalances) [balance.id],
      ],
      'DailyNetWorth!A:A': [
        ['net_worth_id'],
        for (final value in data.dailyNetWorth) [value.id],
      ],
    });

    await DailyMaintenanceService(
      client: client,
      data: data,
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'rates': {'INR': 96.4},
          }),
          200,
        ),
      ),
    ).catchUp(yesterday: DateTime.utc(2026, 10, 13));

    expect(client.replacedRanges, isEmpty);
    expect(client.appendedRows, isNotEmpty);
  });

  test('rebuild replaces all three derived tables', () async {
    final data = await AssetAppDataRepository().load();
    final client = _FakeSheetsClient({});
    final httpClient = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'rates': {'INR': 96.4},
        }),
        200,
      ),
    );

    await DailyMaintenanceService(
      client: client,
      data: data,
      httpClient: httpClient,
    ).rebuild();

    expect(
      client.replacedRanges.keys,
      containsAll(<String>[
        GoogleSheetsRanges.dailyExchangeRates,
        GoogleSheetsRanges.dailyAccountBalances,
        GoogleSheetsRanges.dailyNetWorth,
      ]),
    );
  });

  test('full rebuilds when source history predates derived history', () async {
    final source = await AssetAppDataRepository().load();
    final data = AppDataSnapshot(
      accounts: source.accounts,
      categories: source.categories,
      currencies: source.currencies,
      tags: source.tags,
      transactions: source.transactions,
      exchangeRates: source.exchangeRates
          .where((rate) => rate.date.isAfter(DateTime.utc(2026, 10, 10)))
          .toList(),
      dailyAccountBalances: source.dailyAccountBalances
          .where((balance) => balance.date.isAfter(DateTime.utc(2026, 10, 10)))
          .toList(),
      dailyNetWorth: source.dailyNetWorth
          .where((value) => value.date.isAfter(DateTime.utc(2026, 10, 10)))
          .toList(),
      dailyManualValuations: source.dailyManualValuations,
    );
    final client = _FakeSheetsClient({});
    await DailyMaintenanceService(
      client: client,
      data: data,
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'rates': {'INR': 96.4},
          }),
          200,
        ),
      ),
    ).catchUp(yesterday: DateTime.utc(2026, 10, 13));

    expect(
      client.replacedRanges.keys,
      containsAll(<String>[
        GoogleSheetsRanges.dailyExchangeRates,
        GoogleSheetsRanges.dailyAccountBalances,
        GoogleSheetsRanges.dailyNetWorth,
      ]),
    );
    expect(client.appendedRows, isEmpty);
  });

  test('includes an account through its inclusive closing date', () async {
    final data = await AssetAppDataRepository().load();
    final client = _FakeSheetsClient({
      'DailyExchangeRates!B:B': [
        ['rate_date'],
        ['2026-10-10'],
      ],
      'DailyAccountBalances!B:B': [
        ['balance_date'],
        ['2026-10-10'],
      ],
      'DailyNetWorth!B:B': [
        ['net_worth_date'],
        ['2026-10-10'],
      ],
    });
    final httpClient = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'rates': {'INR': 96.4},
        }),
        200,
      ),
    );

    await DailyMaintenanceService(
      client: client,
      data: data,
      httpClient: httpClient,
    ).catchUp(yesterday: DateTime.utc(2026, 10, 11));

    expect(
      client.appendedRows.any((row) => row.first == '2026-10-11-INR'),
      isTrue,
    );
    expect(
      client.appendedRows.any((row) => row.first == '2026-10-11-sbi_nro'),
      isTrue,
    );
  });

  test(
    'catch-up resumes after a partial write without duplicate rates',
    () async {
      final data = await AssetAppDataRepository().load();
      final client = _ResumableSheetsClient();
      final httpClient = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'rates': {'INR': 96.4},
          }),
          200,
        ),
      );
      final service = DailyMaintenanceService(
        client: client,
        data: data,
        httpClient: httpClient,
      );

      await expectLater(
        service.catchUp(yesterday: DateTime.utc(2026, 10, 13)),
        throwsStateError,
      );

      client.failOnAppendNumber = null;
      final reloadedData = AppDataSnapshot(
        accounts: data.accounts,
        categories: data.categories,
        currencies: data.currencies,
        tags: data.tags,
        transactions: data.transactions,
        exchangeRates: [
          ...data.exchangeRates,
          ExchangeRate(
            id: '2026-10-13-USD',
            date: DateTime.utc(2026, 10, 13),
            currencyId: 'USD',
            rateToUsd: Decimal.one,
            sourceRateDate: DateTime.utc(2026, 10, 13),
            retrievedAt: DateTime.utc(2026, 10, 15),
          ),
          ExchangeRate(
            id: '2026-10-13-INR',
            date: DateTime.utc(2026, 10, 13),
            currencyId: 'INR',
            rateToUsd: Decimal.parse('0.01037344398'),
            sourceRateDate: DateTime.utc(2026, 10, 13),
            retrievedAt: DateTime.utc(2026, 10, 15),
          ),
        ],
        dailyAccountBalances: data.dailyAccountBalances,
        dailyNetWorth: data.dailyNetWorth,
        dailyManualValuations: data.dailyManualValuations,
      );
      await DailyMaintenanceService(
        client: client,
        data: reloadedData,
        httpClient: httpClient,
      ).catchUp(yesterday: DateTime.utc(2026, 10, 13));

      expect(
        client.appendedRows
            .where((row) => row.first == '2026-10-13-USD')
            .length,
        1,
      );
      expect(
        client.appendedRows
            .where((row) => row.first == '2026-10-13-chase_checking')
            .length,
        1,
      );
      expect(
        client.appendedRows
            .where((row) => row.first == '2026-10-13-net')
            .length,
        1,
      );
    },
  );
}

AppDataSnapshot _copySnapshot(
  AppDataSnapshot source, {
  List<Transaction>? transactions,
  List<ExchangeRate>? exchangeRates,
  List<DailyAccountBalance>? dailyAccountBalances,
  List<DailyNetWorth>? dailyNetWorth,
}) => AppDataSnapshot(
  accounts: source.accounts,
  categories: source.categories,
  currencies: source.currencies,
  tags: source.tags,
  transactions: transactions ?? source.transactions,
  transactionsToMigrate: source.transactionsToMigrate,
  exchangeRates: exchangeRates ?? source.exchangeRates,
  dailyAccountBalances: dailyAccountBalances ?? source.dailyAccountBalances,
  dailyNetWorth: dailyNetWorth ?? source.dailyNetWorth,
  dailyManualValuations: source.dailyManualValuations,
  displayPreferences: source.displayPreferences,
  transactionTemplates: source.transactionTemplates,
  incomeAllocations: source.incomeAllocations,
);

class _ResumableSheetsClient extends SheetsTableClient {
  final Map<String, List<List<String>>> tables = {
    'DailyExchangeRates!A:A': [
      ['rate_id'],
      for (final date in ['2026-10-10', '2026-10-11', '2026-10-12']) ...[
        ['$date-USD'],
        ['$date-INR'],
      ],
    ],
    'DailyExchangeRates!B:B': [
      ['rate_date'],
      ['2026-10-12'],
    ],
    'DailyAccountBalances!A:A': [
      ['balance_id'],
      for (final date in ['2026-10-10', '2026-10-11']) ...[
        ['$date-chase_checking'],
        ['$date-sbi_nro'],
        ['$date-chase_freedom_rise'],
      ],
      ['2026-10-12-chase_checking'],
      ['2026-10-12-chase_freedom_rise'],
    ],
    'DailyAccountBalances!B:B': [
      ['balance_date'],
      ['2026-10-12'],
    ],
    'DailyNetWorth!A:A': [
      ['net_worth_id'],
      ['2026-10-10-net'],
      ['2026-10-11-net'],
      ['2026-10-12-net'],
    ],
    'DailyNetWorth!B:B': [
      ['net_worth_date'],
      ['2026-10-12'],
    ],
  };

  final List<List<String>> appendedRows = [];
  final Map<String, List<List<String>>> replacedRanges = {};
  int appendCount = 0;
  int? failOnAppendNumber = 2;

  @override
  Future<void> appendRow(String range, List<String> values) async {
    appendCount++;
    if (appendCount == failOnAppendNumber) {
      throw StateError('Injected partial-write failure.');
    }
    appendedRows.add(values);
    final dateRange = switch (range) {
      'DailyExchangeRates!A:F' => 'DailyExchangeRates!B:B',
      'DailyAccountBalances!A:F' => 'DailyAccountBalances!B:B',
      'DailyNetWorth!A:D' => 'DailyNetWorth!B:B',
      _ => null,
    };
    if (dateRange != null) {
      tables[dateRange]!.add([values[1]]);
    }
    final idRange = switch (range) {
      'DailyExchangeRates!A:F' => 'DailyExchangeRates!A:A',
      'DailyAccountBalances!A:F' => 'DailyAccountBalances!A:A',
      'DailyNetWorth!A:D' => 'DailyNetWorth!A:A',
      _ => null,
    };
    if (idRange != null) tables[idRange]!.add([values.first]);
  }

  @override
  Future<Map<String, List<List<String>>>> batchReadRanges(
    List<String> ranges,
  ) async {
    return {for (final range in ranges) range: tables[range] ?? const []};
  }

  @override
  Future<List<List<String>>> readRange(String range) async =>
      tables[range] ?? [];

  @override
  Future<void> replaceRange(String range, List<List<String>> values) async {
    replacedRanges[range] = values;
  }
}

class _FakeSheetsClient extends SheetsTableClient {
  _FakeSheetsClient(this.tables);

  final Map<String, List<List<String>>> tables;
  final List<List<String>> appendedRows = [];
  final Map<String, List<List<String>>> replacedRanges = {};

  @override
  Future<void> appendRow(String range, List<String> values) async {
    appendedRows.add(values);
  }

  @override
  Future<Map<String, List<List<String>>>> batchReadRanges(
    List<String> ranges,
  ) async {
    return {for (final range in ranges) range: tables[range] ?? const []};
  }

  @override
  Future<List<List<String>>> readRange(String range) async =>
      tables[range] ?? [];

  @override
  Future<void> replaceRange(String range, List<List<String>> values) async {
    tables[range] = values;
    replacedRanges[range] = values;
  }
}

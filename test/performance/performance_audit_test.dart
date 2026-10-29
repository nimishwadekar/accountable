// Opt-in diagnostics, not an FPS benchmark or a timing gate.
// flutter test test/performance/performance_audit_test.dart --dart-define=PERFORMANCE_AUDIT=true --reporter expanded
// Add --platform chrome to compare the browser test runtime.
// Add --dart-define=PERFORMANCE_STRESS=true for 10k/50k/100k transactions.
import 'dart:async';

import 'package:accountable/app/formatters.dart';
import 'package:accountable/app/pages/transaction_list_widgets.dart';
import 'package:accountable/app/pages/transactions_page.dart';
import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';
import 'package:accountable/features/analysis/analysis_calculator.dart';
import 'package:accountable/features/analysis/category_analysis.dart';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

Object? _sink;
const _enabled = bool.fromEnvironment('PERFORMANCE_AUDIT');
const _stressEnabled = bool.fromEnvironment('PERFORMANCE_STRESS');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'synthetic data-path scaling (no network or real financial data)',
    () async {
      debugPrint('Runtime: ${kIsWeb ? 'Chrome test JS' : 'Flutter test VM'}');
      final scenarios = [
        (650, 30),
        (650, 365),
        (650, 1095),
        (6500, 365),
        if (_stressEnabled) (10000, 365),
        if (_stressEnabled) (50000, 365),
        if (_stressEnabled) (100000, 365),
      ];
      for (final scenario in scenarios) {
        final (count, days) = scenario;
        final fixture = await _fixture(count: count, days: days);
        final data = fixture.data;
        final client = fixture.client;
        final repository = GoogleSheetsAppDataRepository(client);
        final network = MockClient((_) async {
          throw StateError(
            'The synthetic fixture must never fetch exchange rates.',
          );
        });
        addTearDown(network.close);
        final maintenance = DailyMaintenanceService(
          client: client,
          data: data,
          httpClient: network,
        );
        final calculator = AnalysisCalculator(data);
        final range = DateTimeRange(
          start: data.earliestTransactionDate!,
          end: fixture.end,
        );
        final label =
            'N=$count D=$days rows=${client.tables.values.fold<int>(0, (sum, rows) => sum + rows.length)}';
        await _measure('$label snapshot construction', () {
          _sink = _copy(data);
        });
        final firstTransaction = data.transactions.first;
        await _measure('$label first running-balance index access', () {
          final snapshot = _copy(data);
          _sink = snapshot.balanceAfterTransaction(
            firstTransaction.sourceAccountId!,
            firstTransaction.id,
          );
        });
        await _measure('$label full repository reload, zero latency', () async {
          _sink = await repository.reload();
        });
        final writes = client.writes;
        await _measure(
          '$label no-op reconcile',
          () => maintenance.reconcile(yesterday: fixture.end),
        );
        expect(
          client.writes,
          writes,
          reason: 'No-op reconciliation must not write.',
        );
        await _measure('$label manual account all-history series', () {
          _sink = calculator.accountBalanceSeries(
            accountId: 'manual-0',
            range: range,
          );
        });
        await _measure('$label category spending, latest month', () {
          _sink = CategoryAnalysisCalculator(data).spending(month: fixture.end);
        });
        final source = csv.encode(
          client.tables[GoogleSheetsRanges.transactions]!,
        );
        await _measure('$label strict transaction parser', () {
          _sink = ModelParsers.parseTransactions(
            source,
            accounts: data.accountsById,
            currencies: data.currenciesById,
          );
        });
        await _measure('$label issue-collecting transaction parser', () {
          final result = ModelParsers.parseTransactionsWithIssues(
            source,
            accounts: data.accountsById,
            currencies: data.currenciesById,
          );
          expect(result.issues, isEmpty);
          _sink = result;
        });
        // Same lookup workload as daily ledger conversion, without Decimal math.
        await _measure('$label linear FX lookups only', () {
          var total = 0;
          for (var day = 0; day < days; day++) {
            final date = range.start.add(Duration(days: day));
            for (final account in data.accounts.where(
              (account) => account.isLedgerAccount,
            )) {
              total += maintenance
                  .rateFor(data.exchangeRates, account.currencyId, date)
                  .date
                  .day;
            }
          }
          _sink = total;
        });
        final indexed = {
          for (final rate in data.exchangeRates)
            (rate.currencyId, rate.date): rate,
        };
        await _measure('$label indexed FX lookups only (candidate)', () {
          var total = 0;
          for (var day = 0; day < days; day++) {
            final date = range.start.add(Duration(days: day));
            for (final account in data.accounts.where(
              (account) => account.isLedgerAccount,
            )) {
              total += indexed[(account.currencyId, date)]!.date.day;
            }
          }
          _sink = total;
        });
        await _measure('$label format every transaction amount', () {
          _sink = [
            for (final transaction in data.transactions)
              formatMoney(transaction.sourceAmount!, data.currenciesById),
          ];
        });
      }
      expect(_sink, isNotNull);
    },
    timeout: const Timeout(Duration(minutes: 5)),
    skip: !_enabled,
  );

  for (final count in [650, 6500, if (_stressEnabled) 100000]) {
    testWidgets('transaction list stays lazy at $count rows', (tester) async {
      final fixture = await _fixture(count: count, days: 365);
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final watch = Stopwatch()..start();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: TransactionsPage(
            data: fixture.data,
            onTransactionAdded: (_) async {},
            onTransactionsAdded: (_) async {},
            onTemplateAdded: (_) async {},
            onTemplateUpdated: (_) async {},
          ),
        ),
      );
      watch.stop();
      final initialRows = find.byType(TransactionListRow).evaluate().length;
      expect(initialRows, lessThan(40));
      debugPrint(
        'UI N=$count first mount+layout ${watch.elapsedMicroseconds / 1000}ms, mounted transaction rows=$initialRows (test harness, not FPS)',
      );
      await _measure('UI N=$count show/hide two taps+pumps', () async {
        await tester.tap(find.text('Show balances'));
        await tester.pump();
        await tester.tap(find.text('Hide balances'));
        await tester.pump();
      });
      final list = tester.widget<ListView>(
        find.byKey(const PageStorageKey<String>('transactions-list')),
      );
      final controller = list.controller!;
      await _measure('UI N=$count 20 scroll steps+pumps', () async {
        controller.jumpTo(0);
        await tester.pump();
        for (var step = 1; step <= 20; step++) {
          controller.jumpTo(step * 80.0);
          await tester.pump();
        }
      });
      expect(find.byType(TransactionListRow).evaluate().length, lessThan(40));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }, skip: !_enabled);
  }
}

Future<void> _measure(String label, FutureOr<void> Function() action) async {
  for (var warmup = 0; warmup < 2; warmup++) {
    final result = action();
    if (result is Future) await result;
  }
  final samples = <double>[];
  for (var sample = 0; sample < 5; sample++) {
    final watch = Stopwatch()..start();
    final result = action();
    if (result is Future) await result;
    watch.stop();
    samples.add(watch.elapsedMicroseconds / 1000);
  }
  samples.sort();
  debugPrint(
    '$label: median=${samples[2].toStringAsFixed(3)}ms range=${samples.first.toStringAsFixed(3)}..${samples.last.toStringAsFixed(3)}ms',
  );
}

AppDataSnapshot _copy(AppDataSnapshot data) => AppDataSnapshot(
  accounts: data.accounts,
  categories: data.categories,
  currencies: data.currencies,
  tags: data.tags,
  transactions: data.transactions,
  exchangeRates: data.exchangeRates,
  dailyAccountBalances: data.dailyAccountBalances,
  dailyNetWorth: data.dailyNetWorth,
  dailyManualValuations: data.dailyManualValuations,
  displayPreferences: data.displayPreferences,
  achievements: data.achievements,
  achievementStartDate: data.achievementStartDate,
);

Future<({AppDataSnapshot data, _MemorySheets client, DateTime end})> _fixture({
  required int count,
  required int days,
}) async {
  final end = DateTime.utc(2026, 10, 28);
  final start = end.subtract(Duration(days: days - 1));
  final tables = {
    for (final schema in RuntimeTableSchemas.all)
      schema.range: <List<String>>[schema.headers],
  };
  tables[GoogleSheetsRanges.currencies]!.addAll([
    ['USD', r'$', '2'],
    ['EUR', '€', '2'],
    ['INR', '₹', '2'],
  ]);
  const currencies = ['USD', 'EUR', 'INR'];
  final accounts = [
    for (var index = 0; index < 10; index++)
      (
        index < 8 ? 'ledger-$index' : 'manual-${index - 8}',
        currencies[index % 3],
      ),
  ];
  for (var index = 0; index < accounts.length; index++) {
    final (id, currency) = accounts[index];
    tables[GoogleSheetsRanges.accounts]!.add([
      id,
      'Account $index',
      index < 8 ? 'cash' : 'asset',
      currency,
      index < 8 ? '10000' : '0',
      _date(start),
      '',
      index < 8 ? 'FALSE' : 'TRUE',
    ]);
    tables[GoogleSheetsRanges.displayPreferences]!.add([
      'account',
      id,
      '${1001 + index}',
      'TRUE',
      'TRUE',
    ]);
  }
  tables[GoogleSheetsRanges.categories]!.add([
    'general',
    'General',
    'expense,income,reimbursement,transfer',
  ]);
  tables[GoogleSheetsRanges.tags]!.add(['general', 'General']);
  tables[GoogleSheetsRanges.displayPreferences]!.addAll([
    ['category', 'general', '2000', 'TRUE', 'TRUE'],
    ['tag', 'general', '3000', 'TRUE', 'TRUE'],
  ]);
  tables[GoogleSheetsRanges.achievementSettings]!.add([_date(start)]);
  for (var index = 0; index < count; index++) {
    final date = start.add(Duration(days: index * days ~/ count));
    final transfer = index % 10 == 0;
    tables[GoogleSheetsRanges.transactions]!.add([
      'synthetic-$index',
      _date(date),
      'Synthetic transaction $index',
      'general',
      transfer ? 'transfer' : 'expense',
      '10',
      'ledger-${index % 8}',
      transfer ? '10' : '',
      transfer ? 'ledger-${(index + 1) % 8}' : '',
      'general',
      date.add(Duration(seconds: index)).toIso8601String(),
    ]);
  }
  for (var day = 0; day < days; day++) {
    final date = start.add(Duration(days: day));
    for (var index = 0; index < currencies.length; index++) {
      final currency = currencies[index];
      tables[GoogleSheetsRanges.dailyExchangeRates]!.add([
        '${_date(date)}-$currency',
        _date(date),
        currency,
        ['1', '1.1', '0.01'][index],
        _date(date),
        end.toIso8601String(),
      ]);
    }
    if (day % 30 == 0) {
      for (var index = 0; index < 2; index++) {
        tables[GoogleSheetsRanges.dailyManualValuations]!.add([
          '${_date(date)}-manual-$index',
          _date(date),
          'manual-$index',
          '5000',
        ]);
      }
    }
  }
  final client = _MemorySheets(tables);
  final repository = GoogleSheetsAppDataRepository(client);
  final network = MockClient(
    (_) async => throw StateError('Unexpected HTTP request'),
  );
  try {
    await DailyMaintenanceService(
      client: client,
      data: await repository.load(),
      httpClient: network,
    ).reconcile(yesterday: end);
    return (data: await repository.reload(), client: client, end: end);
  } finally {
    network.close();
  }
}

String _date(DateTime date) => date.toIso8601String().substring(0, 10);

class _MemorySheets extends SheetsTableClient {
  _MemorySheets(this.tables);
  final Map<String, List<List<String>>> tables;
  int writes = 0;

  @override
  Future<Map<String, List<List<String>>>> batchReadRanges(
    List<String> ranges,
  ) async => {for (final range in ranges) range: tables[range] ?? []};
  @override
  Future<List<List<String>>> readRange(String range) async =>
      tables[range] ?? [];
  @override
  Future<void> appendRow(String range, List<String> values) async {
    writes++;
    tables[range]!.add(values);
  }

  @override
  Future<void> replaceRange(String range, List<List<String>> values) async {
    writes++;
    tables[range] = values;
  }
}

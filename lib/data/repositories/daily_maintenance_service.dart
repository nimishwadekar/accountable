import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;

import '../app_data_snapshot.dart';
import '../models/models.dart';
import '../sources/google_sheets_api.dart';
import '../table_schema.dart';
import 'google_sheets_repository.dart';

class TransactionSavedHistoryRepairException implements Exception {
  const TransactionSavedHistoryRepairException(this.cause);

  final Object cause;

  @override
  String toString() =>
      'Transaction saved, but daily history repair could not be confirmed: $cause';
}

class DailyMaintenanceService {
  DailyMaintenanceService({
    required this.client,
    required this.data,
    http.Client? httpClient,
    this.httpRequestTimeout = const Duration(seconds: 20),
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  final SheetsTableClient client;
  final AppDataSnapshot data;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Duration httpRequestTimeout;
  final Map<DateTime, Map<String, dynamic>> _rateResponsesByDate = {};

  void close() {
    if (_ownsHttpClient) _httpClient.close();
  }

  Future<void> catchUp({required DateTime yesterday}) async {
    _rateResponsesByDate.clear();
    final endDate = _dateOnly(yesterday);
    final fallbackStart = _earliestSourceDate ?? endDate;
    if (fallbackStart.isAfter(endDate)) return;
    if (_requiresFullRebuild) {
      return rebuild(yesterday: endDate);
    }

    final existingIds = await _readDailyIds();
    final coverage = _derivedCoverage(
      startDate: fallbackStart,
      endDate: endDate,
      existingIds: existingIds,
    );
    if (coverage.hasMiddleGap) {
      return rebuild(yesterday: endDate);
    }
    final appendStart = coverage.firstMissingDate;
    if (appendStart == null) return;

    final rates = <ExchangeRate>[...data.exchangeRates];
    final missingRates = <ExchangeRate>[];
    for (
      var date = appendStart;
      !date.isAfter(endDate);
      date = date.add(const Duration(days: 1))
    ) {
      final expectedRateIds = {
        for (final currency in _currenciesWithOpenAccounts(date))
          '${_dateString(date)}-${currency.id}',
      };
      if (expectedRateIds.every(existingIds['rates']!.contains)) continue;

      final dateRates = await _ratesForDate(date);
      rates.addAll(dateRates);
      for (final rate in dateRates) {
        if (existingIds['rates']!.add(rate.id)) {
          missingRates.add(rate);
        }
      }
    }
    if (missingRates.isNotEmpty) {
      await client.appendRows(GoogleSheetsRanges.dailyExchangeRates, [
        for (final rate in missingRates) _exchangeRateRow(rate),
      ]);
    }
    final rateIndex = _ExactExchangeRateIndex(rates);

    final balances = _balancesThrough(
      startDate: appendStart,
      endDate: endDate,
      rates: rateIndex,
    );
    final missingBalances = [
      for (final balance in balances)
        if (existingIds['balances']!.add(balance.id)) balance,
    ];
    if (missingBalances.isNotEmpty) {
      await client.appendRows(GoogleSheetsRanges.dailyAccountBalances, [
        for (final balance in missingBalances) _balanceRow(balance),
      ]);
    }

    // A tail may already contain some account-balance rows from a prior
    // partial write. Merge by deterministic row ID so those rows are not
    // counted once from the loaded snapshot and again from this calculation.
    final balancesById = <String, DailyAccountBalance>{
      for (final balance in data.dailyAccountBalances)
        if (!_dateOnly(balance.date).isBefore(appendStart) &&
            !_dateOnly(balance.date).isAfter(endDate))
          balance.id: balance,
      for (final balance in balances) balance.id: balance,
    };
    final netWorths = _netWorthThrough(
      balancesById.values,
      rates: rateIndex,
      startDate: appendStart,
      endDate: endDate,
    );
    final missingNetWorths = [
      for (final netWorth in netWorths)
        if (existingIds['netWorth']!.add(netWorth.id)) netWorth,
    ];
    if (missingNetWorths.isNotEmpty) {
      await client.appendRows(GoogleSheetsRanges.dailyNetWorth, [
        for (final netWorth in missingNetWorths) _netWorthRow(netWorth),
      ]);
    }
  }

  Future<void> rebuildNetWorth({
    required DateTime startDate,
    DateTime? yesterday,
  }) async {
    final start = _dateOnly(startDate);
    final end = _dateOnly(
      yesterday ?? DateTime.now().subtract(const Duration(days: 1)),
    );
    if (start.isAfter(end)) return;

    final rates = data.exchangeRates;
    final balances = data.dailyAccountBalances.where((balance) {
      final date = _dateOnly(balance.date);
      return !date.isBefore(start) && !date.isAfter(end);
    });
    final recalculated = _netWorthThrough(
      balances,
      rates: _ExactExchangeRateIndex(rates),
      startDate: start,
      endDate: end,
    );
    final recalculatedById = {
      for (final value in recalculated) value.id: value,
    };
    final merged = [
      for (final value in data.dailyNetWorth)
        recalculatedById.remove(value.id) ?? value,
      ...recalculatedById.values,
    ]..sort((a, b) => a.date.compareTo(b.date));

    await client.replaceRange(GoogleSheetsRanges.dailyNetWorth, [
      RuntimeTableSchemas.dailyNetWorth.headers,
      for (final value in merged) _netWorthRow(value),
    ]);
  }

  /// Reconciles materialized daily tables against the current source snapshot.
  /// Existing exchange rates are retained; only missing dates are requested
  /// from Frankfurter. This detects historical appends, edits, and deletions.
  Future<bool> reconcile({DateTime? yesterday}) async {
    _rateResponsesByDate.clear();
    final endDate = _dateOnly(
      yesterday ?? DateTime.now().subtract(const Duration(days: 1)),
    );
    final startDate = _earliestSourceDate;
    if (startDate == null || startDate.isAfter(endDate)) {
      if (data.exchangeRates.isEmpty &&
          data.dailyAccountBalances.isEmpty &&
          data.dailyNetWorth.isEmpty) {
        return false;
      }
      await _clearDerivedTables();
      return true;
    }

    final existingRates = {
      for (final rate in data.exchangeRates)
        '${_dateString(_dateOnly(rate.date))}-${rate.currencyId}': rate,
    };
    final rates = <ExchangeRate>[];
    for (
      var date = startDate;
      !date.isAfter(endDate);
      date = date.add(const Duration(days: 1))
    ) {
      final currencies = _currenciesWithOpenAccounts(date).toList();
      final missing = currencies.where(
        (currency) =>
            !existingRates.containsKey('${_dateString(date)}-${currency.id}'),
      );
      if (missing.isNotEmpty) {
        final fetched = await _ratesForDate(date);
        for (final rate in fetched) {
          existingRates.putIfAbsent(rate.id, () => rate);
        }
      }
      for (final currency in currencies) {
        final key = '${_dateString(date)}-${currency.id}';
        final rate = existingRates[key];
        if (rate == null) {
          throw StateError(
            'No exchange rate for ${currency.id} on ${_dateString(date)}.',
          );
        }
        rates.add(rate);
      }
    }

    final rateIndex = _ExactExchangeRateIndex(rates);
    final balances = _balancesThrough(
      startDate: startDate,
      endDate: endDate,
      rates: rateIndex,
    );
    final netWorths = _netWorthThrough(balances, rates: rateIndex);
    if (_sameDerivedValues(
      expectedRates: rates,
      expectedBalances: balances,
      expectedNetWorth: netWorths,
    )) {
      return false;
    }

    await client.replaceRanges({
      GoogleSheetsRanges.dailyExchangeRates: [
        RuntimeTableSchemas.dailyExchangeRates.headers,
        for (final rate in rates) _exchangeRateRow(rate),
      ],
      GoogleSheetsRanges.dailyAccountBalances: [
        RuntimeTableSchemas.dailyAccountBalances.headers,
        for (final balance in balances) _balanceRow(balance),
      ],
      GoogleSheetsRanges.dailyNetWorth: [
        RuntimeTableSchemas.dailyNetWorth.headers,
        for (final netWorth in netWorths) _netWorthRow(netWorth),
      ],
    });
    return true;
  }

  bool _sameDerivedValues({
    required List<ExchangeRate> expectedRates,
    required List<DailyAccountBalance> expectedBalances,
    required List<DailyNetWorth> expectedNetWorth,
  }) {
    bool sameRows<T>(
      List<T> expected,
      List<T> actual,
      String Function(T) idOf,
      bool Function(T, T) sameValue,
    ) {
      if (expected.length != actual.length) return false;
      final actualById = {for (final value in actual) idOf(value): value};
      if (actualById.length != actual.length) return false;
      return expected.every((value) {
        final existing = actualById[idOf(value)];
        return existing != null && sameValue(value, existing);
      });
    }

    return sameRows(
          expectedRates,
          data.exchangeRates,
          (value) => value.id,
          (a, b) =>
              _dateOnly(a.date) == _dateOnly(b.date) &&
              a.currencyId == b.currencyId &&
              a.rateToUsd == b.rateToUsd &&
              _dateOnly(a.sourceRateDate) == _dateOnly(b.sourceRateDate),
        ) &&
        sameRows(
          expectedBalances,
          data.dailyAccountBalances,
          (value) => value.id,
          (a, b) =>
              _dateOnly(a.date) == _dateOnly(b.date) &&
              a.accountId == b.accountId &&
              a.balance.minorUnits == b.balance.minorUnits &&
              a.balance.currencyId == b.balance.currencyId &&
              a.balanceUsd.minorUnits == b.balanceUsd.minorUnits,
        ) &&
        sameRows(
          expectedNetWorth,
          data.dailyNetWorth,
          (value) => value.id,
          (a, b) =>
              _dateOnly(a.date) == _dateOnly(b.date) &&
              a.amount.minorUnits == b.amount.minorUnits &&
              a.amount.currencyId == b.amount.currencyId,
        );
  }

  Future<void> rebuild({DateTime? yesterday}) async {
    _rateResponsesByDate.clear();
    final endDate = _dateOnly(
      yesterday ?? DateTime.now().subtract(const Duration(days: 1)),
    );
    final startDate = _earliestSourceDate;
    if (startDate == null || startDate.isAfter(endDate)) {
      await _clearDerivedTables();
      return;
    }

    final rates = <ExchangeRate>[];
    for (
      var date = startDate;
      !date.isAfter(endDate);
      date = date.add(const Duration(days: 1))
    ) {
      rates.addAll(await _ratesForDate(date));
    }

    final rateIndex = _ExactExchangeRateIndex(rates);
    final balances = _balancesThrough(
      startDate: startDate,
      endDate: endDate,
      rates: rateIndex,
    );
    final netWorths = _netWorthThrough(balances, rates: rateIndex);

    await client.replaceRanges({
      GoogleSheetsRanges.dailyExchangeRates: [
        RuntimeTableSchemas.dailyExchangeRates.headers,
        for (final rate in rates)
          [
            rate.id,
            _dateString(rate.date),
            rate.currencyId,
            rate.rateToUsd.toString(),
            _dateString(rate.sourceRateDate),
            rate.retrievedAt.toUtc().toIso8601String(),
          ],
      ],
      GoogleSheetsRanges.dailyAccountBalances: [
        RuntimeTableSchemas.dailyAccountBalances.headers,
        for (final balance in balances)
          [
            balance.id,
            _dateString(balance.date),
            balance.accountId,
            balance.balance.toMajorUnitsString(
              data.currenciesById[balance.balance.currencyId]!,
            ),
            balance.balanceUsd.toMajorUnitsString(data.currenciesById['USD']!),
            balance.retrievedAt.toUtc().toIso8601String(),
          ],
      ],
      GoogleSheetsRanges.dailyNetWorth: [
        RuntimeTableSchemas.dailyNetWorth.headers,
        for (final netWorth in netWorths)
          [
            netWorth.id,
            _dateString(netWorth.date),
            netWorth.amount.toMajorUnitsString(data.currenciesById['USD']!),
            netWorth.retrievedAt.toUtc().toIso8601String(),
          ],
      ],
    });
  }

  Future<void> _clearDerivedTables() => client.replaceRanges({
    GoogleSheetsRanges.dailyExchangeRates: [
      RuntimeTableSchemas.dailyExchangeRates.headers,
    ],
    GoogleSheetsRanges.dailyAccountBalances: [
      RuntimeTableSchemas.dailyAccountBalances.headers,
    ],
    GoogleSheetsRanges.dailyNetWorth: [
      RuntimeTableSchemas.dailyNetWorth.headers,
    ],
  });

  _DerivedCoverage _derivedCoverage({
    required DateTime startDate,
    required DateTime endDate,
    required Map<String, Set<String>> existingIds,
  }) {
    DateTime? firstMissingDate;
    for (
      var date = startDate;
      !date.isAfter(endDate);
      date = date.add(const Duration(days: 1))
    ) {
      final complete = _hasDerivedDataForDate(date, existingIds);
      if (!complete) {
        firstMissingDate ??= date;
      } else if (firstMissingDate != null) {
        return const _DerivedCoverage.middleGap();
      }
    }
    return _DerivedCoverage.tail(firstMissingDate);
  }

  bool _hasDerivedDataForDate(
    DateTime date,
    Map<String, Set<String>> existingIds,
  ) {
    final normalized = _dateOnly(date);
    if (!existingIds['netWorth']!.contains('${_dateString(normalized)}-net')) {
      return false;
    }
    for (final currency in _currenciesWithOpenAccounts(normalized)) {
      if (!existingIds['rates']!.contains(
        '${_dateString(normalized)}-${currency.id}',
      )) {
        return false;
      }
    }
    for (final account in _openLedgerAccountsOn(normalized)) {
      if (!existingIds['balances']!.contains(
        '${_dateString(normalized)}-${account.id}',
      )) {
        return false;
      }
    }
    return true;
  }

  Future<Map<String, Set<String>>> _readDailyIds() async {
    final ranges = await client.batchReadRanges(const [
      'DailyExchangeRates!A:A',
      'DailyAccountBalances!A:A',
      'DailyNetWorth!A:A',
    ]);
    return {
      'rates': _ids(ranges['DailyExchangeRates!A:A']),
      'balances': _ids(ranges['DailyAccountBalances!A:A']),
      'netWorth': _ids(ranges['DailyNetWorth!A:A']),
    };
  }

  Future<List<ExchangeRate>> _ratesForDate(DateTime date) async {
    for (var offset = 0; offset <= 30; offset++) {
      final queryDate = date.subtract(Duration(days: offset));
      final normalizedQueryDate = _dateOnly(queryDate);
      var rates = _rateResponsesByDate[normalizedQueryDate];
      if (rates == null) {
        final uri = Uri.parse(
          'https://api.frankfurter.dev/v1/${_dateString(queryDate)}?base=USD',
        );
        final response = await _httpClient.get(uri).timeout(httpRequestTimeout);
        if (response.statusCode != 200) continue;
        final body = jsonDecode(response.body);
        if (body is! Map<String, dynamic>) continue;
        final rawRates = body['rates'];
        if (rawRates is! Map<String, dynamic>) continue;
        rates = rawRates;
        _rateResponsesByDate[normalizedQueryDate] = rates;
      }
      final retrievedAt = DateTime.now().toUtc();
      return [
        for (final currency in _currenciesWithOpenAccounts(date))
          ExchangeRate(
            id: '${_dateString(date)}-${currency.id}',
            date: date,
            currencyId: currency.id,
            rateToUsd: currency.id == 'USD'
                ? Decimal.one
                : _rateToUsd(rates, currency.id),
            sourceRateDate: queryDate,
            retrievedAt: retrievedAt,
          ),
      ];
    }
    throw StateError('No Frankfurter rate available for ${_dateString(date)}.');
  }

  Decimal _rateToUsd(Map<String, dynamic> rates, String currencyId) {
    final unitsPerUsd = Decimal.parse(rates[currencyId].toString());
    if (unitsPerUsd == Decimal.zero) {
      throw StateError('Frankfurter returned a zero rate for $currencyId.');
    }
    return (Decimal.one / unitsPerUsd).toDecimal(
      scaleOnInfinitePrecision: 18,
      toBigInt: (value) => value.round(),
    );
  }

  List<String> _exchangeRateRow(ExchangeRate rate) => [
    rate.id,
    _dateString(rate.date),
    rate.currencyId,
    rate.rateToUsd.toString(),
    _dateString(rate.sourceRateDate),
    rate.retrievedAt.toUtc().toIso8601String(),
  ];

  List<DailyAccountBalance> _balancesThrough({
    required DateTime startDate,
    required DateTime endDate,
    required _ExactExchangeRateIndex rates,
  }) {
    final result = <DailyAccountBalance>[];
    final balances = <String, Money>{
      for (final account in data.accounts) account.id: account.openingBalance,
    };
    for (
      var date = _earliestSourceDate ?? startDate;
      !date.isAfter(endDate);
      date = date.add(const Duration(days: 1))
    ) {
      for (final transaction
          in data.transactionsByDate[date] ?? const <Transaction>[]) {
        _applyTransaction(balances, transaction);
      }
      if (date.isBefore(startDate)) continue;
      final retrievedAt = DateTime.now().toUtc();
      for (final account in _openLedgerAccountsOn(date)) {
        final balance = balances[account.id]!;
        final usd = _toUsd(balance, rates.rateFor(account.currencyId, date));
        result.add(
          DailyAccountBalance(
            id: '${_dateString(date)}-${account.id}',
            date: date,
            accountId: account.id,
            balance: balance,
            balanceUsd: usd,
            retrievedAt: retrievedAt,
          ),
        );
      }
    }
    return result;
  }

  List<DailyNetWorth> _netWorthThrough(
    Iterable<DailyAccountBalance> balances, {
    required _ExactExchangeRateIndex rates,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final byDate = <DateTime, int>{};
    for (final balance in balances) {
      final amount = balance.balanceUsd.minorUnits;
      byDate[balance.date] = (byDate[balance.date] ?? 0) + amount;
    }
    for (final rate in rates.values) {
      final date = _dateOnly(rate.date);
      if ((startDate != null && date.isBefore(_dateOnly(startDate))) ||
          (endDate != null && date.isAfter(_dateOnly(endDate)))) {
        continue;
      }
      byDate.putIfAbsent(date, () => 0);
    }
    final dates = byDate.keys.toList()..sort();
    final valuationAccounts = data.accounts
        .where((account) => account.isValuationAccount)
        .toList(growable: false);
    final valuationIndexes = <String, int>{};
    final latestValuations = <String, DailyManualValuation>{};
    for (final date in dates) {
      for (final account in valuationAccounts) {
        final valuations =
            data.manualValuationsByAccountId[account.id] ??
            const <DailyManualValuation>[];
        var index = valuationIndexes[account.id] ?? 0;
        while (index < valuations.length &&
            !_dateOnly(valuations[index].date).isAfter(date)) {
          final valuation = valuations[index++];
          if (!_dateOnly(valuation.date)
              .isBefore(_dateOnly(account.openingDate))) {
            latestValuations[account.id] = valuation;
          }
        }
        valuationIndexes[account.id] = index;
      }
      for (final account in valuationAccounts) {
        final opened = !_dateOnly(account.openingDate).isAfter(date);
        final closed =
            account.closingDate != null &&
            _dateOnly(account.closingDate!).isBefore(date);
        if (!opened || closed) continue;
        final valuation = latestValuations[account.id];
        if (valuation == null) continue;
        final usd = _toUsd(
          valuation.value,
          rates.rateFor(account.currencyId, date),
        );
        byDate[date] = (byDate[date] ?? 0) + usd.minorUnits;
      }
    }
    return [
      for (final date in dates)
        DailyNetWorth(
          id: '${_dateString(date)}-net',
          date: date,
          amount: Money(minorUnits: byDate[date]!, currencyId: 'USD'),
          retrievedAt: DateTime.now().toUtc(),
        ),
    ];
  }

  List<String> _balanceRow(DailyAccountBalance balance) => [
    balance.id,
    _dateString(balance.date),
    balance.accountId,
    balance.balance.toMajorUnitsString(
      data.currenciesById[balance.balance.currencyId]!,
    ),
    balance.balanceUsd.toMajorUnitsString(data.currenciesById['USD']!),
    balance.retrievedAt.toUtc().toIso8601String(),
  ];

  List<String> _netWorthRow(DailyNetWorth netWorth) => [
    netWorth.id,
    _dateString(netWorth.date),
    netWorth.amount.toMajorUnitsString(data.currenciesById['USD']!),
    netWorth.retrievedAt.toUtc().toIso8601String(),
  ];

  void _applyTransaction(Map<String, Money> balances, Transaction transaction) {
    if (transaction.sourceAccountId != null &&
        transaction.sourceAmount != null) {
      final accountId = transaction.sourceAccountId!;
      balances[accountId] = balances[accountId]! - transaction.sourceAmount!;
    }
    if (transaction.destinationAccountId != null &&
        transaction.destinationAmount != null) {
      final accountId = transaction.destinationAccountId!;
      balances[accountId] =
          balances[accountId]! + transaction.destinationAmount!;
    }
  }

  Money _toUsd(Money balance, ExchangeRate rate) {
    final amount = balance.toMajorUnits(
      data.currenciesById[balance.currencyId]!,
    );
    final usd = data.currenciesById['USD']!;
    final minorUnits =
        (amount *
                rate.rateToUsd *
                Decimal.fromInt(_powerOfTen(usd.decimalPlaces)))
            .round()
            .toBigInt()
            .toInt();
    return Money(minorUnits: minorUnits, currencyId: usd.id);
  }

  static int _powerOfTen(int exponent) {
    var result = 1;
    for (var index = 0; index < exponent; index++) {
      result *= 10;
    }
    return result;
  }

  ExchangeRate rateFor(
    List<ExchangeRate> rates,
    String currencyId,
    DateTime date,
  ) {
    // Retained as a list-based utility for callers that have only one lookup.
    // Historical calculations construct one index and reuse it instead.
    return rates.lastWhere(
      (rate) => rate.currencyId == currencyId && _dateOnly(rate.date) == date,
      orElse: () => throw StateError(
        'No exchange rate for $currencyId on ${_dateString(date)}.',
      ),
    );
  }

  Iterable<Account> _openLedgerAccountsOn(DateTime date) {
    return _openAccountsOn(date).where((account) => account.isLedgerAccount);
  }

  Iterable<Account> _openAccountsOn(DateTime date) {
    return data.accounts.where((account) {
      final opened = !_dateOnly(account.openingDate).isAfter(date);
      final closed =
          account.closingDate != null &&
          _dateOnly(account.closingDate!).isBefore(date);
      return opened && !closed;
    });
  }

  Iterable<CurrencyDefinition> _currenciesWithOpenAccounts(DateTime date) {
    final openCurrencyIds = {
      for (final account in _openAccountsOn(date)) account.currencyId,
    };
    return data.currencies.where(
      (currency) => openCurrencyIds.contains(currency.id),
    );
  }

  bool get _requiresFullRebuild {
    final earliestSource = _earliestSourceDate;
    if (earliestSource == null) return false;
    if (data.exchangeRates.isEmpty ||
        data.dailyAccountBalances.isEmpty ||
        data.dailyNetWorth.isEmpty) {
      return true;
    }
    final earliestDerived = [
      ...data.exchangeRates.map((value) => _dateOnly(value.date)),
      ...data.dailyAccountBalances.map((value) => _dateOnly(value.date)),
      ...data.dailyNetWorth.map((value) => _dateOnly(value.date)),
    ].reduce((a, b) => a.isBefore(b) ? a : b);
    return earliestSource.isBefore(earliestDerived);
  }

  DateTime? get _earliestSourceDate => data.earliestTransactionDate;

  static Set<String> _ids(List<List<String>>? rows) {
    return {
      for (final row in rows ?? const <List<String>>[])
        if (row.isNotEmpty && !row.first.endsWith('_id')) row.first.trim(),
    };
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  static String _dateString(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

class _DerivedCoverage {
  const _DerivedCoverage.tail(this.firstMissingDate) : hasMiddleGap = false;

  const _DerivedCoverage.middleGap()
    : firstMissingDate = null,
      hasMiddleGap = true;

  final DateTime? firstMissingDate;
  final bool hasMiddleGap;
}

/// Exact-date lookup used by daily maintenance. The analysis feature intentionally
/// uses a different latest-on-or-before lookup for transaction-date conversion.
class _ExactExchangeRateIndex {
  _ExactExchangeRateIndex(Iterable<ExchangeRate> values)
    : values = List.unmodifiable(values),
      byDateAndCurrency = {
        for (final rate in values)
          (_dateOnly(rate.date), rate.currencyId): rate,
      };

  final List<ExchangeRate> values;
  final Map<(DateTime, String), ExchangeRate> byDateAndCurrency;

  ExchangeRate rateFor(String currencyId, DateTime date) {
    final normalized = DateTime.utc(date.year, date.month, date.day);
    return byDateAndCurrency[(normalized, currencyId)] ??
        (throw StateError(
          'No exchange rate for $currencyId on ${_formatDate(normalized)}.',
        ));
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  static String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

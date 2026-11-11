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

/// Daily history is missing a baseline required to append or reconcile rows.
/// The caller should offer the explicit daily-tables rebuild action.
class DailyHistoryRebuildRequiredException implements Exception {
  const DailyHistoryRebuildRequiredException(this.reason);

  final String reason;

  @override
  String toString() =>
      'Daily history does not cover the current source data. $reason '
      'Use “Rebuild daily tables” to repair it.';
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
  DateTime? _processedThroughOverride;

  DateTime? get _processedThrough =>
      _processedThroughOverride ?? data.dailyProcessedThrough;

  DateTime _requireProcessedThrough() {
    final value = _processedThrough;
    if (value == null) {
      throw StateError(
        'Metadata is missing $dailyProcessedThroughMetadataKey. '
        'Add the last fully processed date before running daily maintenance.',
      );
    }
    return _dateOnly(value);
  }

  Future<void> _writeProcessedThrough(DateTime date) async {
    final normalized = _dateOnly(date);
    final updatedMetadata = Map<String, String>.of(data.metadata)
      ..[dailyProcessedThroughMetadataKey] = _dateString(normalized);
    await client.replaceRange(GoogleSheetsRanges.metadata, [
      RuntimeTableSchemas.metadata.headers,
      for (final key in updatedMetadata.keys.toList()..sort())
        [key, updatedMetadata[key]!],
    ]);
    _processedThroughOverride = normalized;
  }

  void close() {
    if (_ownsHttpClient) _httpClient.close();
  }

  Future<void> catchUp({required DateTime yesterday}) async {
    _rateResponsesByDate.clear();
    final endDate = _dateOnly(yesterday);
    final processedThrough = _requireProcessedThrough();
    if (!endDate.isAfter(processedThrough)) return;
    final rebuildReason = _rebuildRequiredReason;
    if (rebuildReason != null) {
      throw DailyHistoryRebuildRequiredException(rebuildReason);
    }

    final nextDate = processedThrough.add(const Duration(days: 1));
    final sourceStart = _earliestSourceDate;
    if (sourceStart == null) {
      await _writeProcessedThrough(endDate);
      return;
    }
    final appendStart = nextDate.isBefore(sourceStart) ? sourceStart : nextDate;
    if (appendStart.isAfter(endDate)) {
      await _writeProcessedThrough(endDate);
      return;
    }

    final existingIds = await _readDailyIds();
    final rates = <ExchangeRate>[...data.exchangeRates];
    final rateCandidates = <ExchangeRate>[];
    for (
      var date = appendStart;
      !date.isAfter(endDate);
      date = date.add(const Duration(days: 1))
    ) {
      final dateRates = await _ratesForDate(date);
      rates.addAll(dateRates);
      rateCandidates.addAll(dateRates);
    }
    final changedRates = _changedExchangeRates(
      rateCandidates,
      previous: data.exchangeRates.where(
        (rate) => _dateOnly(rate.date).isBefore(appendStart),
      ),
    );
    final missingRates = _notAlreadyStored(changedRates, existingIds['rates']!);
    if (missingRates.isNotEmpty) {
      await client.appendRows(GoogleSheetsRanges.dailyExchangeRates, [
        for (final rate in missingRates) _exchangeRateRow(rate),
      ]);
    }
    final rateIndex = _LatestExchangeRateIndex(rates);

    final balances = _balancesThrough(
      startDate: appendStart,
      endDate: endDate,
      rates: rateIndex,
    );
    final changedBalances = _changedBalances(
      balances,
      previous: data.dailyAccountBalances.where(
        (balance) => _dateOnly(balance.date).isBefore(appendStart),
      ),
    );
    final missingBalances = _notAlreadyStored(
      changedBalances,
      existingIds['balances']!,
    );
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
    final changedNetWorths = _changedNetWorth(
      netWorths,
      previous: data.dailyNetWorth.where(
        (netWorth) => _dateOnly(netWorth.date).isBefore(appendStart),
      ),
    );
    final missingNetWorths = _notAlreadyStored(
      changedNetWorths,
      existingIds['netWorth']!,
    );
    if (missingNetWorths.isNotEmpty) {
      await client.appendRows(GoogleSheetsRanges.dailyNetWorth, [
        for (final netWorth in missingNetWorths) _netWorthRow(netWorth),
      ]);
    }
    await _writeProcessedThrough(endDate);
  }

  Future<void> rebuildNetWorth({
    required DateTime startDate,
    DateTime? yesterday,
  }) async {
    _requireProcessedThrough();
    final start = _dateOnly(startDate);
    final end = _dateOnly(
      yesterday ?? DateTime.now().subtract(const Duration(days: 1)),
    );
    if (start.isAfter(end)) return;

    final rates = _LatestExchangeRateIndex(data.exchangeRates);
    final balances = _balancesThrough(
      startDate: start,
      endDate: end,
      rates: rates,
    );
    final recalculated = _netWorthThrough(
      balances,
      rates: rates,
      startDate: start,
      endDate: end,
    );
    final recalculatedById = {
      for (final value in recalculated) value.id: value,
    };
    final merged = _changedNetWorth([
      for (final value in data.dailyNetWorth)
        recalculatedById.remove(value.id) ?? value,
      ...recalculatedById.values,
    ]);

    await client.replaceRange(GoogleSheetsRanges.dailyNetWorth, [
      RuntimeTableSchemas.dailyNetWorth.headers,
      for (final value in merged) _netWorthRow(value),
    ]);
  }

  /// Reconciles daily change-point rows against the current source snapshot.
  /// Missing rows within the processed range are interpreted as unchanged.
  Future<bool> reconcile({DateTime? yesterday}) async {
    _rateResponsesByDate.clear();
    final processedThrough = _requireProcessedThrough();
    final endDate = _dateOnly(
      yesterday ?? DateTime.now().subtract(const Duration(days: 1)),
    );
    final startDate = _earliestSourceDate;
    if (startDate == null || startDate.isAfter(endDate)) {
      return false;
    }
    final rebuildReason = _rebuildRequiredReason;
    if (rebuildReason != null) {
      throw DailyHistoryRebuildRequiredException(rebuildReason);
    }

    final rates = await _ratesForReconciliation(
      startDate: startDate,
      endDate: endDate,
      processedThrough: processedThrough,
    );
    final rateIndex = _LatestExchangeRateIndex(rates);
    final balances = _balancesThrough(
      startDate: startDate,
      endDate: endDate,
      rates: rateIndex,
    );
    final netWorths = _netWorthThrough(
      balances,
      rates: rateIndex,
      startDate: startDate,
      endDate: endDate,
    );
    final mergedRates = _mergeDailyRows(
      existing: data.exchangeRates,
      expected: rates,
      changePoints: _changedExchangeRates(rates),
      idOf: (value) => value.id,
      sameValue: (a, b) => a.rateToUsd == b.rateToUsd,
      compare: (a, b) {
        final byDate = _dateOnly(a.date).compareTo(_dateOnly(b.date));
        return byDate == 0 ? a.currencyId.compareTo(b.currencyId) : byDate;
      },
    );
    final mergedBalances = _mergeDailyRows(
      existing: data.dailyAccountBalances,
      expected: balances,
      changePoints: _changedBalances(balances),
      idOf: (value) => value.id,
      sameValue: (a, b) =>
          a.balance.currencyId == b.balance.currencyId &&
          a.balance.minorUnits == b.balance.minorUnits,
      compare: (a, b) {
        final byDate = _dateOnly(a.date).compareTo(_dateOnly(b.date));
        return byDate == 0 ? a.accountId.compareTo(b.accountId) : byDate;
      },
    );
    final mergedNetWorth = _mergeDailyRows(
      existing: data.dailyNetWorth,
      expected: netWorths,
      changePoints: _changedNetWorth(netWorths),
      idOf: (value) => value.id,
      sameValue: (a, b) =>
          a.amount.currencyId == b.amount.currencyId &&
          a.amount.minorUnits == b.amount.minorUnits,
      compare: (a, b) => _dateOnly(a.date).compareTo(_dateOnly(b.date)),
    );
    final ranges = <String, List<List<String>>>{};
    if (mergedRates.changed) {
      ranges[GoogleSheetsRanges.dailyExchangeRates] = [
        RuntimeTableSchemas.dailyExchangeRates.headers,
        for (final rate in mergedRates.rows) _exchangeRateRow(rate),
      ];
    }
    if (mergedBalances.changed) {
      ranges[GoogleSheetsRanges.dailyAccountBalances] = [
        RuntimeTableSchemas.dailyAccountBalances.headers,
        for (final balance in mergedBalances.rows) _balanceRow(balance),
      ];
    }
    if (mergedNetWorth.changed) {
      ranges[GoogleSheetsRanges.dailyNetWorth] = [
        RuntimeTableSchemas.dailyNetWorth.headers,
        for (final value in mergedNetWorth.rows) _netWorthRow(value),
      ];
    }
    if (ranges.isNotEmpty) await client.replaceRanges(ranges);
    final checkpointChanged = endDate.isAfter(processedThrough);
    if (checkpointChanged) await _writeProcessedThrough(endDate);
    return ranges.isNotEmpty || checkpointChanged;
  }

  ({List<T> rows, bool changed}) _mergeDailyRows<T extends Object>({
    required Iterable<T> existing,
    required Iterable<T> expected,
    required Iterable<T> changePoints,
    required String Function(T) idOf,
    required bool Function(T, T) sameValue,
    required int Function(T, T) compare,
  }) {
    final expectedById = {for (final value in expected) idOf(value): value};
    final existingById = {for (final value in existing) idOf(value): value};
    final rows = <T>[];
    var changed = false;
    for (final value in existingById.values) {
      final replacement = expectedById.remove(idOf(value));
      if (replacement == null) {
        changed = true;
        continue;
      }
      if (sameValue(value, replacement)) {
        rows.add(value);
      } else {
        rows.add(replacement);
        changed = true;
      }
    }
    for (final value in changePoints) {
      if (expectedById.remove(idOf(value)) != null) {
        rows.add(value);
        changed = true;
      }
    }
    rows.sort(compare);
    return (rows: List.unmodifiable(rows), changed: changed);
  }

  Future<List<ExchangeRate>> _ratesForReconciliation({
    required DateTime startDate,
    required DateTime endDate,
    required DateTime processedThrough,
  }) async {
    final existingByDateAndCurrency = {
      for (final rate in data.exchangeRates)
        (_dateOnly(rate.date), rate.currencyId): rate,
    };
    final latestByCurrency = <String, ExchangeRate>{};
    final denseRates = <ExchangeRate>[];
    for (
      var date = _dateOnly(startDate);
      !date.isAfter(endDate);
      date = date.add(const Duration(days: 1))
    ) {
      final currencies = _currenciesWithOpenAccounts(date).toList();
      for (final currency in currencies) {
        final existing = existingByDateAndCurrency[(date, currency.id)];
        if (existing != null && !date.isAfter(processedThrough)) {
          latestByCurrency[currency.id] = existing;
        }
      }

      final needsFreshRates =
          date.isAfter(processedThrough) ||
          currencies.any(
            (currency) => !latestByCurrency.containsKey(currency.id),
          );
      final fetched = needsFreshRates ? await _ratesForDate(date) : const [];
      final fetchedByCurrency = {
        for (final rate in fetched) rate.currencyId: rate,
      };
      for (final currency in currencies) {
        final rate =
            fetchedByCurrency[currency.id] ??
            latestByCurrency[currency.id] ??
            existingByDateAndCurrency[(date, currency.id)];
        if (rate == null) {
          throw StateError(
            'No exchange rate for ${currency.id} on ${_dateString(date)}.',
          );
        }
        final dailyRate = ExchangeRate(
          id: '${_dateString(date)}-${currency.id}',
          date: date,
          currencyId: currency.id,
          rateToUsd: rate.rateToUsd,
          sourceRateDate: rate.sourceRateDate,
          retrievedAt: rate.retrievedAt,
        );
        latestByCurrency[currency.id] = dailyRate;
        denseRates.add(dailyRate);
      }
    }
    return denseRates;
  }

  List<ExchangeRate> _changedExchangeRates(
    Iterable<ExchangeRate> values, {
    Iterable<ExchangeRate> previous = const [],
  }) {
    final orderedPrevious = [...previous]
      ..sort((a, b) => a.date.compareTo(b.date));
    final latest = <String, ExchangeRate>{};
    for (final rate in orderedPrevious) {
      latest[rate.currencyId] = rate;
    }
    final ordered = [...values]
      ..sort((a, b) {
        final byDate = _dateOnly(a.date).compareTo(_dateOnly(b.date));
        return byDate == 0 ? a.currencyId.compareTo(b.currencyId) : byDate;
      });
    final changed = <ExchangeRate>[];
    for (final rate in ordered) {
      final previousRate = latest[rate.currencyId];
      if (previousRate == null || previousRate.rateToUsd != rate.rateToUsd) {
        changed.add(rate);
      }
      latest[rate.currencyId] = rate;
    }
    return changed;
  }

  List<DailyAccountBalance> _changedBalances(
    Iterable<DailyAccountBalance> values, {
    Iterable<DailyAccountBalance> previous = const [],
  }) {
    final orderedPrevious = [...previous]
      ..sort((a, b) => a.date.compareTo(b.date));
    final latest = <String, DailyAccountBalance>{};
    for (final balance in orderedPrevious) {
      latest[balance.accountId] = balance;
    }
    final ordered = [...values]
      ..sort((a, b) {
        final byDate = _dateOnly(a.date).compareTo(_dateOnly(b.date));
        return byDate == 0 ? a.accountId.compareTo(b.accountId) : byDate;
      });
    final changed = <DailyAccountBalance>[];
    for (final balance in ordered) {
      final previousBalance = latest[balance.accountId];
      if (previousBalance == null ||
          previousBalance.balance.currencyId != balance.balance.currencyId ||
          previousBalance.balance.minorUnits != balance.balance.minorUnits) {
        changed.add(balance);
      }
      latest[balance.accountId] = balance;
    }
    return changed;
  }

  List<DailyNetWorth> _changedNetWorth(
    Iterable<DailyNetWorth> values, {
    Iterable<DailyNetWorth> previous = const [],
  }) {
    final orderedPrevious = [...previous]
      ..sort((a, b) => a.date.compareTo(b.date));
    var latest = orderedPrevious.isEmpty ? null : orderedPrevious.last;
    final ordered = [...values]
      ..sort((a, b) => _dateOnly(a.date).compareTo(_dateOnly(b.date)));
    final changed = <DailyNetWorth>[];
    for (final netWorth in ordered) {
      if (latest == null ||
          latest.amount.currencyId != netWorth.amount.currencyId ||
          latest.amount.minorUnits != netWorth.amount.minorUnits) {
        changed.add(netWorth);
      }
      latest = netWorth;
    }
    return changed;
  }

  List<T> _notAlreadyStored<T extends Object>(
    List<T> values,
    Set<String> existingIds,
  ) => [
    for (final value in values)
      if (existingIds.add(_idOf(value))) value,
  ];

  String _idOf(Object value) => switch (value) {
    ExchangeRate() => value.id,
    DailyAccountBalance() => value.id,
    DailyNetWorth() => value.id,
    _ => throw ArgumentError.value(value, 'value', 'Unsupported daily row.'),
  };

  Future<void> _replaceDerivedTables({
    required List<ExchangeRate> rates,
    required List<DailyAccountBalance> balances,
    required List<DailyNetWorth> netWorth,
  }) => client.replaceRanges({
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
      for (final netWorthRow in netWorth) _netWorthRow(netWorthRow),
    ],
  });

  Future<void> rebuild({DateTime? yesterday}) async {
    _rateResponsesByDate.clear();
    _requireProcessedThrough();
    final endDate = _dateOnly(
      yesterday ?? DateTime.now().subtract(const Duration(days: 1)),
    );
    final startDate = _earliestSourceDate;
    if (startDate == null || startDate.isAfter(endDate)) {
      await _clearDerivedTables();
      await _writeProcessedThrough(endDate);
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

    final rateIndex = _LatestExchangeRateIndex(rates);
    final balances = _balancesThrough(
      startDate: startDate,
      endDate: endDate,
      rates: rateIndex,
    );
    final netWorths = _netWorthThrough(
      balances,
      rates: rateIndex,
      startDate: startDate,
      endDate: endDate,
    );

    await _replaceDerivedTables(
      rates: _changedExchangeRates(rates),
      balances: _changedBalances(balances),
      netWorth: _changedNetWorth(netWorths),
    );
    await _writeProcessedThrough(endDate);
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
    required _LatestExchangeRateIndex rates,
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
        result.add(
          DailyAccountBalance(
            id: '${_dateString(date)}-${account.id}',
            date: date,
            accountId: account.id,
            balance: balance,
            retrievedAt: retrievedAt,
          ),
        );
      }
    }
    return result;
  }

  List<DailyNetWorth> _netWorthThrough(
    Iterable<DailyAccountBalance> balances, {
    required _LatestExchangeRateIndex rates,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final byDate = <DateTime, int>{};
    for (final balance in balances) {
      final amount = _toUsd(
        balance.balance,
        rates.rateFor(balance.balance.currencyId, balance.date),
      ).minorUnits;
      byDate[balance.date] = (byDate[balance.date] ?? 0) + amount;
    }
    for (
      var date = _dateOnly(startDate);
      !date.isAfter(_dateOnly(endDate));
      date = date.add(const Duration(days: 1))
    ) {
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
    return _LatestExchangeRateIndex(rates).rateFor(currencyId, date);
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

  String? get _rebuildRequiredReason {
    final earliestSource = _earliestSourceDate;
    if (earliestSource == null) return null;
    final through = _processedThrough;
    if (through == null) {
      return 'Metadata is missing $dailyProcessedThroughMetadataKey.';
    }
    if (data.dailyNetWorth.isEmpty) {
      return 'DailyNetWorth has no rows.';
    }
    final firstNetWorth = data.dailyNetWorth
        .map((value) => _dateOnly(value.date))
        .reduce((a, b) => a.isBefore(b) ? a : b);
    if (firstNetWorth.isAfter(earliestSource)) {
      return 'DailyNetWorth starts on ${_dateString(firstNetWorth)}, after '
          'the earliest transaction on ${_dateString(earliestSource)}.';
    }

    final latestRates = _LatestExchangeRateIndex(data.exchangeRates);
    final throughDate = _dateOnly(through);
    for (final currency in data.currencies) {
      final currencyAccounts = data.accounts.where(
        (account) => account.currencyId == currency.id,
      );
      DateTime? firstUse;
      for (final account in currencyAccounts) {
        final opening = _dateOnly(account.openingDate);
        final firstActive = opening.isBefore(earliestSource)
            ? earliestSource
            : opening;
        if (account.closingDate != null &&
            _dateOnly(account.closingDate!).isBefore(firstActive)) {
          continue;
        }
        if (firstActive.isAfter(throughDate)) continue;
        if (firstUse == null || firstActive.isBefore(firstUse)) {
          firstUse = firstActive;
        }
      }
      if (firstUse != null) {
        try {
          latestRates.rateFor(currency.id, firstUse);
        } on StateError {
          return 'No ${currency.id} exchange rate exists on or before '
              '${_dateString(firstUse)}.';
        }
      }
    }
    for (final account in data.accounts.where((item) => item.isLedgerAccount)) {
      final opening = _dateOnly(account.openingDate);
      final firstActive = opening.isBefore(earliestSource)
          ? earliestSource
          : opening;
      if (account.closingDate != null &&
          _dateOnly(account.closingDate!).isBefore(firstActive)) {
        continue;
      }
      if (firstActive.isAfter(throughDate)) continue;
      final hasBaseline = data.dailyAccountBalances.any(
        (balance) =>
            balance.accountId == account.id &&
            !_dateOnly(balance.date).isAfter(throughDate),
      );
      if (!hasBaseline) {
        return 'No daily balance exists for ${account.id} on or before '
            '${_dateString(throughDate)}.';
      }
    }
    return null;
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

/// Rates are stored as change points; reads use the latest rate on or before a
/// requested day.
class _LatestExchangeRateIndex {
  _LatestExchangeRateIndex(Iterable<ExchangeRate> source) {
    final byKey = <(DateTime, String), ExchangeRate>{};
    for (final rate in source) {
      byKey[(_dateOnly(rate.date), rate.currencyId)] = rate;
    }
    final ordered = byKey.values.toList()
      ..sort((a, b) {
        final byDate = _dateOnly(a.date).compareTo(_dateOnly(b.date));
        return byDate == 0 ? a.currencyId.compareTo(b.currencyId) : byDate;
      });
    byCurrency = {
      for (final currencyId in ordered.map((rate) => rate.currencyId).toSet())
        currencyId: List.unmodifiable(
          ordered.where((rate) => rate.currencyId == currencyId).toList(),
        ),
    };
  }

  late final Map<String, List<ExchangeRate>> byCurrency;

  ExchangeRate rateFor(String currencyId, DateTime date) {
    final normalized = _dateOnly(date);
    final rates = byCurrency[currencyId] ?? const <ExchangeRate>[];
    var low = 0;
    var high = rates.length;
    while (low < high) {
      final middle = low + (high - low) ~/ 2;
      if (!_dateOnly(rates[middle].date).isAfter(normalized)) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    if (low == 0) {
      throw StateError(
        'No exchange rate for $currencyId on ${_formatDate(normalized)}.',
      );
    }
    return rates[low - 1];
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  static String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;

import '../app_data_snapshot.dart';
import '../csv/parse_helpers.dart';
import '../models/models.dart';
import '../sources/google_sheets_api.dart';
import 'google_sheets_repository.dart';

class DailyMaintenanceService {
  DailyMaintenanceService({
    required this.client,
    required this.data,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final SheetsTableClient client;
  final AppDataSnapshot data;
  final http.Client _httpClient;

  Future<void> catchUp({required DateTime yesterday}) async {
    final endDate = _dateOnly(yesterday);
    final existingDates = await _readDailyDates();
    final existingIds = await _readDailyIds();
    final fallbackStart = _earliestSourceDate ?? endDate;
    final rates = <ExchangeRate>[...data.exchangeRates];

    final rateStart = _nextDate(
      existingDates['rates']!,
      fallbackStart,
      endDate,
    );
    for (
      var date = rateStart;
      date != null && !date.isAfter(endDate);
      date = date.add(const Duration(days: 1))
    ) {
      final dateRates = await _ratesForDate(date);
      rates.addAll(dateRates);
      for (final rate in dateRates) {
        if (existingIds['rates']!.add(rate.id)) {
          await _appendExchangeRates([rate]);
        }
      }
    }

    final balanceStart = _nextDate(
      existingDates['balances']!,
      fallbackStart,
      endDate,
    );
    final newBalances = balanceStart == null
        ? <DailyAccountBalance>[]
        : _balancesThrough(
            startDate: balanceStart,
            endDate: endDate,
            rates: rates,
          );
    for (final balance in newBalances) {
      if (existingIds['balances']!.add(balance.id)) {
        await _appendBalance(balance);
      }
    }

    final netWorthStart = _nextDate(
      existingDates['netWorth']!,
      fallbackStart,
      endDate,
    );
    if (netWorthStart != null) {
      final allBalances = [...data.dailyAccountBalances, ...newBalances];
      final netWorths = _netWorthThrough(
        allBalances.where(
          (balance) => !_dateOnly(balance.date).isBefore(netWorthStart),
        ),
        rates: rates,
      );
      for (final netWorth in netWorths) {
        if (existingIds['netWorth']!.add(netWorth.id)) {
          await _appendNetWorth(netWorth);
        }
      }
    }
  }

  Future<void> rebuild() async {
    final today = DateTime.now();
    final endDate = _dateOnly(today.subtract(const Duration(days: 1)));
    final startDate = _earliestSourceDate;
    if (startDate == null || startDate.isAfter(endDate)) return;

    final rates = <ExchangeRate>[];
    for (
      var date = startDate;
      !date.isAfter(endDate);
      date = date.add(const Duration(days: 1))
    ) {
      rates.addAll(await _ratesForDate(date));
    }

    final balances = _balancesThrough(
      startDate: startDate,
      endDate: endDate,
      rates: rates,
    );
    final netWorths = _netWorthThrough(balances, rates: rates);

    await client.replaceRange(GoogleSheetsRanges.dailyExchangeRates, [
      ['rate_id', 'rate_date', 'currency', 'rate_to_usd', 'source_rate_date', 'retrieved_at'],
      for (final rate in rates)
        [
          rate.id,
          _dateString(rate.date),
          rate.currencyId,
          rate.rateToUsd.toString(),
          _dateString(rate.sourceRateDate),
          rate.retrievedAt.toUtc().toIso8601String(),
        ],
    ]);
    await client.replaceRange(GoogleSheetsRanges.dailyAccountBalances, [
      [
        'balance_id',
        'balance_date',
        'account_id',
        'balance',
        'balance_usd',
        'retrieved_at',
      ],
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
    ]);
    await client.replaceRange(GoogleSheetsRanges.dailyNetWorth, [
      ['net_worth_id', 'net_worth_date', 'amount', 'retrieved_at'],
      for (final netWorth in netWorths)
        [
          netWorth.id,
          _dateString(netWorth.date),
          netWorth.amount.toMajorUnitsString(data.currenciesById['USD']!),
          netWorth.retrievedAt.toUtc().toIso8601String(),
        ],
    ]);
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

  Future<Map<String, Set<DateTime>>> _readDailyDates() async {
    final ranges = await client.batchReadRanges(const [
      'DailyExchangeRates!B:B',
      'DailyAccountBalances!B:B',
      'DailyNetWorth!B:B',
    ]);
    return {
      'rates': _dates(ranges['DailyExchangeRates!B:B']),
      'balances': _dates(ranges['DailyAccountBalances!B:B']),
      'netWorth': _dates(ranges['DailyNetWorth!B:B']),
    };
  }

  Future<List<ExchangeRate>> _ratesForDate(DateTime date) async {
    for (var offset = 0; offset <= 30; offset++) {
      final queryDate = date.subtract(Duration(days: offset));
      final uri = Uri.parse(
        'https://api.frankfurter.dev/v1/${_dateString(queryDate)}?base=USD',
      );
      final response = await _httpClient.get(uri);
      if (response.statusCode != 200) continue;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final rawRates = body['rates'];
      if (rawRates is! Map<String, dynamic>) continue;
      final retrievedAt = DateTime.now().toUtc();
      return [
        for (final currency in _currenciesWithOpenAccounts(date))
          ExchangeRate(
            id: '${_dateString(date)}-${currency.id}',
            date: date,
            currencyId: currency.id,
            rateToUsd: currency.id == 'USD'
                ? Decimal.one
                : _rateToUsd(rawRates, currency.id),
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

  Future<void> _appendExchangeRates(List<ExchangeRate> rates) async {
    for (final rate in rates) {
      await client.appendRow(GoogleSheetsRanges.dailyExchangeRates, [
        rate.id,
        _dateString(rate.date),
        rate.currencyId,
        rate.rateToUsd.toString(),
        _dateString(rate.sourceRateDate),
        rate.retrievedAt.toUtc().toIso8601String(),
      ]);
    }
  }

  List<DailyAccountBalance> _balancesThrough({
    required DateTime startDate,
    required DateTime endDate,
    required List<ExchangeRate> rates,
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
      for (final transaction in data.transactions.where(
        (value) => _dateOnly(value.date) == date,
      )) {
        _applyTransaction(balances, transaction);
      }
      if (date.isBefore(startDate)) continue;
      final retrievedAt = DateTime.now().toUtc();
      for (final account in _openLedgerAccountsOn(date)) {
        final balance = balances[account.id]!;
        final usd = _toUsd(balance, rateFor(rates, account.currencyId, date));
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
    required List<ExchangeRate> rates,
  }) {
    final byDate = <DateTime, int>{};
    for (final balance in balances) {
      final amount = balance.balanceUsd.minorUnits;
      byDate[balance.date] = (byDate[balance.date] ?? 0) + amount;
    }
    for (final rate in rates) {
      byDate.putIfAbsent(_dateOnly(rate.date), () => 0);
    }
    final dates = byDate.keys.toList()..sort();
    for (final date in dates) {
      for (final account in _openAccountsOn(date).where(
        (account) => account.isValuationAccount,
      )) {
        final valuation = _latestValuation(account.id, date);
        if (valuation == null) continue;
        final usd = _toUsd(
          valuation.value,
          rateFor(rates, account.currencyId, date),
        );
        byDate[date] = (byDate[date] ?? 0) + usd.minorUnits;
      }
    }
    return [
      for (final entry
          in byDate.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
        DailyNetWorth(
          id: '${_dateString(entry.key)}-net',
          date: entry.key,
          amount: Money(minorUnits: entry.value, currencyId: 'USD'),
          retrievedAt: DateTime.now().toUtc(),
        ),
    ];
  }

  Future<void> _appendBalance(DailyAccountBalance balance) {
    return client.appendRow(GoogleSheetsRanges.dailyAccountBalances, [
      balance.id,
      _dateString(balance.date),
      balance.accountId,
      balance.balance.toMajorUnitsString(
        data.currenciesById[balance.balance.currencyId]!,
      ),
      balance.balanceUsd.toMajorUnitsString(data.currenciesById['USD']!),
      balance.retrievedAt.toUtc().toIso8601String(),
    ]);
  }

  Future<void> _appendNetWorth(DailyNetWorth netWorth) {
    return client.appendRow(GoogleSheetsRanges.dailyNetWorth, [
      netWorth.id,
      _dateString(netWorth.date),
      netWorth.amount.toMajorUnitsString(data.currenciesById['USD']!),
      netWorth.retrievedAt.toUtc().toIso8601String(),
    ]);
  }

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
        (amount * rate.rateToUsd * Decimal.fromInt(_powerOfTen(usd.decimalPlaces)))
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

  DailyManualValuation? _latestValuation(String accountId, DateTime date) {
    final historyStart = _earliestSourceDate;
    DailyManualValuation? latest;
    for (final valuation in data.dailyManualValuationsById.values) {
      final valuationDate = _dateOnly(valuation.date);
      if (valuation.accountId != accountId ||
          valuationDate.isAfter(date) ||
          (historyStart != null && valuationDate.isBefore(historyStart))) {
        continue;
      }
      if (latest == null || valuation.date.isAfter(latest.date)) {
        latest = valuation;
      }
    }
    return latest;
  }

  Iterable<Account> _openAccountsOn(DateTime date) {
    return data.accounts.where((account) {
      final opened = !_dateOnly(account.openingDate).isAfter(date);
      final closed = account.closingDate != null &&
          _dateOnly(account.closingDate!).isBefore(date);
      return opened && !closed;
    });
  }

  Iterable<CurrencyDefinition> _currenciesWithOpenAccounts(DateTime date) {
    final openCurrencyIds = {
      for (final account in _openAccountsOn(date)) account.currencyId,
    };
    return data.currencies.where((currency) => openCurrencyIds.contains(currency.id));
  }

  DateTime? get _earliestSourceDate {
    final dates =
        data.transactions
            .map((transaction) => _dateOnly(transaction.date))
            .toList()
          ..sort();
    return dates.isEmpty ? null : dates.first;
  }

  static DateTime? _nextDate(
    Set<DateTime> existing,
    DateTime fallback,
    DateTime end,
  ) {
    if (existing.isEmpty) return fallback.isAfter(end) ? null : fallback;
    final latest = existing.reduce((a, b) => a.isAfter(b) ? a : b);
    final next = latest.add(const Duration(days: 1));
    return next.isAfter(end) ? null : next;
  }

  static Set<String> _ids(List<List<String>>? rows) {
    return {
      for (final row in rows ?? const <List<String>>[])
        if (row.isNotEmpty && !row.first.endsWith('_id')) row.first.trim(),
    };
  }

  static Set<DateTime> _dates(List<List<String>>? rows) {
    final dates = <DateTime>{};
    for (final row in rows ?? const <List<String>>[]) {
      if (row.isEmpty) continue;
      final value = row.first.trim();
      if (value.endsWith('_date')) continue;
      dates.add(_dateOnly(parseDateOnly(value, fieldName: 'daily date')));
    }
    return dates;
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  static String _dateString(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

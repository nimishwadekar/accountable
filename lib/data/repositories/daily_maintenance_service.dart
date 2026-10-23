import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;

import '../app_data_snapshot.dart';
import '../models/models.dart';
import '../sources/google_sheets_api.dart';
import '../table_schema.dart';
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
    final fallbackStart = _earliestSourceDate ?? endDate;
    if (fallbackStart.isAfter(endDate)) return;
    if (_requiresFullRebuild) {
      return rebuild(yesterday: endDate);
    }

    final existingIds = await _readDailyIds();
    final rates = <ExchangeRate>[...data.exchangeRates];
    final missingRates = <ExchangeRate>[];
    for (
      var date = fallbackStart;
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

    final balances = _balancesThrough(
      startDate: fallbackStart,
      endDate: endDate,
      rates: rates,
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

    final allBalances = [...data.dailyAccountBalances, ...balances].where((
      balance,
    ) {
      final date = _dateOnly(balance.date);
      return !date.isBefore(fallbackStart) && !date.isAfter(endDate);
    });
    final netWorths = _netWorthThrough(
      allBalances,
      rates: rates,
      startDate: fallbackStart,
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
      rates: rates,
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

  Future<void> rebuild({DateTime? yesterday}) async {
    final endDate = _dateOnly(
      yesterday ?? DateTime.now().subtract(const Duration(days: 1)),
    );
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
      for (final transaction
          in data.transactionsByDate[date] ?? const <Transaction>[]) {
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
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final byDate = <DateTime, int>{};
    for (final balance in balances) {
      final amount = balance.balanceUsd.minorUnits;
      byDate[balance.date] = (byDate[balance.date] ?? 0) + amount;
    }
    for (final rate in rates) {
      final date = _dateOnly(rate.date);
      if ((startDate != null && date.isBefore(_dateOnly(startDate))) ||
          (endDate != null && date.isAfter(_dateOnly(endDate)))) {
        continue;
      }
      byDate.putIfAbsent(date, () => 0);
    }
    final dates = byDate.keys.toList()..sort();
    for (final date in dates) {
      for (final account in _openAccountsOn(
        date,
      ).where((account) => account.isValuationAccount)) {
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
    final account = data.accountsById[accountId];
    if (account == null) return null;
    final openingDate = _dateOnly(account.openingDate);
    DailyManualValuation? latest;
    for (final valuation
        in data.manualValuationsByAccountId[accountId] ??
            const <DailyManualValuation>[]) {
      final valuationDate = _dateOnly(valuation.date);
      if (valuationDate.isBefore(openingDate)) continue;
      if (valuationDate.isAfter(date)) break;
      latest = valuation;
    }
    return latest;
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

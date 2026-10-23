import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../data/app_data_snapshot.dart';
import '../../data/models/models.dart';

class DailyNetWorthPoint {
  const DailyNetWorthPoint({required this.date, required this.amount});

  final DateTime date;
  final Money amount;
}

class AccountBalancePoint {
  const AccountBalancePoint({
    required this.date,
    required this.nativeAmount,
    required this.usdAmount,
  });

  final DateTime date;
  final Money nativeAmount;
  final Money? usdAmount;
}

class DailySeries<T> {
  const DailySeries({
    required this.points,
    required this.missingDates,
    this.unavailableDates = const [],
  });

  final List<T> points;
  final List<DateTime> missingDates;
  final List<DateTime> unavailableDates;
}

class AnalysisCalculator {
  const AnalysisCalculator(this.data);

  final AppDataSnapshot data;

  DateTimeRange? get allHistoryRange {
    final firstTransactionDate = data.earliestTransactionDate;
    if (firstTransactionDate == null) return null;
    final today = DateTime.now();
    final yesterday = DateTime.utc(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 1));
    return DateTimeRange(start: firstTransactionDate, end: yesterday);
  }

  DailySeries<DailyNetWorthPoint> netWorthSeries(DateTimeRange range) {
    final values =
        data.dailyNetWorthByDate.entries
            .where((entry) => _inRange(entry.key, range))
            .map(
              (entry) => DailyNetWorthPoint(
                date: entry.key,
                amount: entry.value.amount,
              ),
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));

    return DailySeries(
      points: List.unmodifiable(values),
      missingDates: List.unmodifiable(
        _missingDates(range, values.map((v) => v.date)),
      ),
    );
  }

  DateTimeRange? accountRange({
    required String accountId,
    required DateTimeRange requestedRange,
  }) {
    final account = data.accountsById[accountId];
    if (account == null) return null;

    final start = _dateOnly(requestedRange.start);
    final requestedEnd = _dateOnly(requestedRange.end);
    final closingDate = account.closingDate == null
        ? null
        : _dateOnly(account.closingDate!);
    final end = closingDate == null || !closingDate.isBefore(requestedEnd)
        ? requestedEnd
        : closingDate;
    if (end.isBefore(start)) return null;
    return DateTimeRange(start: start, end: end);
  }

  DailySeries<AccountBalancePoint> accountBalanceSeries({
    required String accountId,
    required DateTimeRange range,
  }) {
    final account = data.accountsById[accountId];
    if (account?.usesManualValuations == true) {
      return _manualAccountBalanceSeries(account!, range);
    }

    final values =
        (data.dailyBalancesByAccountId[accountId] ?? const <DailyAccountBalance>[])
            .where((value) => _inRange(value.date, range))
            .map(
              (value) => AccountBalancePoint(
                date: _dateOnly(value.date),
                nativeAmount: value.balance,
                usdAmount: value.balanceUsd,
              ),
            )
            .toList();

    return DailySeries(
      points: List.unmodifiable(values),
      missingDates: List.unmodifiable(
        _missingDates(range, values.map((v) => v.date)),
      ),
    );
  }

  DailySeries<AccountBalancePoint> _manualAccountBalanceSeries(
    Account account,
    DateTimeRange range,
  ) {
    final dates = <DateTime>[];
    var date = _dateOnly(range.start);
    final end = _dateOnly(range.end);
    while (!date.isAfter(end)) {
      dates.add(date);
      date = date.add(const Duration(days: 1));
    }
    final openingDate = _dateOnly(account.openingDate);
    final valuations = (data.manualValuationsByAccountId[account.id] ??
            const <DailyManualValuation>[])
        .where(
          (valuation) =>
              !_dateOnly(valuation.date).isBefore(openingDate),
        )
        .toList();
    final currency = data.currenciesById[account.currencyId]!;
    final usd = data.currenciesById['USD']!;
    final points = <AccountBalancePoint>[];
    final unavailableDates = <DateTime>[];
    for (final date in dates) {
      DailyManualValuation? latest;
      for (final valuation in valuations) {
        if (!_dateOnly(valuation.date).isAfter(date)) latest = valuation;
      }
      final value = latest?.value ?? Money.zero(currency);
      final rate = _latestRate(account.currencyId, date);
      final usdValue = rate == null
          ? null
          : _convertToUsd(value, currency, rate, usd);
      if (usdValue == null) unavailableDates.add(date);
      points.add(
        AccountBalancePoint(
          date: date,
          nativeAmount: value,
          usdAmount: usdValue,
        ),
      );
    }
    return DailySeries(
      points: List.unmodifiable(points),
      missingDates: const [],
      unavailableDates: List.unmodifiable(unavailableDates),
    );
  }

  ExchangeRate? _latestRate(String currencyId, DateTime date) {
    ExchangeRate? latest;
    for (final rate in data.exchangeRatesByCurrencyId[currencyId] ??
        const <ExchangeRate>[]) {
      if (_dateOnly(rate.date).isAfter(date)) break;
      latest = rate;
    }
    return latest;
  }

  Money _convertToUsd(
    Money value,
    CurrencyDefinition currency,
    ExchangeRate rate,
    CurrencyDefinition usd,
  ) {
    final minorUnits =
        (value.toMajorUnits(currency) *
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

  static bool _inRange(DateTime value, DateTimeRange range) {
    final date = _dateOnly(value);
    final start = _dateOnly(range.start);
    final end = _dateOnly(range.end);
    return !date.isBefore(start) && !date.isAfter(end);
  }

  static List<DateTime> _missingDates(
    DateTimeRange range,
    Iterable<DateTime> availableDates,
  ) {
    final available = availableDates.map(_dateOnly).toSet();
    final missing = <DateTime>[];
    var date = _dateOnly(range.start);
    final end = _dateOnly(range.end);
    while (!date.isAfter(end)) {
      if (!available.contains(date)) missing.add(date);
      date = date.add(const Duration(days: 1));
    }
    return missing;
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime.utc(value.year, value.month, value.day);
  }
}

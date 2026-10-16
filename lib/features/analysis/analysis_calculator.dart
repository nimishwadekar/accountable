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
  final Money usdAmount;
}

class DailySeries<T> {
  const DailySeries({required this.points, required this.missingDates});

  final List<T> points;
  final List<DateTime> missingDates;
}

class AnalysisCalculator {
  const AnalysisCalculator(this.data);

  final AppDataSnapshot data;

  DateTimeRange? get allHistoryRange {
    final transactionDates =
        data.transactions
            .map((transaction) => _dateOnly(transaction.date))
            .toList()
          ..sort();
    if (transactionDates.isEmpty) return null;
    final today = DateTime.now();
    final yesterday = DateTime.utc(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 1));
    return DateTimeRange(start: transactionDates.first, end: yesterday);
  }

  DailySeries<DailyNetWorthPoint> netWorthSeries(DateTimeRange range) {
    final values =
        data.dailyNetWorth
            .where((value) => _inRange(value.date, range))
            .map(
              (value) => DailyNetWorthPoint(
                date: _dateOnly(value.date),
                amount: value.amount,
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
        data.dailyAccountBalances
            .where(
              (value) =>
                  value.accountId == accountId && _inRange(value.date, range),
            )
            .map(
              (value) => AccountBalancePoint(
                date: _dateOnly(value.date),
                nativeAmount: value.balance,
                usdAmount: value.balanceUsd,
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
    final valuations =
        data.dailyManualValuations
            .where((valuation) => valuation.accountId == account.id)
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    final currency = data.currenciesById[account.currencyId]!;
    final usd = data.currenciesById['USD']!;
    final points = <AccountBalancePoint>[];
    for (final date in dates) {
      DailyManualValuation? latest;
      for (final valuation in valuations) {
        if (!_dateOnly(valuation.date).isAfter(date)) latest = valuation;
      }
      final value = latest?.value ?? Money.zero(currency);
      final rate = _latestRate(account.currencyId, date);
      final usdValue = rate == null
          ? Money.zero(usd)
          : _convertToUsd(value, currency, rate, usd);
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
    );
  }

  ExchangeRate? _latestRate(String currencyId, DateTime date) {
    ExchangeRate? latest;
    for (final rate in data.exchangeRates) {
      if (rate.currencyId != currencyId || _dateOnly(rate.date).isAfter(date)) {
        continue;
      }
      if (latest == null || rate.date.isAfter(latest.date)) latest = rate;
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

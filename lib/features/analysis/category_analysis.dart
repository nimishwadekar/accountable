import 'package:decimal/decimal.dart';

import '../../data/data.dart';

class MissingExchangeRate {
  const MissingExchangeRate({required this.currencyId, required this.date});

  final String currencyId;
  final DateTime date;
}

class MissingExchangeRateException implements Exception {
  const MissingExchangeRateException(this.missingRates);

  final List<MissingExchangeRate> missingRates;

  MissingExchangeRateException merge(MissingExchangeRateException other) {
    final byKey = <String, MissingExchangeRate>{
      for (final item in [...missingRates, ...other.missingRates])
        '${item.currencyId}:${_missingRateDateKey(item.date)}': item,
    };
    return MissingExchangeRateException(List.unmodifiable(byKey.values));
  }

  @override
  String toString() => 'Missing historical exchange rates.';
}

String _missingRateDateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

class CategoryAnalysisValue {
  const CategoryAnalysisValue({
    required this.categoryId,
    required this.amountUsdMinorUnits,
  });

  final String? categoryId;
  final int amountUsdMinorUnits;
}

class CategoryAnalysisResult {
  const CategoryAnalysisResult({required this.values});

  final List<CategoryAnalysisValue> values;

  List<CategoryAnalysisValue> get positiveValues => values
      .where((value) => value.amountUsdMinorUnits > 0)
      .toList(growable: false);

  int get negativeAdjustment => values
      .where((value) => value.amountUsdMinorUnits < 0)
      .fold(0, (sum, value) => sum + value.amountUsdMinorUnits);

  int get totalPositive =>
      positiveValues.fold(0, (sum, value) => sum + value.amountUsdMinorUnits);
}

class CategoryAnalysisCalculator {
  const CategoryAnalysisCalculator(this.data);

  final AppDataSnapshot data;

  CategoryAnalysisResult spending({required DateTime month, String? tagId}) {
    final totals = <String?, int>{};
    final missingRates = <String, MissingExchangeRate>{};
    for (final transaction in _transactionsInMonth(month)) {
      if (!_inMonth(transaction.date, month)) continue;
      if (transaction.type != TransactionType.expense &&
          transaction.type != TransactionType.reimbursement) {
        continue;
      }
      final usesSource = transaction.type == TransactionType.expense;
      final selectedAccount = usesSource
          ? transaction.sourceAccountId
          : transaction.destinationAccountId;
      if (tagId != null && transaction.tagId != tagId) continue;
      final amount = usesSource
          ? transaction.sourceAmount
          : transaction.destinationAmount;
      final account = selectedAccount == null
          ? null
          : data.accountsById[selectedAccount];
      if (amount == null || account == null) continue;
      final usdMinor = _toUsd(
        amount,
        account.currencyId,
        transaction.date,
        missingRates,
      );
      final signed = usesSource ? usdMinor : -usdMinor;
      totals[transaction.categoryId] =
          (totals[transaction.categoryId] ?? 0) + signed;
    }
    if (missingRates.isNotEmpty) {
      throw MissingExchangeRateException(
        List.unmodifiable(missingRates.values),
      );
    }
    return CategoryAnalysisResult(values: _values(totals));
  }

  CategoryAnalysisResult income({required DateTime month, String? tagId}) {
    final totals = <String?, int>{};
    final missingRates = <String, MissingExchangeRate>{};
    for (final transaction in _transactionsInMonth(month)) {
      if (transaction.type != TransactionType.income ||
          !_inMonth(transaction.date, month)) {
        continue;
      }
      final selectedAccount = transaction.destinationAccountId;
      if (tagId != null && transaction.tagId != tagId) continue;
      final amount = transaction.destinationAmount;
      final account = selectedAccount == null
          ? null
          : data.accountsById[selectedAccount];
      if (amount == null || account == null) continue;
      final usdMinor = _toUsd(
        amount,
        account.currencyId,
        transaction.date,
        missingRates,
      );
      totals[transaction.categoryId] =
          (totals[transaction.categoryId] ?? 0) + usdMinor;
    }
    if (missingRates.isNotEmpty) {
      throw MissingExchangeRateException(
        List.unmodifiable(missingRates.values),
      );
    }
    return CategoryAnalysisResult(values: _values(totals));
  }

  Iterable<Transaction> _transactionsInMonth(DateTime month) {
    return data.transactionsByMonth[DateTime.utc(month.year, month.month)] ??
        const <Transaction>[];
  }

  int _toUsd(
    Money amount,
    String currencyId,
    DateTime date,
    Map<String, MissingExchangeRate> missingRates,
  ) {
    final usd = data.currenciesById['USD'];
    if (usd == null || currencyId == usd.id) return amount.minorUnits;
    final rates =
        data.exchangeRatesByCurrencyId[currencyId] ?? const <ExchangeRate>[];
    final targetDate = _dateOnly(date);
    var low = 0;
    var high = rates.length;
    while (low < high) {
      final middle = low + (high - low) ~/ 2;
      if (!_dateOnly(rates[middle].date).isAfter(targetDate)) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final latest = low == 0 ? null : rates[low - 1];
    if (latest == null) {
      final missing = MissingExchangeRate(
        currencyId: currencyId,
        date: _dateOnly(date),
      );
      missingRates['$currencyId:${_dateKey(date)}'] = missing;
      return 0;
    }
    return (amount.toMajorUnits(data.currenciesById[currencyId]!) *
            latest.rateToUsd *
            Decimal.fromInt(_powerOfTen(usd.decimalPlaces)))
        .round()
        .toBigInt()
        .toInt();
  }

  List<CategoryAnalysisValue> _values(Map<String?, int> totals) {
    return [
      for (final entry in totals.entries)
        if (entry.value != 0)
          CategoryAnalysisValue(
            categoryId: entry.key,
            amountUsdMinorUnits: entry.value,
          ),
    ]..sort((a, b) => b.amountUsdMinorUnits.compareTo(a.amountUsdMinorUnits));
  }

  static bool _inMonth(DateTime date, DateTime month) =>
      date.year == month.year && date.month == month.month;

  static DateTime _dateOnly(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static int _powerOfTen(int exponent) {
    var result = 1;
    for (var index = 0; index < exponent; index++) {
      result *= 10;
    }
    return result;
  }
}

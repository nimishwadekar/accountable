import 'package:decimal/decimal.dart';

import '../../data/data.dart';

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
      final usdMinor = _toUsd(amount, account.currencyId, transaction.date);
      final signed = usesSource ? usdMinor : -usdMinor;
      totals[transaction.categoryId] =
          (totals[transaction.categoryId] ?? 0) + signed;
    }
    return CategoryAnalysisResult(values: _values(totals));
  }

  CategoryAnalysisResult income({required DateTime month, String? tagId}) {
    final totals = <String?, int>{};
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
      final usdMinor = _toUsd(amount, account.currencyId, transaction.date);
      totals[transaction.categoryId] =
          (totals[transaction.categoryId] ?? 0) + usdMinor;
    }
    return CategoryAnalysisResult(values: _values(totals));
  }

  Iterable<Transaction> _transactionsInMonth(DateTime month) {
    return data.transactionsByMonth[DateTime.utc(month.year, month.month)] ??
        const <Transaction>[];
  }

  int _toUsd(Money amount, String currencyId, DateTime date) {
    final usd = data.currenciesById['USD'];
    if (usd == null || currencyId == usd.id) return amount.minorUnits;
    ExchangeRate? latest;
    for (final rate in data.exchangeRatesByCurrencyId[currencyId] ??
        const <ExchangeRate>[]) {
      if (_dateOnly(rate.date).isAfter(_dateOnly(date))) break;
      latest = rate;
    }
    if (latest == null) return 0;
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

  static int _powerOfTen(int exponent) {
    var result = 1;
    for (var index = 0; index < exponent; index++) {
      result *= 10;
    }
    return result;
  }
}

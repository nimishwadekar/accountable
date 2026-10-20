import 'package:decimal/decimal.dart';

import '../../data/data.dart';

class IncomeAllocationProgress {
  const IncomeAllocationProgress({
    required this.allocation,
    required this.expectedUsdMinorUnits,
    required this.actualUsdMinorUnits,
    required this.missingRateDates,
  });

  final IncomeAllocation allocation;
  final int expectedUsdMinorUnits;
  final int actualUsdMinorUnits;
  final List<DateTime> missingRateDates;

  double? get percentage => expectedUsdMinorUnits == 0
      ? null
      : actualUsdMinorUnits / expectedUsdMinorUnits * 100;
}

class IncomeAllocationAnalyzer {
  const IncomeAllocationAnalyzer(this.data);

  final AppDataSnapshot data;

  List<IncomeAllocationProgress> analyze({
    required DateTime month,
    required String incomeCategoryId,
  }) {
    return [
      for (final allocation in data.incomeAllocations.where(
        (allocation) => allocation.incomeCategoryId == incomeCategoryId,
      ))
        _progress(
          allocation,
          month,
          data.transactions.where((transaction) {
            return transaction.type == TransactionType.income &&
                transaction.categoryId == incomeCategoryId &&
                transaction.destinationAccountId == allocation.incomeAccountId &&
                transaction.date.year == month.year &&
                transaction.date.month == month.month;
          }).length,
        ),
    ];
  }

  IncomeAllocationProgress _progress(
    IncomeAllocation allocation,
    DateTime month,
    int incomeCount,
  ) {
    final expected = allocation.expectedAmountPerIncome.minorUnits * incomeCount;
    final missingDates = <DateTime>[];
    var actual = 0;
    for (final transaction in data.transactions) {
      if (transaction.type != TransactionType.transfer ||
          transaction.sourceAccountId != allocation.sourceAccountId ||
          transaction.destinationAccountId != allocation.destinationAccountId ||
          transaction.date.year != month.year ||
          transaction.date.month != month.month ||
          transaction.date.isBefore(allocation.startDate) ||
          (allocation.endDate != null && transaction.date.isAfter(allocation.endDate!))) {
        continue;
      }
      if (allocation.descriptionKeyword != null &&
          transaction.description != allocation.descriptionKeyword) {
        continue;
      }
      final amount = transaction.sourceAmount;
      if (amount == null) continue;
      if (amount.currencyId == 'USD') {
        actual += amount.minorUnits;
      } else {
        final rate = data.exchangeRates.where((rate) {
          return rate.currencyId == amount.currencyId &&
              rate.date.year == transaction.date.year &&
              rate.date.month == transaction.date.month &&
              rate.date.day == transaction.date.day;
        }).firstOrNull;
        if (rate == null) {
          missingDates.add(DateTime.utc(
            transaction.date.year,
            transaction.date.month,
            transaction.date.day,
          ));
          continue;
        }
        final currency = data.currenciesById[amount.currencyId]!;
        actual += (amount.toMajorUnits(currency) *
                rate.rateToUsd *
                Decimal.fromInt(100))
            .round()
            .toBigInt()
            .toInt();
      }
    }
    return IncomeAllocationProgress(
      allocation: allocation,
      expectedUsdMinorUnits: expected,
      actualUsdMinorUnits: actual,
      missingRateDates: missingDates.toSet().toList(),
    );
  }
}

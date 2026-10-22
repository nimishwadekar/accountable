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
    final monthDate = _dateOnly(month);
    return [
      for (final allocation in data.incomeAllocations.where(
        (allocation) => allocation.incomeCategoryId == incomeCategoryId,
      ))
        _progress(
          allocation,
          monthDate,
          data.transactions.where((transaction) {
            final transactionDate = _dateOnly(transaction.date);
            return transaction.type == TransactionType.income &&
                transaction.categoryId == incomeCategoryId &&
                transaction.destinationAccountId ==
                    allocation.incomeAccountId &&
                transactionDate.year == monthDate.year &&
                transactionDate.month == monthDate.month &&
                _isWithinAllocationPeriod(transactionDate, allocation);
          }).length,
        ),
    ];
  }

  IncomeAllocationProgress _progress(
    IncomeAllocation allocation,
    DateTime month,
    int incomeCount,
  ) {
    final expected =
        allocation.expectedAmountPerIncome.minorUnits * incomeCount;
    final missingDates = <DateTime>[];
    var actual = 0;
    for (final transaction in data.transactions) {
      final transactionDate = _dateOnly(transaction.date);
      if (transaction.type != TransactionType.transfer ||
      transaction.sourceAccountId != allocation.incomeAccountId ||
      transaction.categoryId != allocation.transferCategoryId ||
          transactionDate.year != month.year ||
          transactionDate.month != month.month ||
          !_isWithinAllocationPeriod(transactionDate, allocation)) {
        continue;
      }
      final amount = transaction.sourceAmount;
      if (amount == null) continue;
      actual += amount.minorUnits;
    }
    return IncomeAllocationProgress(
      allocation: allocation,
      expectedUsdMinorUnits: expected,
      actualUsdMinorUnits: actual,
      missingRateDates: missingDates.toSet().toList(),
    );
  }

  static bool _isWithinAllocationPeriod(
    DateTime date,
    IncomeAllocation allocation,
  ) {
    final normalizedDate = _dateOnly(date);
    final startDate = _dateOnly(allocation.startDate);
    final endDate = allocation.endDate == null
        ? null
        : _dateOnly(allocation.endDate!);
    return !normalizedDate.isBefore(startDate) &&
        (endDate == null || !normalizedDate.isAfter(endDate));
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

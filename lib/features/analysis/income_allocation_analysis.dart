import '../../data/data.dart';

class IncomeAllocationProgress {
  const IncomeAllocationProgress({
    required this.allocation,
    required this.expectedAmount,
    required this.actualAmount,
  });

  final IncomeAllocation allocation;
  final Money expectedAmount;
  final Money actualAmount;

  double? get percentage => expectedAmount.minorUnits == 0
      ? null
      : actualAmount.minorUnits / expectedAmount.minorUnits * 100;
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
          _transactionsInMonth(monthDate).where((transaction) {
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
    final expectedMinorUnits =
        allocation.expectedAmountPerIncome.minorUnits * incomeCount;
    var actualMinorUnits = 0;
    for (final transaction in _transactionsInMonth(month)) {
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
      actualMinorUnits += amount.minorUnits;
    }
    return IncomeAllocationProgress(
      allocation: allocation,
      expectedAmount: Money(
        minorUnits: expectedMinorUnits,
        currencyId: allocation.expectedAmountPerIncome.currencyId,
      ),
      actualAmount: Money(
        minorUnits: actualMinorUnits,
        currencyId: allocation.expectedAmountPerIncome.currencyId,
      ),
    );
  }

  Iterable<Transaction> _transactionsInMonth(DateTime month) {
    return data.transactionsByMonth[DateTime.utc(month.year, month.month)] ??
        const <Transaction>[];
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

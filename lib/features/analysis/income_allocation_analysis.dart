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
  }) =>
      analyzeAll(
        month: month,
        incomeCategoryIds: {incomeCategoryId},
      )[incomeCategoryId] ??
      const [];

  Map<String, List<IncomeAllocationProgress>> analyzeAll({
    required DateTime month,
    required Set<String> incomeCategoryIds,
  }) {
    final monthDate = _dateOnly(month);
    final allocationsByCategory = <String, List<IncomeAllocation>>{};
    final byIncomeCategoryAndAccount =
        <(String, String), List<IncomeAllocation>>{};
    final byTransferCategoryAndSource =
        <(String, String), List<IncomeAllocation>>{};
    final incomeCounts = <String, int>{};
    final transferTotals = <String, int>{};
    for (final allocation in data.incomeAllocations) {
      if (!incomeCategoryIds.contains(allocation.incomeCategoryId)) continue;
      allocationsByCategory
          .putIfAbsent(allocation.incomeCategoryId, () => [])
          .add(allocation);
      byIncomeCategoryAndAccount
          .putIfAbsent((
            allocation.incomeCategoryId,
            allocation.incomeAccountId,
          ), () => [])
          .add(allocation);
      byTransferCategoryAndSource
          .putIfAbsent((
            allocation.transferCategoryId,
            allocation.incomeAccountId,
          ), () => [])
          .add(allocation);
      incomeCounts[allocation.id] = 0;
      transferTotals[allocation.id] = 0;
    }

    for (final transaction in _transactionsInMonth(monthDate)) {
      final transactionDate = _dateOnly(transaction.date);
      if (transactionDate.year != monthDate.year ||
          transactionDate.month != monthDate.month) {
        continue;
      }
      if (transaction.type == TransactionType.income &&
          transaction.categoryId != null &&
          incomeCategoryIds.contains(transaction.categoryId)) {
        final matchingAllocations =
            byIncomeCategoryAndAccount[(
              transaction.categoryId!,
              transaction.destinationAccountId ?? '',
            )] ??
            const <IncomeAllocation>[];
        for (final allocation in matchingAllocations) {
          if (_isWithinAllocationPeriod(transactionDate, allocation)) {
            incomeCounts[allocation.id] = incomeCounts[allocation.id]! + 1;
          }
        }
      } else if (transaction.type == TransactionType.transfer &&
          transaction.sourceAccountId != null &&
          transaction.categoryId != null &&
          transaction.sourceAmount != null) {
        final matchingAllocations =
            byTransferCategoryAndSource[(
              transaction.categoryId!,
              transaction.sourceAccountId!,
            )] ??
            const <IncomeAllocation>[];
        for (final allocation in matchingAllocations) {
          if (_isWithinAllocationPeriod(transactionDate, allocation)) {
            transferTotals[allocation.id] =
                transferTotals[allocation.id]! +
                transaction.sourceAmount!.minorUnits;
          }
        }
      }
    }

    return {
      for (final categoryId in incomeCategoryIds)
        categoryId: [
          for (final allocation
              in allocationsByCategory[categoryId] ?? const [])
            IncomeAllocationProgress(
              allocation: allocation,
              expectedAmount: Money(
                minorUnits:
                    allocation.expectedAmountPerIncome.minorUnits *
                    incomeCounts[allocation.id]!,
                currencyId: allocation.expectedAmountPerIncome.currencyId,
              ),
              actualAmount: Money(
                minorUnits: transferTotals[allocation.id]!,
                currencyId: allocation.expectedAmountPerIncome.currencyId,
              ),
            ),
        ],
    };
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

import 'money.dart';

class IncomeAllocation {
  const IncomeAllocation({
    required this.id,
    required this.name,
    required this.incomeCategoryId,
    required this.incomeAccountId,
    required this.transferCategoryId,
    required this.expectedAmountPerIncome,
    required this.startDate,
    required this.endDate,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String incomeCategoryId;
  final String incomeAccountId;
  final String transferCategoryId;
  final Money expectedAmountPerIncome;
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime createdAt;
  final DateTime updatedAt;
}

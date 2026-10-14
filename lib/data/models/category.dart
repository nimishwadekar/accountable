import 'transaction.dart';

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.allowedTransactionTypes,
  });

  final String id;
  final String name;
  final Set<TransactionType> allowedTransactionTypes;
}

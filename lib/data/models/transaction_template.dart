import 'money.dart';
import 'transaction.dart';

class TransactionTemplate {
  const TransactionTemplate({
    required this.id,
    required this.name,
    required this.type,
    this.date,
    this.description,
    this.categoryId,
    this.tagId,
    this.sourceAccountId,
    this.sourceAmount,
    this.destinationAccountId,
    this.destinationAmount,
    this.isFavorite = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final TransactionType type;
  final DateTime? date;
  final String? description;
  final String? categoryId;
  final String? tagId;
  final String? sourceAccountId;
  final Money? sourceAmount;
  final String? destinationAccountId;
  final Money? destinationAmount;
  final bool isFavorite;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasDescription => description != null && description!.isNotEmpty;
  bool get hasCategory => categoryId != null;
  bool get hasTag => tagId != null;
  bool get hasSourceAccount => sourceAccountId != null;
  bool get hasSourceAmount => sourceAmount != null;
  bool get hasDestinationAccount => destinationAccountId != null;
  bool get hasDestinationAmount => destinationAmount != null;

  TransactionTemplate copyWith({String? name, bool? isFavorite}) =>
      TransactionTemplate(
        id: id,
        name: name ?? this.name,
        type: type,
        date: date,
        description: description,
        categoryId: categoryId,
        tagId: tagId,
        sourceAccountId: sourceAccountId,
        sourceAmount: sourceAmount,
        destinationAccountId: destinationAccountId,
        destinationAmount: destinationAmount,
        isFavorite: isFavorite ?? this.isFavorite,
        createdAt: createdAt,
        updatedAt: DateTime.now().toUtc(),
      );
}

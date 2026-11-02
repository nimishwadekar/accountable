import 'money.dart';
import 'currency.dart';
import 'template_option.dart';
import 'transaction.dart';

class TransactionTemplate {
  const TransactionTemplate({
    required this.id,
    required this.name,
    required this.type,
    this.date,
    this.dateOptions = const [],
    this.description,
    this.descriptionOptions = const [],
    this.categoryId,
    this.categoryOptions = const [],
    this.tagId,
    this.tagOptions = const [],
    this.sourceAccountId,
    this.sourceAccountOptions = const [],
    this.sourceAmount,
    this.sourceAmountOptions = const [],
    this.destinationAccountId,
    this.destinationAccountOptions = const [],
    this.destinationAmount,
    this.destinationAmountOptions = const [],
    this.isFavorite = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final TransactionType type;
  final DateTime? date;
  final List<TemplateOption<DateTime>> dateOptions;
  final String? description;
  final List<TemplateOption<String>> descriptionOptions;
  final String? categoryId;
  final List<TemplateOption<String>> categoryOptions;
  final String? tagId;
  final List<TemplateOption<String>> tagOptions;
  final String? sourceAccountId;
  final List<TemplateOption<String>> sourceAccountOptions;
  final Money? sourceAmount;
  final List<TemplateOption<String>> sourceAmountOptions;
  final String? destinationAccountId;
  final List<TemplateOption<String>> destinationAccountOptions;
  final Money? destinationAmount;
  final List<TemplateOption<String>> destinationAmountOptions;
  final bool isFavorite;
  final DateTime createdAt;
  final DateTime updatedAt;

  List<TemplateOption<DateTime>> get effectiveDateOptions =>
      dateOptions.isEmpty ? legacyTemplateOption(date) : dateOptions;
  List<TemplateOption<String>> get effectiveDescriptionOptions =>
      descriptionOptions.isEmpty
      ? legacyTemplateOption(description)
      : descriptionOptions;
  List<TemplateOption<String>> get effectiveCategoryOptions =>
      categoryOptions.isEmpty
      ? legacyTemplateOption(categoryId)
      : categoryOptions;
  List<TemplateOption<String>> get effectiveTagOptions =>
      tagOptions.isEmpty ? legacyTemplateOption(tagId) : tagOptions;
  List<TemplateOption<String>> get effectiveSourceAccountOptions =>
      sourceAccountOptions.isEmpty
      ? legacyTemplateOption(sourceAccountId)
      : sourceAccountOptions;
  List<TemplateOption<String>> get effectiveDestinationAccountOptions =>
      destinationAccountOptions.isEmpty
      ? legacyTemplateOption(destinationAccountId)
      : destinationAccountOptions;

  List<TemplateOption<String>> effectiveSourceAmountOptions(
    Map<String, CurrencyDefinition> currencies,
  ) => sourceAmountOptions.isNotEmpty
      ? sourceAmountOptions
      : sourceAmount == null
      ? const []
      : [
          TemplateOption(
            value: sourceAmount!.toMajorUnitsString(
              currencies[sourceAmount!.currencyId]!,
            ),
            isDefault: true,
          ),
        ];

  List<TemplateOption<String>> effectiveDestinationAmountOptions(
    Map<String, CurrencyDefinition> currencies,
  ) => destinationAmountOptions.isNotEmpty
      ? destinationAmountOptions
      : destinationAmount == null
      ? const []
      : [
          TemplateOption(
            value: destinationAmount!.toMajorUnitsString(
              currencies[destinationAmount!.currencyId]!,
            ),
            isDefault: true,
          ),
        ];

  bool get hasDescription => effectiveDescriptionOptions.isNotEmpty;
  bool get hasCategory => effectiveCategoryOptions.isNotEmpty;
  bool get hasTag => effectiveTagOptions.isNotEmpty;
  bool get hasSourceAccount => effectiveSourceAccountOptions.isNotEmpty;
  bool get hasSourceAmount =>
      sourceAmountOptions.isNotEmpty || sourceAmount != null;
  bool get hasDestinationAccount =>
      effectiveDestinationAccountOptions.isNotEmpty;
  bool get hasDestinationAmount =>
      destinationAmountOptions.isNotEmpty || destinationAmount != null;

  TransactionTemplate copyWith({String? name, bool? isFavorite}) =>
      TransactionTemplate(
        id: id,
        name: name ?? this.name,
        type: type,
        date: date,
        dateOptions: dateOptions,
        description: description,
        descriptionOptions: descriptionOptions,
        categoryId: categoryId,
        categoryOptions: categoryOptions,
        tagId: tagId,
        tagOptions: tagOptions,
        sourceAccountId: sourceAccountId,
        sourceAccountOptions: sourceAccountOptions,
        sourceAmount: sourceAmount,
        sourceAmountOptions: sourceAmountOptions,
        destinationAccountId: destinationAccountId,
        destinationAccountOptions: destinationAccountOptions,
        destinationAmount: destinationAmount,
        destinationAmountOptions: destinationAmountOptions,
        isFavorite: isFavorite ?? this.isFavorite,
        createdAt: createdAt,
        updatedAt: DateTime.now().toUtc(),
      );
}

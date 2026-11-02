import 'account.dart';
import 'currency.dart';
import 'money.dart';
import 'template_option.dart';
import 'transaction.dart';
import 'transaction_description_pattern.dart';
import 'transaction_template.dart';

class TransactionTemplateCodec {
  const TransactionTemplateCodec._();

  static List<String> encodeRow(
    TransactionTemplate template, {
    required Map<String, Account> accounts,
    required Map<String, CurrencyDefinition> currencies,
  }) {
    String amountCell({
      required List<TemplateOption<String>> options,
      required Money? legacyAmount,
      required String? legacyAccountId,
      required String fieldName,
    }) {
      if (options.isNotEmpty) {
        return encodeTemplateOptions(
          options,
          encodeValue: (value) => value,
          fieldName: fieldName,
        );
      }
      if (legacyAmount == null) return '';
      final accountId = legacyAccountId;
      if (accountId == null) {
        throw StateError('$fieldName requires an account.');
      }
      final account = accounts[accountId];
      if (account == null) {
        throw StateError('Unknown account: $accountId.');
      }
      if (account.currencyId != legacyAmount.currencyId) {
        throw StateError('$fieldName has an invalid account currency.');
      }
      final currency = currencies[account.currencyId];
      if (currency == null) {
        throw StateError('Unknown currency ${account.currencyId}.');
      }
      return legacyAmount.toMajorUnitsString(currency);
    }

    final descriptions = template.descriptionOptions.isNotEmpty
        ? template.descriptionOptions
        : legacyTemplateOption(template.description);
    return [
      template.id,
      template.name,
      template.type.wireValue,
      encodeTemplateOptions(
        template.effectiveDateOptions,
        encodeValue: _dateString,
        fieldName: 'date',
      ),
      encodeDescriptionOptions(descriptions),
      encodeTemplateOptions(
        template.effectiveCategoryOptions,
        encodeValue: (value) => value,
        fieldName: 'category',
      ),
      encodeTemplateOptions(
        template.effectiveTagOptions,
        encodeValue: (value) => value,
        fieldName: 'tag',
      ),
      encodeTemplateOptions(
        template.effectiveSourceAccountOptions,
        encodeValue: (value) => value,
        fieldName: 'source_account_id',
      ),
      amountCell(
        options: template.sourceAmountOptions,
        legacyAmount: template.sourceAmount,
        legacyAccountId:
            template.sourceAccountId ??
            defaultOrOnlyTemplateOption(template.effectiveSourceAccountOptions),
        fieldName: 'source_amount',
      ),
      encodeTemplateOptions(
        template.effectiveDestinationAccountOptions,
        encodeValue: (value) => value,
        fieldName: 'dest_account_id',
      ),
      amountCell(
        options: template.destinationAmountOptions,
        legacyAmount: template.destinationAmount,
        legacyAccountId:
            template.destinationAccountId ??
            defaultOrOnlyTemplateOption(
              template.effectiveDestinationAccountOptions,
            ),
        fieldName: 'dest_amount',
      ),
      template.createdAt.toUtc().toIso8601String(),
      template.updatedAt.toUtc().toIso8601String(),
      template.isFavorite.toString().toUpperCase(),
    ];
  }

  static List<TemplateOption<String>> parseDescriptionOptions(String? source) {
    if (source == null || source.isEmpty) return const [];
    final options = <TemplateOption<String>>[];
    final seen = <String>{};
    var defaultCount = 0;
    for (final rawOption in _splitDescriptionOptions(source)) {
      var value = rawOption.trim();
      final isDefault = value.startsWith(templateDefaultMarker);
      if (isDefault) {
        defaultCount++;
        value = value.substring(templateDefaultMarker.length).trim();
      }
      if (value.isEmpty) {
        throw const FormatException('Description contains an empty option.');
      }
      TransactionDescriptionPattern.parse(value);
      if (!seen.add(value)) {
        throw FormatException(
          'Description contains a duplicate option: $value.',
        );
      }
      options.add(TemplateOption(value: value, isDefault: isDefault));
    }
    if (defaultCount > 1) {
      throw const FormatException(
        'Description can have only one default option.',
      );
    }
    return List.unmodifiable(options);
  }

  static String encodeDescriptionOptions(
    Iterable<TemplateOption<String>> options,
  ) {
    final values = options.toList(growable: false);
    if (values.isEmpty) return '';
    if (values.where((option) => option.isDefault).length > 1) {
      throw const FormatException(
        'Description can have only one default option.',
      );
    }
    final seen = <String>{};
    final encoded = <String>[];
    for (final option in values) {
      final value = option.value.trim();
      if (value.isEmpty) {
        throw const FormatException('Description has an empty option.');
      }
      TransactionDescriptionPattern.parse(value);
      if (!seen.add(value)) {
        throw FormatException(
          'Description contains a duplicate option: $value.',
        );
      }
      encoded.add(
        '${values.length > 1 && option.isDefault ? templateDefaultMarker : ''}'
        '$value',
      );
    }
    return encoded.join(templateOptionSeparator);
  }

  static List<String> _splitDescriptionOptions(String source) {
    final options = <String>[];
    var start = 0;
    var index = 0;
    var braceDepth = 0;
    while (index < source.length) {
      final char = source[index];
      if (char == '{' &&
          index + 1 < source.length &&
          source[index + 1] == '{') {
        index += 2;
        continue;
      }
      if (char == '}' &&
          index + 1 < source.length &&
          source[index + 1] == '}') {
        index += 2;
        continue;
      }
      if (char == '{') {
        braceDepth++;
      } else if (char == '}') {
        braceDepth--;
      } else if (char == templateOptionSeparator && braceDepth == 0) {
        options.add(source.substring(start, index));
        start = index + 1;
      }
      index++;
    }
    options.add(source.substring(start));
    return options;
  }

  static String _dateString(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

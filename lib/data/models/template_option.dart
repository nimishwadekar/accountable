class TemplateOption<T> {
  const TemplateOption({required this.value, this.isDefault = false});

  final T value;
  final bool isDefault;
}

const templateOptionSeparator = ';';
const templateDefaultMarker = '^';
const templatePlaceholderOptionSeparator = '~';

bool containsReservedTemplateCharacter(String value) =>
    value.contains(templateOptionSeparator) ||
    value.contains(templateDefaultMarker) ||
    value.contains(templatePlaceholderOptionSeparator);

String? validateTemplateEntryText(String? value) {
  if (value == null) return null;
  return containsReservedTemplateCharacter(value)
      ? 'The characters ;, ^, and ~ are reserved for template options.'
      : null;
}

List<TemplateOption<String>> parseTemplateOptions(
  String source, {
  required String fieldName,
}) {
  if (source.isEmpty) return const [];
  final result = <TemplateOption<String>>[];
  final seen = <String>{};
  var defaultCount = 0;
  for (final rawOption in source.split(templateOptionSeparator)) {
    var value = rawOption.trim();
    final isDefault = value.startsWith(templateDefaultMarker);
    if (isDefault) {
      defaultCount++;
      value = value.substring(templateDefaultMarker.length).trim();
    }
    if (value.isEmpty) {
      throw FormatException('$fieldName contains an empty option.');
    }
    if (containsReservedTemplateCharacter(value)) {
      throw FormatException(
        '$fieldName contains a reserved character in an option value.',
      );
    }
    if (!seen.add(value)) {
      throw FormatException('$fieldName contains a duplicate option: $value.');
    }
    result.add(TemplateOption(value: value, isDefault: isDefault));
  }
  if (defaultCount > 1) {
    throw FormatException('$fieldName can have only one default option.');
  }
  return List.unmodifiable(result);
}

String encodeTemplateOptions<T>(
  Iterable<TemplateOption<T>> options, {
  required String Function(T value) encodeValue,
  required String fieldName,
}) {
  final values = options.toList(growable: false);
  if (values.isEmpty) return '';
  if (values.where((option) => option.isDefault).length > 1) {
    throw FormatException('$fieldName can have only one default option.');
  }
  final encoded = <String>[];
  final seen = <String>{};
  for (final option in values) {
    final value = encodeValue(option.value).trim();
    if (value.isEmpty) throw FormatException('$fieldName has an empty option.');
    if (containsReservedTemplateCharacter(value)) {
      throw FormatException(
        '$fieldName contains a reserved character in an option value.',
      );
    }
    if (!seen.add(value)) {
      throw FormatException('$fieldName contains a duplicate option: $value.');
    }
    encoded.add(
      '${values.length > 1 && option.isDefault ? templateDefaultMarker : ''}'
      '$value',
    );
  }
  return encoded.join(templateOptionSeparator);
}

List<TemplateOption<T>> legacyTemplateOption<T>(T? value) =>
    value == null ? const [] : [TemplateOption(value: value, isDefault: true)];

T? defaultOrOnlyTemplateOption<T>(Iterable<TemplateOption<T>> options) {
  final values = options.toList(growable: false);
  if (values.length == 1) return values.single.value;
  for (final option in values) {
    if (option.isDefault) return option.value;
  }
  return null;
}

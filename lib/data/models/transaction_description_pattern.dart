import 'template_option.dart';

/// A description pattern with required, named text inputs.
///
/// `{Merchant}` creates a free-text input. `{Merchant~Cafe;^Office}` creates
/// an input restricted to two choices, with `Office` selected by default.
/// `{{` and `}}` escape literal braces.
class TransactionDescriptionPattern {
  const TransactionDescriptionPattern._(
    this.source,
    this.placeholders,
    this.placeholderOptions,
  );

  final String source;
  final List<String> placeholders;
  final Map<String, List<TemplateOption<String>>> placeholderOptions;

  static TransactionDescriptionPattern parse(String source) {
    final placeholders = <String>[];
    final optionsByName = <String, List<TemplateOption<String>>>{};
    var index = 0;
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
      if (char == '}') {
        throw const FormatException('A closing brace must be escaped as }}.');
      }
      if (char != '{') {
        _rejectReservedLiteral(char);
        index++;
        continue;
      }

      final close = source.indexOf('}', index + 1);
      if (close < 0) {
        throw const FormatException(
          'A placeholder is missing its closing brace.',
        );
      }
      final parsed = _parsePlaceholder(source.substring(index + 1, close));
      final previous = optionsByName[parsed.name];
      if (previous != null && !_sameOptions(previous, parsed.options)) {
        throw FormatException(
          'Repeated placeholder "${parsed.name}" must use the same options.',
        );
      }
      if (previous == null) {
        placeholders.add(parsed.name);
        optionsByName[parsed.name] = parsed.options;
      }
      index = close + 1;
    }
    return TransactionDescriptionPattern._(
      source,
      List.unmodifiable(placeholders),
      Map.unmodifiable(optionsByName),
    );
  }

  static String encodePlaceholderOptions(
    String source,
    Map<String, List<TemplateOption<String>>> optionsByName,
  ) {
    final pattern = parse(source);
    if (pattern.placeholderOptions.values.any(
      (options) => options.isNotEmpty,
    )) {
      throw const FormatException(
        'Enter placeholder names in braces; configure their choices below.',
      );
    }
    final result = StringBuffer();
    var index = 0;
    while (index < source.length) {
      final char = source[index];
      if (char == '{' &&
          index + 1 < source.length &&
          source[index + 1] == '{') {
        result.write('{{');
        index += 2;
      } else if (char == '}' &&
          index + 1 < source.length &&
          source[index + 1] == '}') {
        result.write('}}');
        index += 2;
      } else if (char == '{') {
        final close = source.indexOf('}', index + 1);
        final name = _parsePlaceholder(source.substring(index + 1, close)).name;
        final options = optionsByName[name] ?? const <TemplateOption<String>>[];
        if (options.isEmpty) {
          result.write('{$name}');
        } else {
          result.write(
            '{$name~${encodeTemplateOptions(options, encodeValue: (value) => value, fieldName: 'Placeholder "$name"')}}',
          );
        }
        index = close + 1;
      } else {
        result.write(char);
        index++;
      }
    }
    return result.toString();
  }

  String compose(Map<String, String> values) {
    final result = StringBuffer();
    var index = 0;
    while (index < source.length) {
      final char = source[index];
      if (char == '{' &&
          index + 1 < source.length &&
          source[index + 1] == '{') {
        result.write('{');
        index += 2;
      } else if (char == '}' &&
          index + 1 < source.length &&
          source[index + 1] == '}') {
        result.write('}');
        index += 2;
      } else if (char == '{') {
        final close = source.indexOf('}', index + 1);
        final name = _parsePlaceholder(source.substring(index + 1, close)).name;
        final value = values[name];
        if (value == null || value.trim().isEmpty) {
          throw FormatException('A value is required for "$name".');
        }
        final reservedError = validateTemplateEntryText(value);
        if (reservedError != null) throw FormatException(reservedError);
        result.write(value.trim());
        index = close + 1;
      } else {
        result.write(char);
        index++;
      }
    }
    return result.toString().trim();
  }

  static ({String name, List<TemplateOption<String>> options})
  _parsePlaceholder(String source) {
    final separator = source.indexOf(templatePlaceholderOptionSeparator);
    final name = (separator < 0 ? source : source.substring(0, separator))
        .trim();
    if (name.isEmpty || name.contains('{')) {
      throw const FormatException('A placeholder needs a non-empty label.');
    }
    if (containsReservedTemplateCharacter(name)) {
      throw const FormatException(
        'Placeholder labels cannot contain ;, ^, or ~.',
      );
    }
    if (separator < 0) return (name: name, options: const []);
    if (source.indexOf(templatePlaceholderOptionSeparator, separator + 1) >=
        0) {
      throw const FormatException(
        'A placeholder can contain only one ~ separator.',
      );
    }
    final optionSource = source.substring(separator + 1);
    if (optionSource.isEmpty) {
      throw FormatException('Placeholder "$name" has no options.');
    }
    final options = parseTemplateOptions(
      optionSource,
      fieldName: 'Placeholder "$name"',
    );
    for (final option in options) {
      if (option.value.contains('{') || option.value.contains('}')) {
        throw FormatException(
          'Placeholder "$name" options cannot contain braces.',
        );
      }
    }
    return (name: name, options: options);
  }

  static bool _sameOptions(
    List<TemplateOption<String>> first,
    List<TemplateOption<String>> second,
  ) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index].value != second[index].value ||
          first[index].isDefault != second[index].isDefault) {
        return false;
      }
    }
    return true;
  }

  static void _rejectReservedLiteral(String value) {
    if (containsReservedTemplateCharacter(value)) {
      throw const FormatException(
        'The characters ;, ^, and ~ are reserved for template options.',
      );
    }
  }
}

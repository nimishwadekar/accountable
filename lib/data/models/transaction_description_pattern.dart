/// A description pattern with required, named text inputs.
///
/// `{Merchant Name}` creates an input. `{{` and `}}` escape literal braces.
class TransactionDescriptionPattern {
  const TransactionDescriptionPattern._(this.source, this.placeholders);

  final String source;
  final List<String> placeholders;

  static TransactionDescriptionPattern parse(String source) {
    final placeholders = <String>[];
    final seen = <String>{};
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
        index++;
        continue;
      }

      final close = source.indexOf('}', index + 1);
      if (close < 0) {
        throw const FormatException(
          'A placeholder is missing its closing brace.',
        );
      }
      final label = source.substring(index + 1, close).trim();
      if (label.isEmpty || label.contains('{')) {
        throw const FormatException('A placeholder needs a non-empty label.');
      }
      if (seen.add(label)) placeholders.add(label);
      index = close + 1;
    }
    return TransactionDescriptionPattern._(
      source,
      List.unmodifiable(placeholders),
    );
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
        final label = source.substring(index + 1, close).trim();
        final value = values[label];
        if (value == null || value.trim().isEmpty) {
          throw FormatException('A value is required for "$label".');
        }
        result.write(value.trim());
        index = close + 1;
      } else {
        result.write(char);
        index++;
      }
    }
    return result.toString().trim();
  }
}

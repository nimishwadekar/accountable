DateTime parseDateOnly(String value, {required String fieldName}) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value.trim());
  if (match == null) {
    throw FormatException('Invalid date in $fieldName: $value.');
  }

  final date = DateTime.utc(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
  if (date.year.toString().padLeft(4, '0') != match.group(1) ||
      date.month.toString().padLeft(2, '0') != match.group(2) ||
      date.day.toString().padLeft(2, '0') != match.group(3)) {
    throw FormatException('Invalid date in $fieldName: $value.');
  }
  return date;
}

DateTime parseUtcTimestamp(String value, {required String fieldName}) {
  var normalized = value.trim();
  if (normalized.contains(' ')) {
    normalized = normalized.replaceFirst(' ', 'T');
  }
  if (!normalized.endsWith('Z') &&
      !RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(normalized)) {
    normalized = '${normalized}Z';
  }

  try {
    return DateTime.parse(normalized).toUtc();
  } on FormatException {
    throw FormatException('Invalid UTC timestamp in $fieldName: $value.');
  }
}

String requiredValue(Map<String, String> row, String fieldName) {
  final value = row[fieldName]?.trim();
  if (value == null || value.isEmpty) {
    throw FormatException('Missing required field: $fieldName.');
  }
  return value;
}

String? optionalValue(Map<String, String> row, String fieldName) {
  final value = row[fieldName]?.trim();
  return value == null || value.isEmpty ? null : value;
}

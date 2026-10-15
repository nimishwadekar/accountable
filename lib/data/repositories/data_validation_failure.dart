class DataValidationIssue {
  const DataValidationIssue({
    required this.table,
    required this.message,
    this.row,
    this.field,
    this.technicalDetails,
  });

  final String table;
  final String message;
  final int? row;
  final String? field;
  final String? technicalDetails;

  String get location {
    final parts = <String>[table];
    if (row != null) parts.add('row $row');
    if (field != null) parts.add(field!);
    return parts.join(' · ');
  }
}

class DataValidationFailure implements Exception {
  const DataValidationFailure(this.issues);

  final List<DataValidationIssue> issues;

  @override
  String toString() => issues.map((issue) => issue.message).join('\n');
}

DataValidationIssue issueFromError(String table, Object error) {
  return DataValidationIssue(
    table: table,
    message: _friendlyMessage(error),
    technicalDetails: error.toString(),
  );
}

String _friendlyMessage(Object error) {
  final raw = error.toString();
  final prefix = raw.indexOf(': ');
  return prefix >= 0 ? raw.substring(prefix + 2) : raw;
}

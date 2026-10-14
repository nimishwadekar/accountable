class DataLoadException implements Exception {
  const DataLoadException({
    required this.tableName,
    required this.message,
    this.cause,
  });

  final String tableName;
  final String message;
  final Object? cause;

  @override
  String toString() {
    final causeText = cause == null ? '' : ' Cause: $cause';
    return 'Failed to load $tableName: $message$causeText';
  }
}

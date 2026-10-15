import '../repositories/data_validation_failure.dart';

class ModelParseResult<T> {
  const ModelParseResult({required this.values, required this.issues});

  final List<T> values;
  final List<DataValidationIssue> issues;

  bool get hasIssues => issues.isNotEmpty;
}

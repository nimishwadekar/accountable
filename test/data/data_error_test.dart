import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';

void main() {
  test('formats validation issue locations and technical errors', () {
    const issue = DataValidationIssue(
      table: 'Transactions',
      row: 4,
      field: 'date',
      message: 'Invalid date.',
      technicalDetails: 'FormatException: invalid date',
    );
    final failure = DataValidationFailure([issue]);

    expect(issue.location, 'Transactions · row 4 · date');
    expect(failure.toString(), 'Invalid date.');
    expect(issue.technicalDetails, contains('FormatException'));
  });

  test('converts parser errors into validation issues', () {
    final issue = issueFromError(
      'Accounts',
      const FormatException('Missing required field.'),
    );

    expect(issue.table, 'Accounts');
    expect(issue.message, 'Missing required field.');
    expect(issue.technicalDetails, contains('FormatException'));
  });

  test('reports whether a model parse result has issues', () {
    const clean = ModelParseResult<int>(values: [1], issues: []);
    final invalid = ModelParseResult<int>(
      values: const [],
      issues: [
        const DataValidationIssue(table: 'Accounts', message: 'Invalid.'),
      ],
    );

    expect(clean.hasIssues, isFalse);
    expect(invalid.hasIssues, isTrue);
  });

  test('formats data-load exceptions with their table names', () {
    const error = DataLoadException(
      tableName: 'Currencies',
      message: 'Could not read table.',
    );

    expect(error.toString(), contains('Currencies'));
    expect(error.toString(), contains('Could not read table.'));
  });
}

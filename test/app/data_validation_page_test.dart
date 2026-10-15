import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/pages/app_pages.dart';
import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';

void main() {
  testWidgets('groups repeated errors and summarizes row lists', (
    tester,
  ) async {
    final failure = DataValidationFailure([
      for (var row = 2; row <= 6; row++)
        DataValidationIssue(
          table: 'Transactions',
          row: row,
          field: 'source_account_id',
          message: 'Source account is missing.',
          technicalDetails: 'Missing required source account.',
        ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: DataValidationPage(failure: failure, onReload: () {}),
      ),
    );

    expect(
      find.text(
        'Transactions · rows 2, 3, 4 and 2 other rows · source_account_id',
      ),
      findsOneWidget,
    );
  });

  testWidgets('groups validation errors and exposes technical details', (
    tester,
  ) async {
    final failure = DataValidationFailure([
      const DataValidationIssue(
        table: 'Accounts',
        row: 2,
        field: 'opening_balance',
        message: 'Current balance is missing.',
        technicalDetails: 'FormatException: Missing required field.',
      ),
      const DataValidationIssue(
        table: 'Transactions',
        row: 7,
        field: 'date',
        message: 'Transaction date is invalid.',
        technicalDetails: 'FormatException: Invalid date.',
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: DataValidationPage(failure: failure, onReload: () {}),
      ),
    );

    expect(find.text('Data validation failed'), findsOneWidget);
    expect(find.text('Accounts'), findsOneWidget);
    expect(find.text('Transactions'), findsOneWidget);
    expect(find.text('Current balance is missing.'), findsOneWidget);
    expect(find.text('Reload data'), findsOneWidget);

    await tester.tap(find.text('Technical details'));
    await tester.pump();
    expect(find.textContaining('FormatException'), findsWidgets);
  });
}

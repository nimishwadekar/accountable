import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/pages/transaction_review_sheet.dart';
import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';

void main() {
  testWidgets('shows transaction details and confirms the review', (
    tester,
  ) async {
    final data = await AssetAppDataRepository().load();
    final transaction = data.transactions.first;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: TransactionReviewSheet(transaction: transaction, data: data),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Review Transaction'), findsOneWidget);
    expect(find.text(transaction.description), findsOneWidget);
    expect(find.text('Okay'), findsOneWidget);
  });
}

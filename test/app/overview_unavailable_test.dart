import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/pages/app_pages.dart';
import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';

void main() {
  testWidgets('shows unavailable when no daily net worth exists', (
    tester,
  ) async {
    final data = await AssetAppDataRepository().load();
    final withoutNetWorth = AppDataSnapshot(
      accounts: data.accounts,
      categories: data.categories,
      currencies: data.currencies,
      tags: data.tags,
      transactions: data.transactions,
      exchangeRates: data.exchangeRates,
      dailyAccountBalances: data.dailyAccountBalances,
      dailyNetWorth: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: OverviewPage(data: withoutNetWorth),
      ),
    );
    await tester.pump();

    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('No daily snapshot available'), findsOneWidget);
  });
}

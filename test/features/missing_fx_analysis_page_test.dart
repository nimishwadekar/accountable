import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';
import 'package:accountable/features/analysis/analysis_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows a rebuild error when category FX data is missing', (
    tester,
  ) async {
    final source = await AssetAppDataRepository().load();
    final withoutInrRates = AppDataSnapshot(
      accounts: source.accounts,
      categories: source.categories,
      currencies: source.currencies,
      tags: source.tags,
      transactions: source.transactions,
      exchangeRates: source.exchangeRates
          .where((rate) => rate.currencyId != 'INR')
          .toList(),
      dailyAccountBalances: source.dailyAccountBalances,
      dailyNetWorth: source.dailyNetWorth,
      dailyManualValuations: source.dailyManualValuations,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AnalysisPage(
            data: withoutInrRates,
            onRebuildDailyTables: () async {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Historical exchange rates unavailable'), findsOneWidget);
    expect(find.text('INR · 2026-10-11'), findsOneWidget);
    expect(find.text('Net Worth Trend (USD)'), findsNothing);
    expect(find.text('Spending by Category'), findsNothing);
    expect(find.text('Rebuild daily tables'), findsOneWidget);
  });
}

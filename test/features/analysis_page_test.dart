import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';
import 'package:accountable/features/analysis/analysis_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders net-worth and account history sections', (tester) async {
    final data = await AssetAppDataRepository().load();
    expect(data.accountsById['sbi_nro']!.closingDate, isNotNull);
    final closedAccountFirst = AppDataSnapshot(
      accounts: [
        data.accountsById['sbi_nro']!,
        ...data.accounts.where((account) => account.id != 'sbi_nro'),
      ],
      categories: data.categories,
      currencies: data.currencies,
      tags: data.tags,
      transactions: data.transactions,
      exchangeRates: data.exchangeRates,
      dailyAccountBalances: data.dailyAccountBalances,
      dailyNetWorth: data.dailyNetWorth,
      dailyManualValuations: data.dailyManualValuations,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: AnalysisPage(data: closedAccountFirst)),
      ),
    );
    await tester.pump();

    expect(find.text('Analysis'), findsOneWidget);
    expect(find.text('Net Worth Trend'), findsOneWidget);
    expect(find.text('Individual Account Valuation Trend'), findsOneWidget);
    expect(find.text('All history'), findsNWidgets(2));
    expect(find.byType(LineChart), findsNWidgets(2));
    expect(find.textContaining('Closed on 2026-10-11'), findsNothing);
  });
}

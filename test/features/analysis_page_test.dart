import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/app/pages/app_pages.dart';
import 'package:accountable/data/data.dart';
import 'package:accountable/features/analysis/analysis_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();

  testWidgets('renders net-worth and account history sections', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
    expect(find.text('Net worth (USD)'), findsOneWidget);
    expect(find.text('Account history'), findsOneWidget);
    expect(find.byType(MetricCard), findsNWidgets(3));
    expect(find.text('Monthly Average'), findsOneWidget);
    expect(find.text('Monthly Change'), findsOneWidget);
    expect(
      tester.getRect(find.byType(MetricCard).last).bottom,
      lessThan(tester.getRect(find.text('Net worth (USD)')).top),
    );
    expect(find.text('View missing data'), findsOneWidget);
    expect(find.text('1M'), findsNWidgets(2));
    final charts = find.byType(LineChart);
    expect(charts, findsNWidgets(2));
    for (var index = 0; index < 2; index++) {
      final size = tester.getSize(charts.at(index));
      expect(size.width, greaterThan(300));
      expect(size.height, greaterThan(200));
    }
    expect(find.textContaining('Closed on 2026-10-11'), findsNothing);
    await tester.ensureVisible(find.text('View missing data'));
    await tester.tap(find.text('View missing data'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Missing daily snapshots'), findsWidgets);
    expect(find.textContaining('2026-10-13'), findsOneWidget);

    await tester.ensureVisible(find.text('Categories'));
    await tester.tap(find.text('Categories'));
    await tester.pumpAndSettle();
    expect(find.text('Spending by Category'), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);
    expect(find.text('Net worth (USD)'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'All tags'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'All tags'));
    await tester.pumpAndSettle();
    expect(find.text('Filter categories by tag'), findsOneWidget);
    await tester.tap(find.text('Boston').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, 'Boston'), findsOneWidget);

    await tester.tap(find.text('Trends'));
    await tester.pumpAndSettle();
    expect(find.byType(LineChart), findsNWidgets(2));
    expect(find.text('Account history'), findsOneWidget);
    await tester.ensureVisible(find.text('Categories'));
    await tester.tap(find.text('Categories').first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, 'Boston'), findsOneWidget);
  });
}

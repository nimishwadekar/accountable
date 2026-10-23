import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/theme/design_tokens.dart';
import 'package:accountable/data/data.dart';
import 'package:accountable/features/analysis/analysis_chart_widgets.dart';

void main() {
  testWidgets('shrinks the graph on a narrow screen while retaining labels', (
    tester,
  ) async {
    final data = await AssetAppDataRepository().load();
    final usd = data.currenciesById['USD'];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: LineChartWidget(
              points: [
                ChartPoint(date: DateTime.utc(2026, 10, 1), value: 100),
                ChartPoint(date: DateTime.utc(2026, 10, 2), value: 120),
              ],
              color: AppColors.success,
              currency: usd,
              axisLabel: 'Value (USD)',
              markers: [
                ChartMarker(
                  date: DateTime.utc(2026, 10, 1),
                  label: 'Opened',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final size = tester.getSize(find.byType(LineChart));
    expect(size.width, closeTo(390, 1));
    expect(size.height, lessThan(304));
    expect(size.height, greaterThan(150));
    expect(find.text('Opened'), findsOneWidget);
  });
}

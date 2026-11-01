import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
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
                ChartMarker(date: DateTime.utc(2026, 10, 1), label: 'Opened'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final size = tester.getSize(find.byType(LineChart));
    expect(size.width, greaterThan(250));
    expect(size.width, lessThan(390));
    expect(size.height, lessThan(304));
    expect(size.height, greaterThan(150));
    expect(find.text('Opened'), findsOneWidget);
    expect(find.textContaining('Value (USD)'), findsNothing);
  });

  testWidgets('keeps the vertical scale fixed while scrubbing points', (
    tester,
  ) async {
    const size = Size(390, 844);
    final points = [
      ChartPoint(date: DateTime.utc(2026, 10, 1), value: 100),
      ChartPoint(date: DateTime.utc(2026, 10, 2), value: 900),
      ChartPoint(date: DateTime.utc(2026, 10, 3), value: 250),
      ChartPoint(date: DateTime.utc(2026, 10, 4), value: 300),
    ];
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: Scaffold(
          body: SizedBox(
            width: size.width,
            child: LineChartWidget(
              points: points,
              color: AppColors.success,
              currency: null,
              axisLabel: 'Balance',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final chart = find.byType(LineChart);
    final initialMaxY = tester.widget<LineChart>(chart).data.maxY;
    expect(initialMaxY, greaterThan(980));
    final chartRect = tester.getRect(chart);
    final gesture = await tester.startGesture(
      Offset(chartRect.left + chartRect.width * 0.4, chartRect.center.dy),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    expect(tester.widget<LineChart>(chart).data.maxY, initialMaxY);
    expect(find.text('Oct 3, 2026'), findsOneWidget);

    await gesture.moveTo(
      Offset(chartRect.left + chartRect.width * 0.9, chartRect.center.dy),
    );
    await tester.pump();
    expect(tester.widget<LineChart>(chart).data.maxY, initialMaxY);
    expect(find.text('Oct 4, 2026'), findsOneWidget);

    await gesture.moveTo(
      Offset(chartRect.left + chartRect.width * 0.1, chartRect.center.dy),
    );
    await tester.pump();
    expect(tester.widget<LineChart>(chart).data.maxY, initialMaxY);
    await gesture.up();
    await tester.pump();
  });
}

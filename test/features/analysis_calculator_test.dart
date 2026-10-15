import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';
import 'package:accountable/features/analysis/analysis_calculator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'uses inclusive dates and preserves available daily net-worth points',
    () async {
      final data = await AssetAppDataRepository().load();
      final calculator = AnalysisCalculator(data);
      final range = DateTimeRange(
        start: DateTime.utc(2026, 10, 10),
        end: DateTime.utc(2026, 10, 12),
      );

      final series = calculator.netWorthSeries(range);

      expect(series.points, hasLength(3));
      expect(series.points.first.date, DateTime.utc(2026, 10, 10));
      expect(series.points.last.date, DateTime.utc(2026, 10, 12));
      expect(series.missingDates, isEmpty);
    },
  );

  test('reports missing dates without filling them in', () async {
    final data = await AssetAppDataRepository().load();
    final calculator = AnalysisCalculator(data);
    final range = DateTimeRange(
      start: DateTime.utc(2026, 10, 10),
      end: DateTime.utc(2026, 10, 12),
    );

    final series = calculator.accountBalanceSeries(
      accountId: 'sbi_nro',
      range: range,
    );

    expect(series.points, hasLength(2));
    expect(series.missingDates, [DateTime.utc(2026, 10, 12)]);
  });

  test('closed accounts stop at their inclusive closing date', () async {
    final data = await AssetAppDataRepository().load();
    final calculator = AnalysisCalculator(data);
    final requestedRange = DateTimeRange(
      start: DateTime.utc(2026, 10, 10),
      end: DateTime.utc(2026, 10, 12),
    );

    final range = calculator.accountRange(
      accountId: 'sbi_nro',
      requestedRange: requestedRange,
    );
    final series = calculator.accountBalanceSeries(
      accountId: 'sbi_nro',
      range: range!,
    );

    expect(range.end, DateTime.utc(2026, 10, 11));
    expect(series.points.last.date, DateTime.utc(2026, 10, 11));
    expect(series.missingDates, isEmpty);
  });

  test('all history uses the earliest and latest daily dates', () async {
    final data = await AssetAppDataRepository().load();
    final range = AnalysisCalculator(data).allHistoryRange;

    expect(range?.start, DateTime.utc(2026, 10, 10));
    expect(range?.end, DateTime.utc(2026, 10, 12));
  });
}

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
        end: DateTime.utc(2026, 10, 14),
      );

      final series = calculator.netWorthSeries(range);

      expect(series.points, hasLength(3));
      expect(series.points.first.date, DateTime.utc(2026, 10, 10));
      expect(series.points.last.date, DateTime.utc(2026, 10, 12));
      expect(series.missingDates, [
        DateTime.utc(2026, 10, 13),
        DateTime.utc(2026, 10, 14),
      ]);
    },
  );

  test('reports missing dates without filling them in', () async {
    final data = await AssetAppDataRepository().load();
    final calculator = AnalysisCalculator(data);
    final range = DateTimeRange(
      start: DateTime.utc(2026, 10, 10),
      end: DateTime.utc(2026, 10, 14),
    );

    final series = calculator.accountBalanceSeries(
      accountId: 'sbi_nro',
      range: range,
    );

    expect(series.points, hasLength(2));
    expect(series.missingDates, [
      DateTime.utc(2026, 10, 12),
      DateTime.utc(2026, 10, 13),
      DateTime.utc(2026, 10, 14),
    ]);
  });

  test('closed accounts stop at their inclusive closing date', () async {
    final data = await AssetAppDataRepository().load();
    final calculator = AnalysisCalculator(data);
    final requestedRange = DateTimeRange(
      start: DateTime.utc(2026, 10, 10),
      end: DateTime.utc(2026, 10, 14),
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

  test(
    'manual account history uses valuation values and signed liabilities',
    () async {
      final data = await AssetAppDataRepository().load();
      final series = AnalysisCalculator(data).accountBalanceSeries(
        accountId: 'hdfc-credila-loan',
        range: DateTimeRange(
          start: DateTime.utc(2026, 10, 14),
          end: DateTime.utc(2026, 10, 14),
        ),
      );

      expect(series.points, hasLength(1));
      expect(series.points.single.nativeAmount.minorUnits, lessThan(0));
      expect(series.missingDates, isEmpty);
    },
  );

  test('all history uses the earliest and latest daily dates', () async {
    final data = await AssetAppDataRepository().load();
    final range = AnalysisCalculator(data).allHistoryRange;

    final today = DateTime.now();
    final yesterday = DateTime.utc(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 1));
    expect(range?.start, DateTime.utc(2026, 10, 10));
    expect(range?.end, yesterday);
  });
}

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/app_shell.dart';
import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('pending achievement pulses in navigation and is acknowledged', (
    tester,
  ) async {
    final tables = <String, String>{
      for (final schema in RuntimeTableSchemas.all)
        schema.assetPath: await rootBundle.loadString(schema.assetPath),
    };
    final now = DateTime.now();
    final previousMonth = DateTime.utc(now.year, now.month - 1);
    final currentMonth = DateTime.utc(now.year, now.month);
    tables[DataAssetPaths.achievements] = csv.encode([
      RuntimeTableSchemas.achievements.headers,
      ['ACH001', 'A personal achievement', '100', 'FALSE'],
    ]);
    tables[DataAssetPaths.achievementSettings] = csv.encode([
      RuntimeTableSchemas.achievementSettings.headers,
      ['${previousMonth.year}-${previousMonth.month.toString().padLeft(2, '0')}-01'],
    ]);
    tables[DataAssetPaths.dailyNetWorth] = csv.encode([
      RuntimeTableSchemas.dailyNetWorth.headers,
      ..._month(previousMonth.year, previousMonth.month, 10000),
      for (var day = 1; day < now.day; day++)
        _netWorthRow(currentMonth.year, currentMonth.month, day, 5000),
    ]);
    final store = MemoryLocalDatasetStore(tables);
    final repository = AssetAppDataRepository(store: store);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: AppShell(dataRepository: repository),
        ),
      ),
    );
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.byType(NavigationBar), findsOneWidget);
    final milestonesIcon = find.byIcon(Icons.celebration_outlined);
    expect(milestonesIcon, findsOneWidget);
    await tester.tap(milestonesIcon);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('You did it!'), findsOneWidget);

    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Last completed month average'), findsOneWidget);
    expect(find.textContaining('Provisional'), findsNothing);
    expect(
      csv.decode((await store.read())![DataAssetPaths.achievements]!).last.last,
      'TRUE',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

List<List<Object>> _month(int year, int month, int minorUnits) {
  final days = DateTime.utc(year, month + 1, 0).day;
  return [
    for (var day = 1; day <= days; day++)
      _netWorthRow(year, month, day, minorUnits),
  ];
}

List<Object> _netWorthRow(int year, int month, int day, int minorUnits) => [
  '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}-net',
  '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
  minorUnits / 100,
  DateTime.utc(year, month, day).toIso8601String(),
];

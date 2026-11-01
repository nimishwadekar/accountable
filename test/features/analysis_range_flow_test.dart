import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';
import 'package:accountable/features/analysis/analysis_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  late final AppDataSnapshot data;

  setUpAll(() async {
    data = await AssetAppDataRepository().load();
  });

  testWidgets('updates both chart ranges when a range is selected', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: AnalysisPage(data: data)),
      ),
    );
    await tester.pump();

    expect(find.text('1M'), findsNWidgets(2));
    for (final preset in ['3M', '6M', 'YTD', '1Y', '5Y', 'MAX']) {
      expect(find.text(preset), findsNWidgets(2), reason: '$preset visible');
    }
    expect(find.byType(PopupMenuButton<AnalysisRangePreset>), findsNothing);
    final firstChip = tester.getRect(
      find
          .ancestor(
            of: find.text('1M').first,
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    final firstLabel = tester.getRect(find.text('1M').first);
    expect(firstLabel.center.dy, closeTo(firstChip.center.dy, 1));

    await tester.tap(find.text('3M').first);
    await tester.pump();
    expect(find.text('3M'), findsNWidgets(2));
    final primaryColor = AppTheme.light().colorScheme.onPrimary;
    expect(
      tester
          .widgetList<Text>(find.text('3M'))
          .where((text) => text.style?.color == primaryColor),
      hasLength(1),
      reason: 'Changing the net-worth range must not change the account range.',
    );

    await tester.ensureVisible(find.text('3M').last);
    await tester.tap(find.text('3M').last);
    await tester.pump();
    expect(
      tester
          .widgetList<Text>(find.text('3M'))
          .where((text) => text.style?.color == primaryColor),
      hasLength(2),
    );

    await tester.ensureVisible(find.text('MAX').first);
    await tester.tap(find.text('MAX').first);
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<Text>(find.text('MAX'))
          .where((text) => text.style?.color == primaryColor),
      hasLength(1),
    );

    await tester.ensureVisible(find.text('Categories'));
    await tester.tap(find.text('Categories'));
    await tester.pumpAndSettle();
    expect(find.text('Spending by Category'), findsOneWidget);
    await tester.ensureVisible(find.text('Trends'));
    await tester.tap(find.text('Trends'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<Text>(find.text('MAX'))
          .where((text) => text.style?.color == primaryColor),
      hasLength(1),
    );
  });

  testWidgets('shows and aligns all range presets on compact screens', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in [const Size(430, 932), const Size(320, 740)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(size: size),
            child: Scaffold(body: AnalysisPage(data: data)),
          ),
        ),
      );
      await tester.pump();

      for (final preset in ['1M', '3M', '6M', 'YTD', '1Y', '5Y', 'MAX']) {
        expect(find.text(preset), findsNWidgets(2), reason: '${size.width}px');
      }
      expect(find.byType(PopupMenuButton<AnalysisRangePreset>), findsNothing);
      final selectedText = tester.getRect(find.text('1M').first);
      final selectedChip = tester.getRect(
        find
            .ancestor(
              of: find.text('1M').first,
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      expect(selectedText.center.dy, closeTo(selectedChip.center.dy, 1));
      expect(tester.takeException(), isNull, reason: '${size.width}px');
    }
  });
}

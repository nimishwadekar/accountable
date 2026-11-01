import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';
import 'package:accountable/features/analysis/analysis_page.dart';
import 'package:accountable/app/session_ui_preferences.dart';

void main() {
  testWidgets(
    'Analysis view selector and category controls survive 200% text',
    (tester) async {
      const size = Size(320, 900);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await SessionUiPreferences.instance.startSession();
      final data = await AssetAppDataRepository().load();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(size: size)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: Scaffold(body: AnalysisPage(data: data)),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Trends'), findsOneWidget);
      expect(find.text('Categories'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();
      expect(find.text('Spending by Category'), findsOneWidget);
      expect(find.text('Income by Category'), findsOneWidget);
      expect(find.text('All tags'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.widgetWithText(OutlinedButton, 'All tags'));
      await tester.pumpAndSettle();
      expect(find.text('Filter categories by tag'), findsOneWidget);
      expect(find.text('Boston'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

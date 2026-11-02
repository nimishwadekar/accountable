import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/app_shell.dart';
import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'rebuilding daily tables does not return a Future from setState',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final data = await AssetAppDataRepository().load();
      var rebuildCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: AppShell(
              dataRepository: AssetAppDataRepository(),
              onRebuildDailyTables: () async {
                rebuildCount++;
                return data;
              },
            ),
          ),
        ),
      );
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final navigation = tester.widget<NavigationBar>(
        find.byType(NavigationBar),
      );
      navigation.onDestinationSelected!(4);
      await tester.pump();
      expect(find.text('Derived daily tables'), findsOneWidget);
      await tester.ensureVisible(find.text('Rebuild daily tables'));
      await tester.tap(find.text('Rebuild daily tables'));
      await tester.pump();
      await tester.tap(find.text('Rebuild'));
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(rebuildCount, 1);
      expect(tester.takeException(), isNull);
      expect(find.text('Daily tables rebuilt.'), findsOneWidget);
    },
  );
}

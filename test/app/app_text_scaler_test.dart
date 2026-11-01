import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:accountable/app/app.dart';
import 'package:accountable/app/app_text_scaler.dart';
import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/app/theme/design_tokens.dart';
import 'package:accountable/data/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'app text preference composes with linear and nonlinear system scales',
    () {
      const enlargedSystem = TextScaler.linear(1.3);
      expect(
        const AccountableTextScaler(
          systemScaler: enlargedSystem,
          appScale: 0.75,
        ).scale(16),
        20.8,
        reason: 'A legacy app reduction must not cancel system enlargement.',
      );
      expect(
        const AccountableTextScaler(
          systemScaler: TextScaler.noScaling,
          appScale: 0.75,
        ).scale(16),
        12,
      );
      expect(
        AccountableTextScaler(
          systemScaler: const _NonlinearTextScaler(),
          appScale: 1,
        ).scale(12),
        18,
      );
      expect(
        AccountableTextScaler(
          systemScaler: const _NonlinearTextScaler(),
          appScale: 1,
        ).scale(20),
        24,
      );
      expect(normalizeAppTextScale(double.nan), 1);
      expect(normalizeAppTextScale(double.infinity), 1);
      expect(normalizeAppTextScale(0.5), 0.75);
      expect(normalizeAppTextScale(2), 1.5);
    },
  );

  testWidgets(
    'AccountableApp composes stored preferences with actual platform scales',
    (tester) async {
      // Isolate scaler composition from the app's compact breakpoint/layout.
      await tester.binding.setSurfaceSize(const Size(800, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      const scenarios = [
        (systemScale: 1.0, appScale: 0.75, expectedSize: 10.5),
        (systemScale: 1.3, appScale: 1.0, expectedSize: 18.2),
        (systemScale: 2.0, appScale: 0.75, expectedSize: 28.0),
        (systemScale: 1.0, appScale: 1.5, expectedSize: 21.0),
        (systemScale: 1.3, appScale: 1.5, expectedSize: 27.3),
        (systemScale: 2.0, appScale: 1.5, expectedSize: 42.0),
      ];

      for (final scenario in scenarios) {
        SharedPreferences.setMockInitialValues({
          'text_scale': scenario.appScale,
        });
        tester.platformDispatcher.textScaleFactorTestValue =
            scenario.systemScale;
        await tester.pumpWidget(
          AccountableApp(
            key: ValueKey('${scenario.systemScale}-${scenario.appScale}'),
            dataRepository: AssetAppDataRepository(),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        final pageTitle = find.text('Transactions').first;
        expect(pageTitle, findsOneWidget);
        expect(
          MediaQuery.textScalerOf(tester.element(pageTitle)).scale(14),
          closeTo(scenario.expectedSize, 0.1),
          reason: 'System ${scenario.systemScale}, app ${scenario.appScale}',
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('compact theme uses role-specific heading sizes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Theme(
          data: AppTheme.light().copyWith(
            textTheme: AppTheme.compactTextTheme(AppTheme.light().textTheme),
          ),
          child: const Scaffold(
            body: Text('Compact title', style: TextStyle(fontSize: 24)),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      AppTheme.compactTextTheme(AppTheme.light().textTheme)
          .headlineMedium
          ?.fontSize,
      24,
    );
    expect(
      AppTheme.compactTextTheme(AppTheme.light().textTheme)
          .titleLarge
          ?.fontSize,
      18,
    );
  });

  testWidgets('compact spacing never tightens enlarged text or desktop', (
    tester,
  ) async {
    const scenarios = [
      (size: Size(390, 844), scaler: TextScaler.noScaling, expected: true),
      (size: Size(390, 844), scaler: TextScaler.linear(1.3), expected: false),
      (size: Size(1280, 900), scaler: TextScaler.noScaling, expected: false),
    ];

    for (final scenario in scenarios) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: scenario.size)
                .copyWith(textScaler: scenario.scaler),
            child: Builder(
              builder: (context) => Scaffold(
                body: Text(usesCompactVerticalSpacing(context).toString()),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.text(scenario.expected.toString()),
        findsOneWidget,
        reason: '${scenario.size} with ${scenario.scaler}',
      );
    }
  });
}

class _NonlinearTextScaler extends TextScaler {
  const _NonlinearTextScaler();

  @override
  double scale(double fontSize) =>
      fontSize < 16 ? fontSize * 1.5 : fontSize * 1.2;

  @override
  double get textScaleFactor => 1.2;
}

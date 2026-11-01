import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/pages/settings_page.dart';
import 'package:accountable/app/theme/app_theme.dart';

void main() {
  testWidgets('shows refresh data action', (tester) async {
    var reloaded = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SettingsPage(onReloadData: () async => reloaded = true),
        ),
      ),
    );

    expect(find.text('Refresh data'), findsOneWidget);
    await tester.tap(find.text('Refresh data'));
    await tester.pump();
    expect(reloaded, isTrue);
  });

  testWidgets('text preference supports enlargement and reset', (tester) async {
    double? selectedScale;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SettingsPage(
            textScale: 0.75,
            onReloadData: () async {},
            onTextScaleChanged: (value) => selectedScale = value,
          ),
        ),
      ),
    );
    await tester.pump();

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.min, 0.75);
    expect(slider.max, 1.5);
    expect(find.text('75% app preference'), findsOneWidget);
    expect(
      find.text('System text enlargement is always respected.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Reset to 100%'));
    expect(selectedScale, 1);
  });
}

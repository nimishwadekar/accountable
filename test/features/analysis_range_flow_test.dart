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

  testWidgets('updates both chart ranges when a range is selected', (
    tester,
  ) async {
    final data = await AssetAppDataRepository().load();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: AnalysisPage(data: data)),
      ),
    );
    await tester.pump();

    expect(find.text('1M'), findsNWidgets(2));
    await tester.tap(find.text('3M').first);
    await tester.pump();
    expect(find.text('3M'), findsNWidgets(2));
  });
}

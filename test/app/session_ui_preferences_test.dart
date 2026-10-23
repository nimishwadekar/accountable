import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:accountable/app/session_ui_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();

  test('starts a clean in-memory session and persists the current selections',
      () async {
    final preferences = SessionUiPreferences.instance
      ..analysisAccountId = 'account'
      ..analysisMonth = '2026-10-01T00:00:00.000Z'
      ..transactionTagId = 'tag';

    await preferences.persist();
    await preferences.startSession();

    expect(preferences.analysisAccountId, isNull);
    expect(preferences.analysisMonth, isNull);
    expect(preferences.transactionTagId, isNull);
  });
}

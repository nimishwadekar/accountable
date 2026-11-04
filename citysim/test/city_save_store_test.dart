import 'dart:convert';

import 'package:citysim/data/city_save_store.dart';
import 'package:citysim/domain/city_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'uses its own key and reset leaves unrelated local data untouched',
    () async {
      SharedPreferences.setMockInitialValues({'accountable.settings': 'keep'});
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesCitySaveStore(preferences: preferences);
      final city = CityState(
        calendarDate: DateTime.utc(2026, 11, 2),
        simulationSeconds: 15,
        coins: 2,
        totalCoinsEarned: 2,
        totalCoinsSpent: 0,
        nextConstructionNumber: 1,
        creditedDates: {'2026-11-02'},
        unlockedDistrictIds: {'village'},
        buildings: const [],
        constructions: const [],
        events: const [],
      );

      await store.save(city);
      expect((await store.load())?.toJson(), city.toJson());
      expect(preferences.getString('accountable.settings'), 'keep');
      expect(
        jsonDecode(
          preferences.getString(SharedPreferencesCitySaveStore.storageKey)!,
        ),
        isA<Map<String, dynamic>>(),
      );

      await store.clear();
      expect(await store.load(), isNull);
      expect(preferences.getString('accountable.settings'), 'keep');
    },
  );

  test('invalid save is surfaced instead of silently replaced', () async {
    SharedPreferences.setMockInitialValues({
      SharedPreferencesCitySaveStore.storageKey: '{not json',
    });
    final preferences = await SharedPreferences.getInstance();
    final store = SharedPreferencesCitySaveStore(preferences: preferences);

    expect(store.load(), throwsFormatException);
    expect(
      preferences.getString(SharedPreferencesCitySaveStore.storageKey),
      '{not json',
    );
  });
}

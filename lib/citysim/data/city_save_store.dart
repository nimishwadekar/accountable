import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../content/city_content.dart';
import '../domain/city_state.dart';

abstract interface class CitySaveStore {
  Future<CityState?> load();
  Future<void> save(CityState state);
  Future<void> clear();
}

/// A namespaced local save, deliberately separate from Accountable keys.
class SharedPreferencesCitySaveStore implements CitySaveStore {
  SharedPreferencesCitySaveStore({this.preferences});

  static const storageKey = 'citysim.prototype.v1';

  final SharedPreferences? preferences;

  Future<SharedPreferences> get _store async =>
      preferences ?? SharedPreferences.getInstance();

  @override
  Future<CityState?> load() async {
    final raw = (await _store).getString(storageKey);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('The saved city data is not an object.');
    }
    final state = CityState.fromJson(
      decoded.map((key, value) => MapEntry(key as String, value)),
    );
    validateCityContentState(state);
    return state;
  }

  @override
  Future<void> save(CityState state) async {
    final saved = await (await _store).setString(
      storageKey,
      jsonEncode(state.toJson()),
    );
    if (!saved) {
      throw StateError('The browser did not confirm saving the city.');
    }
  }

  @override
  Future<void> clear() async {
    final removed = await (await _store).remove(storageKey);
    if (!removed) {
      throw StateError('The browser did not confirm resetting the city save.');
    }
  }
}

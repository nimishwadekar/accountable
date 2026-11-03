import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'terrain_provider.dart';
import 'world_rules.dart';
import 'world_state.dart';

abstract interface class ParcelWorldStore {
  Future<ParcelWorldState?> load();
  Future<void> save(ParcelWorldState state);
  Future<bool> hasLegacyV1Save();
}

class SharedPreferencesParcelWorldStore implements ParcelWorldStore {
  SharedPreferencesParcelWorldStore({
    required this.terrainProvider,
    this.preferences,
  });

  static const storageKey = 'citysim.parcel-world.v2';
  static const legacyV1StorageKey = 'citysim.prototype.v1';

  final TerrainProvider terrainProvider;
  final SharedPreferences? preferences;

  Future<SharedPreferences> get _store async =>
      preferences ?? SharedPreferences.getInstance();

  @override
  Future<ParcelWorldState?> load() async {
    final raw = (await _store).getString(storageKey);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('The parcel-world save is not an object.');
    }
    final state = ParcelWorldState.fromJson(
      decoded.map((key, value) => MapEntry(key as String, value)),
    );
    validateParcelWorldState(state, terrainProvider);
    return state;
  }

  @override
  Future<void> save(ParcelWorldState state) async {
    validateParcelWorldState(state, terrainProvider);
    final saved = await (await _store).setString(
      storageKey,
      jsonEncode(state.toJson()),
    );
    if (!saved) {
      throw StateError('The browser did not confirm saving the parcel world.');
    }
  }

  @override
  Future<bool> hasLegacyV1Save() async =>
      (await _store).containsKey(legacyV1StorageKey);
}

/// Serializes persistence and makes reset/scenario replacement win over stale
/// queued snapshots. It only ever writes the parcel-world V2 key.
class ParcelWorldSaveCoordinator {
  ParcelWorldSaveCoordinator(this.store);

  final ParcelWorldStore store;
  Future<void> _tail = Future<void>.value();
  int _generation = 0;

  Future<void> save(ParcelWorldState state) {
    final generation = _generation;
    _tail = _tail.catchError((Object _) {}).then((_) async {
      if (generation == _generation) await store.save(state);
    });
    return _tail;
  }

  Future<void> replace(ParcelWorldState state) {
    _generation++;
    final generation = _generation;
    _tail = _tail.catchError((Object _) {}).then((_) async {
      if (generation == _generation) await store.save(state);
    });
    return _tail;
  }

  Future<void> flush() => _tail;
}

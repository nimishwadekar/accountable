import '../storage/sheet_tables.dart';
import 'world_state.dart';

/// The loaded save: every city's decoded, reconciled, and validated
/// state, plus the raw tables the session splices saves through.
/// Cities are independent games — the directory is all the session
/// knows beyond the city it is playing.
class LoadedCitySave {
  const LoadedCitySave({required this.tables, required this.states});

  final MultiCityTables tables;
  final Map<String, ParcelWorldState> states;

  /// The lowest city id present — the city the game plays until
  /// switching gameplay exists (decided 2026-11-16).
  String get activeCityId =>
      states.keys.reduce((a, b) => cityIdNumber(a) <= cityIdNumber(b) ? a : b);

  ParcelWorldState get activeCity => states[activeCityId]!;
}

/// Persistence boundary for the parcel world. Implementations load
/// the whole city directory and save one city at a time; the sheet
/// codec and its stores live in `lib/storage/`.
abstract interface class ParcelWorldStore {
  /// Returns null when no save exists yet (a fresh world found its
  /// first city); throws visibly on structurally invalid documents.
  Future<LoadedCitySave?> load();

  /// Validates [state], splices it into [tables] as [cityId]'s block,
  /// and writes the whole save through.
  Future<void> saveCity(
    MultiCityTables tables,
    String cityId,
    ParcelWorldState state,
  );
}

/// Serializes persistence and makes reset/scenario replacement win over
/// stale queued snapshots.
class ParcelWorldSaveCoordinator {
  ParcelWorldSaveCoordinator(this.store);

  final ParcelWorldStore store;
  Future<void> _tail = Future<void>.value();
  int _generation = 0;

  Future<void> save(
    MultiCityTables tables,
    String cityId,
    ParcelWorldState state,
  ) {
    final generation = _generation;
    _tail = _tail.catchError((Object _) {}).then((_) async {
      if (generation == _generation) {
        await store.saveCity(tables, cityId, state);
      }
    });
    return _tail;
  }

  Future<void> replace(
    MultiCityTables tables,
    String cityId,
    ParcelWorldState state,
  ) {
    _generation++;
    final generation = _generation;
    _tail = _tail.catchError((Object _) {}).then((_) async {
      if (generation == _generation) {
        await store.saveCity(tables, cityId, state);
      }
    });
    return _tail;
  }

  Future<void> flush() => _tail;
}

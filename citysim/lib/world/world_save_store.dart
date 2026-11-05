import 'world_state.dart';

/// Persistence boundary for the parcel world. Implementations load and
/// save the whole world; the sheet codec and its stores live in
/// `lib/storage/`.
abstract interface class ParcelWorldStore {
  Future<ParcelWorldState?> load();
  Future<void> save(ParcelWorldState state);
}

/// Serializes persistence and makes reset/scenario replacement win over
/// stale queued snapshots.
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

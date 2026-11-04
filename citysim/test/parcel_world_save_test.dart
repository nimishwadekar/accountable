import 'package:citysim/world/terrain_provider.dart';
import 'package:citysim/world/world_save_store.dart';
import 'package:citysim/world/world_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryWorldStore implements ParcelWorldStore {
  _MemoryWorldStore();

  ParcelWorldState? current;
  final writes = <ParcelWorldState>[];

  @override
  Future<bool> hasLegacyV1Save() async => false;

  @override
  Future<ParcelWorldState?> load() async => current;

  @override
  Future<void> save(ParcelWorldState state) async {
    writes.add(state);
    current = state;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const terrain = DemoTerrainProvider();

  test('V2 uses its own key and leaves a V1 city save untouched', () async {
    SharedPreferences.setMockInitialValues({
      SharedPreferencesParcelWorldStore.legacyV1StorageKey: 'legacy-snapshot',
      'accountable.settings': 'untouched',
    });
    final preferences = await SharedPreferences.getInstance();
    final store = SharedPreferencesParcelWorldStore(
      terrainProvider: terrain,
      preferences: preferences,
    );

    expect(await store.load(), isNull);
    expect(await store.hasLegacyV1Save(), isTrue);
    final world = newParcelWorldState(
      seed: 9,
      terrainProvider: terrain,
      today: DateTime.utc(2026, 11, 2),
    );
    await store.save(world);

    expect((await store.load())?.toJson(), world.toJson());
    expect(
      preferences.getString(
        SharedPreferencesParcelWorldStore.legacyV1StorageKey,
      ),
      'legacy-snapshot',
    );
    expect(preferences.getString('accountable.settings'), 'untouched');
  });

  test(
    'save coordinator ignores queued stale snapshots during replacement',
    () async {
      final store = _MemoryWorldStore();
      final coordinator = ParcelWorldSaveCoordinator(store);
      final oldWorld = newParcelWorldState(
        seed: 1,
        terrainProvider: terrain,
        today: DateTime.utc(2026, 11, 2),
      );
      final newWorld = newParcelWorldState(
        seed: 2,
        terrainProvider: terrain,
        today: DateTime.utc(2026, 11, 3),
      );

      final oldWrite = coordinator.save(oldWorld);
      final replaceWrite = coordinator.replace(newWorld);
      await Future.wait([oldWrite, replaceWrite]);

      expect(store.current?.seed, 2);
      expect(store.writes, [newWorld]);
    },
  );

  test(
    'invalid content is surfaced and does not become a fresh silent save',
    () async {
      SharedPreferences.setMockInitialValues({
        SharedPreferencesParcelWorldStore.storageKey: '{bad json',
      });
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesParcelWorldStore(
        terrainProvider: terrain,
        preferences: preferences,
      );

      expect(store.load(), throwsFormatException);
      expect(
        preferences.getString(SharedPreferencesParcelWorldStore.storageKey),
        '{bad json',
      );
    },
  );
}

import 'package:citysim/content/asset_content_source.dart';
import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/storage/server_sheet_store.dart';
import 'package:citysim/storage/sheet_tables.dart';
import 'package:citysim/storage/world_sheet_codec.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:citysim/world/terrain_provider.dart';
import 'package:citysim/world/world_reducer.dart';
import 'package:citysim/world/world_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// An in-memory documents transport — the test double for the HTTP API.
class _FakeDocumentsApi implements WorldDocumentsApi {
  Map<String, String>? documents;
  Object? fetchError;

  @override
  Future<Map<String, String>?> fetchDocuments() async {
    if (fetchError != null) throw fetchError!;
    return documents;
  }

  @override
  Future<void> putDocuments(Map<String, String> documents) async {
    this.documents = {...documents};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ContentBundle content;
  late ContentTerrainProvider terrain;

  setUpAll(() async {
    content = await loadContentBundle(const AssetContentSource());
    terrain = ContentTerrainProvider(content.terrain);
  });

  ParcelWorldState newWorld() => newParcelWorldState(
    content: content,
    seed: 99,
    terrainProvider: terrain,
    today: DateTime.utc(2026, 11, 2),
  );

  test('the store round-trips a played world through its documents', () async {
    final api = _FakeDocumentsApi();
    final store = ServerSheetParcelWorldStore(
      content: content,
      terrainProvider: terrain,
      api: api,
    );

    // Play: check in, expand, build a partially funded road, then save
    // and reload mid-project.
    var world = grantWorldDebugCoins(checkInWorldForToday(newWorld()), 100);
    world = purchaseAdjacentParcel(
      world,
      content,
      terrain,
      const ParcelCoord(1, 0),
    );
    world = planRoadStretch(
      world,
      content,
      terrain,
      cells: [for (var column = 5; column <= 7; column++) CellCoord(column, 4)],
      style: RoadStyle.asphalt,
    );
    final roadProject = world.constructions.single;
    for (var column = 5; column <= 6; column++) {
      world = fundRoadTile(
        world,
        content,
        terrain,
        projectId: roadProject.id,
        cell: CellCoord(column, 4),
      );
    }

    final reloaded = await store.load();
    expect(reloaded, isNull, reason: 'no documents yet');
    await store.save(world);
    final midProject = (await store.load())!;
    expect(midProject.constructions.single.roadCells, hasLength(3));
    expect(midProject.constructions.single.coinsFunded, 2);
    expect(midProject.coins, world.coins);
    expect(midProject.checkInCount, 1);
    expect(midProject.lastCheckInDate, DateTime.utc(2026, 11, 2));

    // Continue playing on the reloaded world: finish the road, build a
    // cottage, bridge the east channel, and start a café.
    var played = midProject;
    played = fundRoadTile(
      played,
      content,
      terrain,
      projectId: played.constructions.single.id,
      cell: const CellCoord(7, 4),
    );
    played = startStructureConstruction(
      played,
      content,
      terrain,
      catalogueId: 'small-home',
      origin: const CellCoord(3, 4),
    );
    played = fundStructureProject(
      played,
      content,
      projectId: played.constructions.single.id,
      amount: played.constructions.single.totalCostCoins,
    );
    played = startBridgeConstruction(
      played,
      content,
      terrain,
      nearBank: const CellCoord(7, 4),
      farBank: const CellCoord(16, 4),
    );
    played = fundBridgeProject(
      played,
      projectId: played.constructions.single.id,
      amount: played.constructions.single.totalCostCoins,
    );
    played = startStructureConstruction(
      played,
      content,
      terrain,
      catalogueId: 'cafe',
      origin: const CellCoord(6, 5),
    );

    await store.save(played);
    final finalWorld = (await store.load())!;
    expect(finalWorld.roads, hasLength(5), reason: 'starter + 3 + approach');
    expect(finalWorld.structures.single.catalogueId, 'small-home');
    expect(finalWorld.bridges.single.nearBank, const CellCoord(7, 4));
    expect(finalWorld.bridges.single.farBank, const CellCoord(16, 4));
    expect(finalWorld.constructions.single.catalogueId, 'cafe');

    // Saving the reloaded world produces the same documents again.
    expect(
      encodeSheetTables(worldToSheetTables(finalWorld)),
      encodeSheetTables(worldToSheetTables(played)),
    );
  });

  test('empty documents mean a brand-new game', () async {
    final store = ServerSheetParcelWorldStore(
      content: content,
      terrainProvider: terrain,
      api: _FakeDocumentsApi()..documents = const {},
    );
    expect(await store.load(), isNull);
  });

  test('a fetch failure explains how to start the server', () async {
    final store = ServerSheetParcelWorldStore(
      content: content,
      terrainProvider: terrain,
      api: _FakeDocumentsApi()..fetchError = Exception('Connection refused'),
    );
    await expectLater(
      store.load(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('run_game'),
        ),
      ),
    );
  });
}

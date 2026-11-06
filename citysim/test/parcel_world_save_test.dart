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
    world = purchaseAdjacentParcel(
      world,
      content,
      terrain,
      const ParcelCoord(2, 0),
    );
    world = planRoadStretch(
      world,
      content,
      terrain,
      cells: [for (var column = 5; column <= 6; column++) CellCoord(column, 4)],
    );
    final roadProject = world.constructions.single;
    world = fundRoadProject(world, content, terrain, projectId: roadProject.id);

    final reloaded = await store.load();
    expect(reloaded, isNull, reason: 'no documents yet');
    await store.save(world);
    final midProject = (await store.load())!;
    expect(midProject.constructions.single.roadCells, hasLength(2));
    expect(midProject.constructions.single.coinsFunded, 1);
    expect(midProject.coins, world.coins);
    expect(midProject.checkInCount, 1);
    expect(midProject.lastCheckInDate, DateTime.utc(2026, 11, 2));

    // Continue playing on the reloaded world: finish the road, build a
    // cottage, bridge the east channel, and start a café.
    var played = midProject;
    played = fundRoadProject(
      played,
      content,
      terrain,
      projectId: played.constructions.single.id,
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
    // The bridge spans the east channel from vacant banks: the road
    // stops at (7,4) so both bridge banks are free land.
    played = startBridgeConstruction(
      played,
      content,
      terrain,
      nearBank: const CellCoord(7, 4),
      farBank: const CellCoord(16, 4),
    );
    played = fundBridgeProject(
      played,
      content,
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

  test('finished road projects release their tile references', () async {
    final api = _FakeDocumentsApi();
    final store = ServerSheetParcelWorldStore(
      content: content,
      terrainProvider: terrain,
      api: api,
    );

    // Finish a road stretch east of the starter road.
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
    );
    final finishedId = world.constructions.single.id;
    for (var column = 5; column <= 7; column++) {
      world = fundRoadProject(world, content, terrain, projectId: finishedId);
    }
    expect(world.constructions, isEmpty);
    expect(
      world.roads.where((road) => road.projectId == finishedId),
      isEmpty,
      reason: 'finished roads no longer name their project',
    );

    await store.save(world);
    final saved = decodeSheetTables(
      userData: api.documents![userDataSheetName] ?? '',
      tiles: api.documents![tilesSheetName] ?? '',
      ownedParcels: api.documents![ownedParcelsSheetName] ?? '',
      projects: api.documents![projectsSheetName] ?? '',
    );
    expect(
      saved.tiles.where((row) => row[2] == 'road' && row[7].isNotEmpty),
      isEmpty,
      reason: 'no completed road keeps a project reference',
    );

    // Reloading with no active projects restarts numbering, so the next
    // stretch reuses the finished project's id. The two must not
    // collide: the reload has to rebuild the new project from its own
    // tiles only.
    final reloaded = (await store.load())!;
    expect(reloaded.nextEntityNumber, 1);
    var played = planRoadStretch(
      reloaded,
      content,
      terrain,
      cells: [const CellCoord(4, 5), const CellCoord(4, 6)],
    );
    expect(played.constructions.single.id, finishedId);
    played = fundRoadProject(
      played,
      content,
      terrain,
      projectId: played.constructions.single.id,
    );

    await store.save(played);
    final second = (await store.load())!;
    expect(second.constructions.single.roadCells, hasLength(2));
    expect(second.constructions.single.coinsFunded, 1);
    expect(second.roads, hasLength(5), reason: 'starter + 3 + 1 funded tile');
  });
}

import 'package:citysim/content/asset_content_source.dart';
import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/storage/csv_sheet_store.dart';
import 'package:citysim/storage/sheet_tables.dart';
import 'package:citysim/storage/world_sheet_codec.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:citysim/world/terrain_provider.dart';
import 'package:citysim/world/world_reducer.dart';
import 'package:citysim/world/world_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A sheet source backed by in-memory documents — the test analogue of
/// the bundled CSV sheets.
class _HardcodedSheetSource implements SheetSource {
  _HardcodedSheetSource(this.documents);

  final Map<String, String> documents;

  @override
  Future<String?> readSheet(String name) async => documents[name];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const terrain = DemoTerrainProvider();
  late ContentBundle content;

  setUpAll(() async {
    content = await loadContentBundle(const AssetContentSource());
  });

  ParcelWorldState newWorld() => newParcelWorldState(
    content: content,
    seed: 99,
    terrainProvider: terrain,
    today: DateTime.utc(2026, 11, 2),
  );

  test('the store round-trips a played world through its sheets', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = CsvSheetParcelWorldStore(
      content: content,
      terrainProvider: terrain,
      preferences: preferences,
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
      cells: [
        for (var column = 5; column <= 11; column++) CellCoord(column, 4),
      ],
      style: RoadStyle.asphalt,
    );
    final roadProject = world.constructions.single;
    for (var column = 5; column <= 9; column++) {
      world = fundRoadTile(
        world,
        content,
        terrain,
        projectId: roadProject.id,
        cell: CellCoord(column, 4),
      );
    }

    final reloaded = await store.load();
    expect(reloaded, isNull, reason: 'nothing saved yet');
    await store.save(world);
    final midProject = (await store.load())!;
    expect(midProject.constructions, hasLength(1));
    expect(midProject.constructions.single.roadCells, hasLength(7));
    expect(midProject.constructions.single.coinsFunded, 5);
    expect(midProject.coins, world.coins);
    expect(midProject.checkInCount, 1);
    expect(midProject.lastCheckInDate, DateTime.utc(2026, 11, 2));

    // Continue playing on the reloaded world: finish the road, build a
    // cottage, bridge the river, and start a café.
    var played = midProject;
    for (var column = 10; column <= 11; column++) {
      played = fundRoadTile(
        played,
        content,
        terrain,
        projectId: played.constructions.single.id,
        cell: CellCoord(column, 4),
      );
    }
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
    played = startRiverBridgeConstruction(
      played,
      content,
      terrain,
      nearBank: const CellCoord(11, 4),
      farBank: const CellCoord(13, 4),
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
    expect(finalWorld.roads, hasLength(9), reason: 'starter + 7 + approach');
    expect(finalWorld.structures, hasLength(1));
    expect(finalWorld.structures.single.catalogueId, 'small-home');
    expect(finalWorld.bridges.single.nearBank, const CellCoord(11, 4));
    expect(finalWorld.bridges.single.farBank, const CellCoord(13, 4));
    expect(finalWorld.constructions.single.catalogueId, 'cafe');
    expect(finalWorld.checkInCount, 1);

    // Saving the reloaded world produces the same documents again.
    expect(
      encodeSheetTables(worldToSheetTables(finalWorld)),
      encodeSheetTables(worldToSheetTables(played)),
    );
  });

  test('a bundled seed loads when nothing is saved locally', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final seeded = checkInWorldForToday(newWorld());
    final documents = encodeSheetTables(worldToSheetTables(seeded));
    final store = CsvSheetParcelWorldStore(
      content: content,
      terrainProvider: terrain,
      preferences: preferences,
      seedSource: _HardcodedSheetSource(documents),
    );

    final world = await store.load();
    expect(world, isNotNull, reason: 'the seed provides a world');
    expect(world!.coins, seeded.coins);
    expect(world.checkInCount, 1);
  });

  test('an empty seed means a brand-new game', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = CsvSheetParcelWorldStore(
      content: content,
      terrainProvider: terrain,
      preferences: preferences,
      seedSource: _HardcodedSheetSource(const {}),
    );

    expect(await store.load(), isNull);
  });

  test('a local save wins over the bundled seed', () async {
    final seeded = checkInWorldForToday(newWorld());
    final local = newWorld();
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = CsvSheetParcelWorldStore(
      content: content,
      terrainProvider: terrain,
      preferences: preferences,
      seedSource: _HardcodedSheetSource(
        encodeSheetTables(worldToSheetTables(seeded)),
      ),
    );
    await store.save(local);

    final world = await store.load();
    expect(world!.seed, local.seed, reason: 'the local sheet set wins');
  });

  test('corrupt sheet documents fail loudly on load', () async {
    SharedPreferences.setMockInitialValues({
      'citysim.sheets.Tiles':
          'x,y,kind,status,detail,variant,facing,project\n'
          '4,4,alien,complete,,,,\n',
      'citysim.sheets.UserData': 'key,value\nseed,7\n',
    });
    final preferences = await SharedPreferences.getInstance();
    final store = CsvSheetParcelWorldStore(
      content: content,
      terrainProvider: terrain,
      preferences: preferences,
    );

    expect(store.load(), throwsA(isA<FormatException>()));
  });
}

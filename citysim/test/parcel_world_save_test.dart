import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/storage/server_sheet_store.dart';
import 'package:citysim/storage/sheet_tables.dart';
import 'package:citysim/storage/world_sheet_codec.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:citysim/world/terrain_provider.dart';
import 'package:citysim/world/world_reducer.dart';
import 'package:citysim/world/world_rules.dart';
import 'package:citysim/world/world_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'frozen_content.dart';

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

  setUpAll(() {
    content = frozenContent();
    terrain = ContentTerrainProvider(content.terrain);
  });

  ParcelWorldState newWorld() => newParcelWorldState(
    content: content,
    seed: 99,
    today: DateTime.utc(2026, 11, 2),
  );

  /// A one-city save around a state — the shape the app's fresh-world
  /// path writes.
  MultiCityTables citySave(ParcelWorldState world) => MultiCityTables(
    cities: [CityRecord(id: 'city_1', name: 'City 1', founded: world.dateKey)],
    tablesById: {'city_1': worldToSheetTables(world)},
  );

  Future<void> save(
    ServerSheetParcelWorldStore store,
    ParcelWorldState world,
  ) => store.saveCity(citySave(world), 'city_1', world);

  /// The heartbeat: a day passes and the town report runs.
  ParcelWorldState nextDay(ParcelWorldState world) =>
      checkInWorldForToday(advanceWorldDays(world, 1), content);

  test('the store round-trips a played world through its documents', () async {
    final api = _FakeDocumentsApi();
    final store = ServerSheetParcelWorldStore(
      content: content,
      terrainProvider: terrain,
      api: api,
    );

    // Play: check in, found, expand, buy a road plan (in flight,
    // nothing delivered), then save and reload mid-project.
    var world = grantWorldDebugCoins(
      checkInWorldForToday(newWorld(), content),
      500000,
    );
    world = foundCity(
      world,
      content,
      terrain,
      origin: const CellCoord(3, 1),
      facing: 'south',
    );
    world = purchaseParcel(world, content, terrain, const ParcelCoord(1, 0));
    world = purchaseParcel(world, content, terrain, const ParcelCoord(2, 0));
    world = planRoadStretch(
      world,
      content,
      terrain,
      cells: [for (var column = 5; column <= 6; column++) CellCoord(column, 4)],
    );

    final reloaded = await store.load();
    expect(reloaded, isNull, reason: 'no documents yet');
    await save(store, world);
    final midProject = (await store.load())!.activeCity;
    final midRoad = midProject.constructions.lastWhere(
      (job) => job.kind == WorldConstructionKind.road,
    );
    expect(midRoad.roadCells, hasLength(2));
    expect(
      midProject.roads.where((road) => road.projectId == midRoad.id),
      isEmpty,
      reason: 'nothing delivered — the plan waits for its check-in',
    );
    expect(midProject.coins, world.coins);
    expect(midProject.checkInCount, 1, reason: 'the founding check-in');
    expect(midProject.lastCheckInDate, DateTime.utc(2026, 11, 2));

    // Continue playing on the reloaded world: the road lands whole,
    // then build a cottage, bridge the east channel, and start a
    // café.
    var played = midProject;
    played = nextDay(played);
    expect(
      played.roads.where(
        (road) =>
            road.cell == const CellCoord(4, 4) ||
            road.cell == const CellCoord(5, 4) ||
            road.cell == const CellCoord(6, 4),
      ),
      isNotEmpty,
      reason: 'the whole stretch landed on its first check-in',
    );
    played = startStructureConstruction(
      played,
      content,
      terrain,
      catalogueId: 'small-home',
      origin: const CellCoord(3, 4),
    );
    played = nextDay(played);
    played = nextDay(played);
    // The bridge spans the east channel from vacant banks: the road
    // stops before the near bank so both bridge banks are free land
    // (the founding road at (4,4) plus three landed tiles).
    played = startBridgeConstruction(
      played,
      content,
      terrain,
      nearBank: const CellCoord(7, 4),
      farBank: const CellCoord(16, 4),
    );
    while (played.constructions.any(
      (job) => job.kind == WorldConstructionKind.bridge,
    )) {
      played = nextDay(played);
    }
    played = startStructureConstruction(
      played,
      content,
      terrain,
      catalogueId: 'cafe',
      origin: const CellCoord(5, 5),
    );

    await save(store, played);
    final finalWorld = (await store.load())!.activeCity;
    expect(
      finalWorld.roads,
      hasLength(5),
      reason: 'founding road + 2 planned + 2 bridge banks',
    );
    expect(
      finalWorld.structures
          .lastWhere((structure) => structure.catalogueId == 'small-home')
          .catalogueId,
      'small-home',
    );
    expect(finalWorld.bridges.single.nearBank, const CellCoord(7, 4));
    expect(finalWorld.bridges.single.farBank, const CellCoord(16, 4));
    expect(finalWorld.constructions.single.catalogueId, 'cafe');

    // Saving the reloaded world produces the same documents again.
    expect(
      encodeMultiCityTables(citySave(finalWorld)),
      encodeMultiCityTables(citySave(played)),
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

    // Finish a road stretch east of the founding road. The settled
    // start is codec-assembled (hall complete, front road at (4,4))
    // so the road plan is the town's first project — the numbering
    // story this test tells.
    var world = sheetTablesToWorld(
      SheetTables(
        userData: {
          'seed': '99',
          'coins': '60000',
          'coins_earned': '60000',
          'coins_spent': '0',
          'simulated_date': '2026-11-02',
          'high_water_date': '2026-11-02',
          'construction_day': '1',
        },
        ownedParcels: const [
          ['0', '0'],
          ['1', '0'],
        ],
        tiles: const [
          ['4', '4', 'road', 'complete', 'asphalt', '', '', ''],
          [
            '3',
            '1',
            'structure',
            'complete',
            'city-hall',
            'city-hall',
            'south',
            '',
          ],
        ],
        projects: const [],
      ),
      content: content,
      terrainProvider: terrain,
    );
    world = planRoadStretch(
      world,
      content,
      terrain,
      cells: [for (var column = 5; column <= 7; column++) CellCoord(column, 4)],
    );
    final finishedId = world.constructions.single.id;
    // One check-in lands the whole stretch, whatever its length.
    world = nextDay(world);
    expect(world.constructions, isEmpty);
    expect(
      world.roads.where((road) => road.projectId == finishedId),
      isEmpty,
      reason: 'finished roads no longer name their project',
    );

    await save(store, world);
    final saved = decodeMultiCityTables(
      cities: api.documents![citiesSheetName] ?? '',
      userData: api.documents![userDataSheetName] ?? '',
      tiles: api.documents![tilesSheetName] ?? '',
      ownedParcels: api.documents![ownedParcelsSheetName] ?? '',
      projects: api.documents![projectsSheetName] ?? '',
    ).tablesById['city_1']!;
    expect(
      saved.tiles.where((row) => row[2] == 'road' && row[7].isNotEmpty),
      isEmpty,
      reason: 'no completed road keeps a project reference',
    );

    // Reloading with no active projects restarts numbering, so the next
    // stretch reuses the finished project's id. The two must not
    // collide: the reload has to rebuild the new project from its own
    // tiles only.
    final reloaded = (await store.load())!.activeCity;
    expect(reloaded.nextEntityNumber, 1);
    var played = planRoadStretch(
      reloaded,
      content,
      terrain,
      cells: [const CellCoord(4, 5), const CellCoord(4, 6)],
    );
    expect(played.constructions.single.id, finishedId);

    // Save the stretch in flight and reload: the reused id must
    // rebuild the project from its own planned tiles only.
    await save(store, played);
    final second = (await store.load())!.activeCity;
    expect(
      second.constructions.single.roadCells,
      hasLength(2),
      reason: 'the reused id rebuilds from its own planned tiles',
    );
    expect(
      second.roads.where(
        (road) => road.projectId == second.constructions.single.id,
      ),
      isEmpty,
      reason: 'nothing delivered — the plan waits for its check-in',
    );
    expect(
      second.roads,
      hasLength(4),
      reason:
          '4 finished (founding road plus three); the new plan is '
          'still undelivered',
    );
  });

  test('saving one city splices only its block', () async {
    final api = _FakeDocumentsApi();
    final store = ServerSheetParcelWorldStore(
      content: content,
      terrainProvider: terrain,
      api: api,
    );

    // Two cities: city_1 founded and expanded; city_2 fresh, not yet
    // founded (a valid save state — founding is gameplay, not
    // storage).
    var first = grantWorldDebugCoins(
      checkInWorldForToday(newWorld(), content),
      100,
    );
    first = foundCity(
      first,
      content,
      terrain,
      origin: const CellCoord(3, 1),
      facing: 'south',
    );
    final second = newWorld();
    final tables = MultiCityTables(
      cities: [
        CityRecord(id: 'city_1', name: 'Alpha', founded: first.dateKey),
        CityRecord(id: 'city_2', name: 'Beta', founded: second.dateKey),
      ],
      tablesById: {
        'city_1': worldToSheetTables(first),
        'city_2': worldToSheetTables(second),
      },
    );
    await store.saveCity(tables, 'city_2', second);

    final loaded = (await store.load())!;
    expect(loaded.states.keys, {'city_1', 'city_2'});
    expect(loaded.activeCityId, 'city_1', reason: 'the lowest id plays');
    expect(
      loaded.states['city_1']!.parcels.single.coord,
      const ParcelCoord(0, 0),
    );
    expect(loaded.states['city_2']!.parcels, isEmpty);

    // Saving city_1 leaves city_2's block untouched — cities are
    // independent games.
    var played = loaded.states['city_1']!;
    played = purchaseParcel(played, content, terrain, const ParcelCoord(1, 0));
    await store.saveCity(loaded.tables, 'city_1', played);
    final reloaded = (await store.load())!;
    expect(reloaded.states['city_1']!.parcels, hasLength(2));
    expect(reloaded.states['city_2']!.parcels, isEmpty);

    // And city_2 cannot take what city_1 now holds: the claim set is
    // every other city's parcels.
    final claimed = {
      for (final parcel in reloaded.states['city_1']!.parcels) parcel.coord,
    };
    expect(
      () => purchaseParcel(
        reloaded.states['city_2']!,
        content,
        terrain,
        const ParcelCoord(1, 0),
        claimedParcels: claimed,
      ),
      throwsA(
        isA<WorldRuleViolation>().having(
          (error) => error.message,
          'message',
          contains('Another city has claimed'),
        ),
      ),
    );
  });
}

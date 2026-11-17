import 'package:citysim/content/asset_content_source.dart';
import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/storage/sheet_tables.dart';
import 'package:citysim/storage/world_sheet_codec.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:citysim/world/terrain_provider.dart';
import 'package:citysim/world/world_reducer.dart';
import 'package:citysim/world/world_rules.dart';
import 'package:citysim/world/world_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// The three demand relaxations, pinned end to end: any build order
/// converges, tolerance keeps the founding list alive, and surplus
/// jobs pull migration.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ContentBundle content;
  late ContentTerrainProvider terrain;
  setUpAll(() async {
    content = await loadContentBundle(const AssetContentSource());
    terrain = ContentTerrainProvider(content.terrain);
  });

  ParcelWorldState fresh() {
    // The settled start: parcel (0,0) owned with one road tile at
    // its centre, assembled directly through the save codec so no
    // coins, days, or events are spent reaching it.
    final world = sheetTablesToWorld(
      SheetTables(
        userData: {
          'seed': '123456',
          'coins': '${content.economy.startingTreasuryCoins}',
          'coins_earned': '${content.economy.startingTreasuryCoins}',
          'coins_spent': '0',
          'simulated_date': '2026-11-02',
          'high_water_date': '2026-11-02',
          'construction_day': '0',
        },
        ownedParcels: const [
          ['0', '0'],
        ],
        tiles: const [
          ['4', '4', 'road', 'complete', 'asphalt', '', '', ''],
        ],
        projects: const [],
      ),
      content: content,
      terrainProvider: terrain,
    );
    return world.copyWith(
      unlockedCatalogueIds: {...world.unlockedCatalogueIds, 'fruit-market'},
    );
  }

  ParcelWorldState nextDay(ParcelWorldState world) =>
      checkInWorldForToday(advanceWorldDays(world, 1), content);

  test('every build order converges: the strand is dead', () {
    // Order A: home, shop, home.
    var a = fresh();
    a = startStructureConstruction(
      a,
      content,
      terrain,
      catalogueId: 'small-home',
      origin: const CellCoord(3, 4),
    );
    a = nextDay(a);
    a = nextDay(a);
    a = startStructureConstruction(
      a,
      content,
      terrain,
      catalogueId: 'fruit-market',
      origin: const CellCoord(4, 3),
    );
    a = nextDay(a);
    a = nextDay(a);
    a = startStructureConstruction(
      a,
      content,
      terrain,
      catalogueId: 'small-home',
      origin: const CellCoord(5, 4),
    );
    a = nextDay(a);
    a = nextDay(a);
    a = nextDay(a);

    // Order B: home, home, shop — the order that used to brick.
    var b = fresh();
    b = startStructureConstruction(
      b,
      content,
      terrain,
      catalogueId: 'small-home',
      origin: const CellCoord(3, 4),
    );
    b = nextDay(b);
    b = nextDay(b);
    b = startStructureConstruction(
      b,
      content,
      terrain,
      catalogueId: 'small-home',
      origin: const CellCoord(5, 4),
    );
    b = nextDay(b);
    b = nextDay(b);
    b = startStructureConstruction(
      b,
      content,
      terrain,
      catalogueId: 'fruit-market',
      origin: const CellCoord(4, 3),
    );
    for (var i = 0; i < 5; i++) {
      b = nextDay(b);
    }

    expect(a.population, 2);
    expect(
      b.population,
      2,
      reason: 'both homes fill regardless of build order',
    );
    expect(b.employedPopulation, 2);
    validateParcelWorldState(b, content, terrain);
  });

  test('the founding list survives its first unemployed family', () {
    var world = fresh();
    world = startStructureConstruction(
      world,
      content,
      terrain,
      catalogueId: 'small-home',
      origin: const CellCoord(3, 4),
    );
    world = nextDay(world);
    world = nextDay(world);
    expect(world.population, 1);
    expect(world.employedPopulation, 0);
    expect(
      world.waitingHouseholds,
      1,
      reason:
          'tolerance floors at one, so one jobless family '
          'does not freeze migration',
    );
  });

  test('tolerance admits one jobless family, then gates migration', () {
    // Three cottages, no commerce. The first family arrives and the
    // list refills behind it (tolerance floors at one); the second
    // family exhausts the list; the third home finds nobody waiting
    // — unemployment is now above tolerance and migration pauses
    // until jobs exist.
    var world = fresh();
    world = startStructureConstruction(
      world,
      content,
      terrain,
      catalogueId: 'small-home',
      origin: const CellCoord(3, 4),
    );
    world = nextDay(world);
    world = nextDay(world);
    expect(world.population, 1);
    expect(world.waitingHouseholds, 1);

    world = startStructureConstruction(
      world,
      content,
      terrain,
      catalogueId: 'small-home',
      origin: const CellCoord(5, 4),
    );
    world = nextDay(world);
    world = nextDay(world);
    world = startStructureConstruction(
      world,
      content,
      terrain,
      catalogueId: 'small-home',
      origin: const CellCoord(4, 3),
    );
    world = nextDay(world);
    world = nextDay(world);
    expect(world.population, 2);
    expect(world.waitingHouseholds, 0);
    expect(world.unemployment, 2);
    final ledger = townLedger(world, content);
    expect(ledger.residentialVacancy, 1);
    expect(ledger.employmentDemand, 2);
  });

  test('surplus jobs pull migration faster', () {
    // A market row along an eastward road: nine fruit-markets, 27
    // job capacity, and a scaled town of 24 households all
    // employed. The three surplus positions boost the migration
    // budget — with the pull at 50% the list refills to its cap of
    // 2; with the seeded 10% (floor of 0.3) it refills to 1.
    var world = fresh();
    world = planRoadStretch(
      world,
      content,
      terrain,
      cells: const [CellCoord(5, 4), CellCoord(6, 4), CellCoord(7, 4)],
    );
    for (var i = 0; i < 3; i++) {
      world = nextDay(world);
    }
    for (final origin in [
      const CellCoord(3, 4),
      const CellCoord(4, 3),
      const CellCoord(4, 5),
      const CellCoord(5, 3),
      const CellCoord(6, 3),
      const CellCoord(7, 3),
      const CellCoord(5, 5),
      const CellCoord(6, 5),
      const CellCoord(7, 5),
    ]) {
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'fruit-market',
        origin: origin,
      );
      world = nextDay(world);
      world = nextDay(world);
    }

    final settled = reconcileWorldProgression(
      world.copyWith(
        population: 24,
        employedPopulation: 24,
        waitingHouseholds: 0,
      ),
      content,
    );
    validateParcelWorldState(settled, content, terrain);

    final pullContent = ContentBundle(
      manifest: content.manifest,
      terrain: content.terrain,
      catalogue: content.catalogue,
      sprites: content.sprites,
      economy: content.economy.copyWith(jobPullPercentPerCheckIn: 50),
      ambience: content.ambience,
      progression: content.progression,
    );
    final withPull = checkInWorldForToday(
      advanceWorldDays(settled, 1),
      pullContent,
    );
    final withoutPull = checkInWorldForToday(
      advanceWorldDays(settled, 1),
      content,
    );
    expect(
      withPull.waitingHouseholds,
      2,
      reason: 'the pull-boosted budget refills the list to its cap',
    );
    expect(
      withoutPull.waitingHouseholds,
      1,
      reason: 'the base budget alone refills one',
    );
  });
}

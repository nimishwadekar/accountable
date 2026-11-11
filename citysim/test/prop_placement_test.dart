/// Placement rules for sub-tile props: the surface (ground, road,
/// bridge deck), one prop per subtile, blocking of future
/// construction, and the save round-trip.
library;

import 'package:citysim/content/asset_content_source.dart';
import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/storage/sheet_tables.dart';
import 'package:citysim/storage/world_sheet_codec.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:citysim/world/terrain_provider.dart';
import 'package:citysim/world/world_queries.dart';
import 'package:citysim/world/world_reducer.dart';
import 'package:citysim/world/world_rules.dart';
import 'package:citysim/world/world_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ContentTerrainProvider terrain;
  late ContentBundle content;

  setUpAll(() async {
    content = await loadContentBundle(const AssetContentSource());
    terrain = ContentTerrainProvider(content.terrain);
  });

  /// The codec test's handwritten town — starter road, paved road to
  /// the river, a bridge over the east water parcel, a cottage, and a
  /// half-funded café — with a rich wallet so several placements fit.
  ParcelWorldState town() => sheetTablesToWorld(
    SheetTables(
      userData: const {
        'seed': '7',
        'coins': '50',
        'coins_earned': '50',
        'coins_spent': '0',
        'simulated_date': '2026-11-02',
        'high_water_date': '2026-11-02',
        'last_checkin_date': '2026-11-02',
        'checkin_count': '1',
        'construction_day': '5',
      },
      ownedParcels: const [
        ['0', '0'],
        ['1', '0'],
        ['2', '0'],
      ],
      tiles: [
        ['4', '4', 'road', 'complete', 'dirt', '', '', ''],
        ['5', '4', 'road', 'complete', 'asphalt', '', '', ''],
        ['6', '4', 'road', 'complete', 'asphalt', '', '', ''],
        ['7', '4', 'road', 'complete', 'asphalt', '', '', ''],
        for (var column = 8; column <= 15; column++)
          ['$column', '4', 'bridge', 'complete', '', '', '', ''],
        ['16', '4', 'road', 'complete', 'asphalt', '', '', ''],
        [
          '3',
          '4',
          'structure',
          'complete',
          'small-home',
          'home-small-yellow',
          'east',
          '',
        ],
        ['6', '5', 'structure', 'planned', 'cafe', 'cafe', 'east', ''],
      ],
      projects: const [
        ['2', 'structure', 'cafe', '6:5', '1'],
      ],
    ),
    content: content,
    terrainProvider: terrain,
  );

  test('placing a prop lands it on the tapped subtile', () {
    var world = town();
    world = startStructureConstruction(
      world,
      content,
      terrain,
      catalogueId: 'pine-tree',
      origin: const CellCoord(5, 5),
      subtileX: 2,
      subtileY: 3,
    );
    final prop = world.props.single;
    expect(prop.cell, const CellCoord(5, 5));
    expect(prop.subtileX, 2);
    expect(prop.subtileY, 3);
    expect(prop.pricePaid, 2);
    expect(world.coins, 48);
    expect(
      world.structures.every(
        (structure) => structure.kind == StructureKind.building,
      ),
      isTrue,
      reason: 'decorations never join the structures list',
    );
    expect(
      () => validateParcelWorldState(world, content, terrain),
      returnsNormally,
    );
  });

  test('props cluster per tile but never share a subtile', () {
    var world = town();
    world = startStructureConstruction(
      world,
      content,
      terrain,
      catalogueId: 'pine-tree',
      origin: const CellCoord(5, 5),
      subtileX: 2,
      subtileY: 3,
    );
    world = startStructureConstruction(
      world,
      content,
      terrain,
      catalogueId: 'wild-grass',
      origin: const CellCoord(5, 5),
      subtileX: 6,
      subtileY: 6,
    );
    expect(world.props, hasLength(2));
    expect(
      WorldQueries(world, terrain).propsByCell[const CellCoord(5, 5)],
      hasLength(2),
    );
    expect(
      () => startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'rocks',
        origin: const CellCoord(5, 5),
        subtileX: 2,
        subtileY: 3,
      ),
      throwsA(isA<WorldRuleViolation>()),
      reason: 'one prop per subtile',
    );
  });

  test('props place on ground and roads — nowhere else', () {
    var world = town();
    void place(CellCoord cell, {int subtileX = 0, int subtileY = 0}) =>
        world = startStructureConstruction(
          world,
          content,
          terrain,
          catalogueId: 'wild-grass',
          origin: cell,
          subtileX: subtileX,
          subtileY: subtileY,
        );
    place(const CellCoord(5, 5)); // vacant ground
    place(const CellCoord(5, 4)); // completed road
    expect(world.props, hasLength(2));
    expect(
      () => place(const CellCoord(10, 4), subtileX: 7, subtileY: 7),
      throwsA(isA<WorldRuleViolation>()),
      reason: 'bridge decks are off the prop surface (future work)',
    );
    expect(
      () => place(const CellCoord(10, 5)),
      throwsA(isA<WorldRuleViolation>()),
      reason: 'open water',
    );
    expect(
      () => place(const CellCoord(3, 4)),
      throwsA(isA<WorldRuleViolation>()),
      reason: 'building footprint',
    );
    expect(
      () => place(const CellCoord(6, 5)),
      throwsA(isA<WorldRuleViolation>()),
      reason: 'pending construction',
    );
    expect(
      () => place(const CellCoord(24, 4)),
      throwsA(isA<WorldRuleViolation>()),
      reason: 'unowned parcel',
    );
  });

  test('props block buildings and roads', () {
    var world = town();
    world = startStructureConstruction(
      world,
      content,
      terrain,
      catalogueId: 'rocks',
      origin: const CellCoord(5, 5),
    );
    expect(
      () => quoteStructurePlacement(
        world,
        content,
        terrain,
        catalogueId: 'small-home',
        origin: const CellCoord(5, 5),
      ),
      throwsA(isA<WorldRuleViolation>()),
      reason: 'a propped tile is not vacant',
    );
    expect(
      () => quoteRoadStretch(
        world,
        content,
        terrain,
        cells: const [CellCoord(5, 5), CellCoord(5, 6)],
      ),
      throwsA(isA<WorldRuleViolation>()),
      reason: 'roads cannot pave over a prop',
    );
  });

  test('props survive the save round-trip', () {
    var world = town();
    world = startStructureConstruction(
      world,
      content,
      terrain,
      catalogueId: 'pine-tree',
      origin: const CellCoord(5, 5),
      subtileX: 1,
      subtileY: 6,
    );
    final reloaded = sheetTablesToWorld(
      worldToSheetTables(world),
      content: content,
      terrainProvider: terrain,
    );
    final prop = reloaded.props.single;
    expect(prop.cell, const CellCoord(5, 5));
    expect(prop.subtileX, 1);
    expect(prop.subtileY, 6);
    expect(prop.assetRole, world.props.single.assetRole);
    expect(prop.id, world.props.single.id);
  });

  test('picking a prop up frees its subtile and refunds nothing', () {
    var world = town();
    world = startStructureConstruction(
      world,
      content,
      terrain,
      catalogueId: 'pine-tree',
      origin: const CellCoord(5, 5),
      subtileX: 2,
      subtileY: 3,
    );
    final coinsAfterPlacement = world.coins;
    world = pickUpProp(world, content, propId: world.props.single.id);
    expect(world.props, isEmpty);
    expect(world.coins, coinsAfterPlacement, reason: 'no refund, no charge');
    expect(
      world.events.last.kind,
      'prop-picked-up',
      reason: 'the pick-up is logged',
    );
    // The subtile is placeable again — and only that subtile was freed.
    world = startStructureConstruction(
      world,
      content,
      terrain,
      catalogueId: 'rocks',
      origin: const CellCoord(5, 5),
      subtileX: 2,
      subtileY: 3,
    );
    expect(world.props, hasLength(1));
    expect(
      () => pickUpProp(world, content, propId: 'prop:9:9:0.0'),
      throwsA(isA<WorldRuleViolation>()),
      reason: 'picking up a missing prop fails loudly',
    );
    expect(
      () => validateParcelWorldState(world, content, terrain),
      returnsNormally,
    );
  });

  test('save validation rejects a prop on open water', () {
    final world = town().copyWith(
      props: [
        PlacedProp(
          id: 'prop:10:5:0.0',
          catalogueId: 'rocks',
          cell: const CellCoord(10, 5),
          subtileX: 0,
          subtileY: 0,
          pricePaid: 1,
          placedAtDay: 0,
        ),
      ],
    );
    expect(
      () => validateParcelWorldState(world, content, terrain),
      throwsA(isA<FormatException>()),
    );
  });
}

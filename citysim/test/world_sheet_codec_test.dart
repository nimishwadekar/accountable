import 'package:citysim/content/asset_content_source.dart';
import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/storage/sheet_tables.dart';
import 'package:citysim/storage/world_sheet_codec.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:citysim/world/terrain_provider.dart';
import 'package:citysim/world/world_queries.dart';
import 'package:citysim/world/world_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ContentTerrainProvider terrain;
  late ContentBundle content;

  setUpAll(() async {
    content = await loadContentBundle(const AssetContentSource());
    terrain = ContentTerrainProvider(content.terrain);
  });

  /// Hand-authored tables in the main app's test style: literal rows, no
  /// fixtures. A starter road, a paved road to the river, a completed
  /// bridge over it, a completed cottage, and a half-funded café project.
  SheetTables handwrittenTables() => SheetTables(
    userData: {
      'seed': '7',
      'coins': '3',
      'coins_earned': '4',
      'coins_spent': '1',
      'simulated_date': '2026-11-02',
      'high_water_date': '2026-11-02',
      'last_checkin_date': '2026-11-02',
      'checkin_count': '1',
      'construction_day': '5',
    },
    ownedParcels: [
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
    projects: [
      ['2', 'structure', 'cafe', '6:5', '1'],
    ],
  );

  test('handwritten tables rebuild a valid world', () {
    final world = sheetTablesToWorld(
      handwrittenTables(),
      content: content,
      terrainProvider: terrain,
    );

    expect(world.seed, 7);
    expect(world.coins, 3);
    expect(world.checkInCount, 1);
    expect(world.constructionDay, 5);
    expect(world.lastCheckInDate, DateTime.utc(2026, 11, 2));
    expect(world.parcels, hasLength(3));

    // The starter road is identified by its position at the parcel centre.
    expect(
      world.roads.firstWhere((road) => road.id == 'road-start').cell,
      const CellCoord(4, 4),
    );
    expect(world.roads, hasLength(5));

    // The bridge run derives its banks from the roads at its ends — the
    // full eight-tile crossing of the east water parcel.
    final bridge = world.bridges.single;
    expect(bridge.nearBank, const CellCoord(7, 4));
    expect(bridge.farBank, const CellCoord(16, 4));
    expect(bridge.waterCells, [
      for (var column = 8; column <= 15; column++) CellCoord(column, 4),
    ]);

    // Structures rebuild with their content-derived footprint, variant,
    // and door side; the café is still a half-funded project.
    final cottage = world.structures.single;
    expect(cottage.catalogueId, 'small-home');
    expect(cottage.assetRole, 'home-small-yellow');
    expect(cottage.facing, 'east');
    expect(cottage.footprint, [const CellCoord(3, 4)]);
    expect(cottage.population, 1);

    final project = world.constructions.single;
    expect(project.catalogueId, 'cafe');
    expect(project.origin, const CellCoord(6, 5));
    expect(project.coinsFunded, 1);
    expect(project.totalCostCoins, 3);

    // Unlocks and builder capacity derive from population.
    expect(world.population, 1);
    expect(world.unlockedCatalogueIds, contains('cafe'));
    expect(world.builderCapacity, 1);

    expect(
      () => validateParcelWorldState(world, content, terrain),
      returnsNormally,
    );
  });

  test('encoding and decoding CSV documents round-trips the tables', () {
    final tables = handwrittenTables();
    final documents = encodeSheetTables(tables);
    final decoded = decodeSheetTables(
      userData: documents[userDataSheetName]!,
      tiles: documents[tilesSheetName]!,
      ownedParcels: documents[ownedParcelsSheetName]!,
      projects: documents[projectsSheetName]!,
    );
    // A comma inside a value exercises CSV quoting.
    final quoted = decodeSheetTables(
      userData: 'key,value\nnote,"hello, world"\nseed,7\n',
    );
    expect(quoted.userData['note'], 'hello, world');
    expect(decoded.userData, tables.userData);
    expect(decoded.tiles, tables.tiles);
    expect(decoded.ownedParcels, tables.ownedParcels);
    expect(decoded.projects, tables.projects);
  });

  test('tables are a fixed point: world → tables → world → same tables', () {
    final world = sheetTablesToWorld(
      handwrittenTables(),
      content: content,
      terrainProvider: terrain,
    );
    final again = sheetTablesToWorld(
      worldToSheetTables(world),
      content: content,
      terrainProvider: terrain,
    );
    expect(
      encodeSheetTables(worldToSheetTables(again)),
      encodeSheetTables(worldToSheetTables(world)),
    );
  });

  test('stale project references on completed roads are healed', () {
    final base = handwrittenTables();
    // A pre-fix save: the completed road at (5,4) still names project 9,
    // which finished long ago. Its reference must be dropped on load.
    final tiles = <List<String>>[for (final row in base.tiles) row];
    final staleIndex = tiles.indexWhere(
      (row) => row[0] == '5' && row[1] == '4',
    );
    final stale = [...tiles[staleIndex]];
    stale[7] = '9';
    tiles[staleIndex] = stale;
    final world = sheetTablesToWorld(
      SheetTables(
        userData: base.userData,
        ownedParcels: base.ownedParcels,
        tiles: tiles,
        projects: base.projects,
      ),
      content: content,
      terrainProvider: terrain,
    );
    final healed = world.roads.singleWhere(
      (road) => road.cell == const CellCoord(5, 4),
    );
    expect(healed.projectId, isNull);
    expect(
      () => validateParcelWorldState(world, content, terrain),
      returnsNormally,
    );
  });

  test('planned road tiles with dead project references still fail', () {
    final base = handwrittenTables();
    expect(
      () => sheetTablesToWorld(
        SheetTables(
          userData: base.userData,
          ownedParcels: base.ownedParcels,
          tiles: [
            ...base.tiles,
            ['4', '5', 'road', 'planned', 'dirt', '', '', '9'],
          ],
          projects: base.projects,
        ),
        content: content,
        terrainProvider: terrain,
      ),
      throwsA(isA<FormatException>()),
      reason: 'a planned tile without a live project is orphaned, not healed',
    );
  });

  test('corrupt tables fail loudly', () {
    expect(
      () => sheetTablesToWorld(
        SheetTables(
          userData: handwrittenTables().userData,
          ownedParcels: handwrittenTables().ownedParcels,
          tiles: [
            ...handwrittenTables().tiles,
            ['9', '9', 'alien', 'complete', '', '', '', ''],
          ],
        ),
        content: content,
        terrainProvider: terrain,
      ),
      throwsA(isA<FormatException>()),
      reason: 'unknown tile kind',
    );
    expect(
      () => sheetTablesToWorld(
        SheetTables(
          userData: handwrittenTables().userData,
          ownedParcels: handwrittenTables().ownedParcels,
          tiles: handwrittenTables().tiles,
          projects: [
            ['9', 'structure', 'cafe', '8:6', '1'],
          ],
        ),
        content: content,
        terrainProvider: terrain,
      ),
      throwsA(isA<FormatException>()),
      reason: 'planned tile without a matching project',
    );
    expect(
      () => sheetTablesToWorld(
        SheetTables(
          userData: {'seed': '7'},
          ownedParcels: const [],
          tiles: [
            ['4', '4', 'road', 'complete', 'dirt', '', '', ''],
            ['4', '4', 'structure', 'complete', 'small-home', '', '', ''],
          ],
        ),
        content: content,
        terrainProvider: terrain,
      ),
      throwsA(isA<FormatException>()),
      reason: 'two entities on one cell',
    );
    expect(
      () => sheetTablesToWorld(
        SheetTables(
          userData: handwrittenTables().userData,
          ownedParcels: handwrittenTables().ownedParcels,
          tiles: [
            ...handwrittenTables().tiles,
            ['9', '6', 'structure', 'complete', 'small-home', '', 'left', ''],
          ],
        ),
        content: content,
        terrainProvider: terrain,
      ),
      throwsA(isA<FormatException>()),
      reason: 'legacy left/right facings must migrate to cardinals first',
    );
  });

  SheetTables withProps(List<List<String>> props) {
    final base = handwrittenTables();
    return SheetTables(
      userData: base.userData,
      tiles: base.tiles,
      props: props,
      ownedParcels: base.ownedParcels,
      projects: base.projects,
    );
  }

  test('props decode onto the subtile lattice and validate', () {
    final world = sheetTablesToWorld(
      withProps(const [
        ['5', '5', '3', '3', 'pine-tree', 'pine-small', ''],
        ['5', '5', '6', '2', 'wild-grass', '', ''],
        ['5', '4', '0', '0', 'street-lamp', '', ''],
        ['10', '4', '7', '7', 'rocks', '', ''],
      ]),
      content: content,
      terrainProvider: terrain,
    );
    expect(world.props, hasLength(4));
    expect(world.props.first.id, 'prop:5,5:3.3');
    final queries = WorldQueries(world, terrain);
    expect(queries.propsByCell[const CellCoord(5, 5)], hasLength(2));
    // Ground, completed road, and bridge deck all carry props.
    expect(queries.propAt(const CellCoord(5, 4), 0, 0), isNotNull);
    expect(queries.propAt(const CellCoord(10, 4), 7, 7), isNotNull);
    expect(
      () => validateParcelWorldState(world, content, terrain),
      returnsNormally,
    );
  });

  test('props round-trip as a fixed point', () {
    final world = sheetTablesToWorld(
      withProps(const [
        ['5', '5', '3', '3', 'pine-tree', 'pine-small', ''],
        ['5', '5', '6', '2', 'wild-grass', '', ''],
        ['10', '4', '7', '7', 'rocks', '', ''],
      ]),
      content: content,
      terrainProvider: terrain,
    );
    final again = sheetTablesToWorld(
      worldToSheetTables(world),
      content: content,
      terrainProvider: terrain,
    );
    expect(again.props, hasLength(3));
    expect(
      encodeSheetTables(worldToSheetTables(again)),
      encodeSheetTables(worldToSheetTables(world)),
    );
  });

  test('two props on one subtile fail the load', () {
    expect(
      () => sheetTablesToWorld(
        withProps(const [
          ['5', '5', '3', '3', 'pine-tree', '', ''],
          ['5', '5', '3', '3', 'rocks', '', ''],
        ]),
        content: content,
        terrainProvider: terrain,
      ),
      throwsA(isA<FormatException>()),
      reason: 'one prop per subtile',
    );
  });

  test('decorations are rejected in the Tiles sheet', () {
    final base = handwrittenTables();
    expect(
      () => sheetTablesToWorld(
        SheetTables(
          userData: base.userData,
          ownedParcels: base.ownedParcels,
          tiles: [
            ...base.tiles,
            ['9', '6', 'structure', 'complete', 'pine-tree', '', '', ''],
          ],
          projects: base.projects,
        ),
        content: content,
        terrainProvider: terrain,
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => '$error',
          'message',
          contains('Props sheet'),
        ),
      ),
      reason: 'decorations live in the Props sheet since the lattice',
    );
  });

  test('prop rows validate their lattice and model kind', () {
    expect(
      () => sheetTablesToWorld(
        withProps(const [
          ['5', '5', '8', '0', 'rocks', '', ''],
        ]),
        content: content,
        terrainProvider: terrain,
      ),
      throwsA(isA<FormatException>()),
      reason: 'subtile 8 is outside the 8×8 lattice',
    );
    expect(
      () => sheetTablesToWorld(
        withProps(const [
          ['5', '5', '0', '0', 'small-home', '', ''],
        ]),
        content: content,
        terrainProvider: terrain,
      ),
      throwsA(isA<FormatException>()),
      reason: 'buildings live in the Tiles sheet',
    );
    expect(
      () => sheetTablesToWorld(
        withProps(const [
          ['5', '5', '0', '0', 'pine-tree', 'not-a-role', ''],
        ]),
        content: content,
        terrainProvider: terrain,
      ),
      throwsA(isA<FormatException>()),
      reason: 'unknown sprite variant',
    );
  });
}

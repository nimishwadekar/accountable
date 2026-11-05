import 'package:citysim/content/asset_content_source.dart';
import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/storage/sheet_tables.dart';
import 'package:citysim/storage/world_sheet_codec.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:citysim/world/terrain_provider.dart';
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
        'right',
        '',
      ],
      ['6', '5', 'structure', 'planned', 'cafe', 'cafe', 'right', ''],
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
    expect(cottage.facing, 'right');
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
  });
}

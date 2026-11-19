import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/storage/sheet_tables.dart';
import 'package:citysim/storage/world_sheet_codec.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:citysim/world/terrain_provider.dart';
import 'package:citysim/world/world_queries.dart';
import 'package:citysim/world/world_rules.dart';
import 'package:flutter_test/flutter_test.dart';

import 'frozen_content.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ContentTerrainProvider terrain;
  late ContentBundle content;

  setUpAll(() {
    content = frozenContent();
    terrain = ContentTerrainProvider(content.terrain);
  });

  /// Hand-authored tables in the main app's test style: literal rows, no
  /// fixtures. A starter road, a paved road to the river, a completed
  /// bridge over it, a completed cottage, and a half-funded café project.
  SheetTables handwrittenTables() => SheetTables(
    ownedParcels: [
      ['0', '0'],
      ['1', '0'],
      ['2', '0'],
    ],
    userData: {
      'seed': '7',
      'population': '1',
      'employed_population': '1',
      'waiting_population': '0',
      'coins': '3',
      'coins_earned': '4',
      'coins_spent': '1',
      'simulated_date': '2026-11-02',
      'high_water_date': '2026-11-02',
      'last_checkin_date': '2026-11-02',
      'checkin_count': '1',
      'construction_day': '5',
    },
    tiles: [
      ['4', '4', 'road', 'complete', 'dirt', '', '', ''],
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

  test('non-square structures rebuild turned by their saved facing', () {
    // A clinic saved facing east turns its 2×1 lot a quarter: the
    // cells run south from the origin, the street edge on the road —
    // the same turn the placement that chose the facing made.
    final world = sheetTablesToWorld(
      SheetTables(
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
        ],
        tiles: [
          [
            '4',
            '5',
            'structure',
            'complete',
            'community-clinic',
            'clinic',
            'east',
            '',
          ],
        ],
      ),
      content: content,
      terrainProvider: terrain,
    );
    final clinic = world.structures.single;
    expect(clinic.quarterTurns, 1);
    expect(clinic.footprint, const [CellCoord(4, 5), CellCoord(4, 6)]);
  });

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

    // Roads re-derive their ids and prices from position: the old
    // starter-road special case is gone, and every road — the one at
    // the parcel centre included — loads as an ordinary paid tile.
    // (Cosmetic only: road prices feed no ledger or rule.)
    expect(
      world.roads.firstWhere((road) => road.cell == const CellCoord(4, 4)).id,
      'road:4,4',
    );
    expect(
      world.roads
          .firstWhere((road) => road.cell == const CellCoord(4, 4))
          .pricePaid,
      content.economy.roadTileCostCoins,
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
    // and door side; the café is still a mid-construction project.
    // (The hall rebuilds too — see the founding row in the tables.)
    final cottage = world.structures.lastWhere(
      (structure) => structure.catalogueId == 'small-home',
    );
    expect(cottage.catalogueId, 'small-home');
    expect(cottage.assetRole, 'home-small-yellow');
    expect(cottage.facing, 'east');
    expect(cottage.footprint, [const CellCoord(3, 4)]);
    expect(cottage.population, 3);

    // The aggregate counters round-trip through UserData.
    expect(world.population, 1);
    expect(world.employedPopulation, 1);
    expect(world.waitingPopulation, 0);

    final project = world.constructions.single;
    expect(project.catalogueId, 'cafe');
    expect(project.origin, const CellCoord(6, 5));
    expect(project.stagesDone, 1);
    expect(
      project.stagesDone,
      lessThan(content.structure('cafe')!.constructionStages),
      reason: 'the funded column stores stages done',
    );

    // Unlocks derive from population.
    expect(world.population, 1);
    expect(world.unlockedCatalogueIds, contains('cafe'));

    expect(
      () => validateParcelWorldState(world, content, terrain),
      returnsNormally,
    );
  });

  test('encoding and decoding CSV documents round-trips the tables', () {
    final tables = handwrittenTables();
    final documents = encodeMultiCityTables(
      MultiCityTables(
        cities: const [
          CityRecord(id: 'city_1', name: 'City 1', founded: '2026-11-02'),
        ],
        tablesById: {'city_1': tables},
      ),
    );
    final decoded = decodeMultiCityTables(
      cities: documents[citiesSheetName]!,
      userData: documents[userDataSheetName]!,
      tiles: documents[tilesSheetName]!,
      props: documents[propsSheetName]!,
      ownedParcels: documents[ownedParcelsSheetName]!,
      projects: documents[projectsSheetName]!,
    ).tablesById['city_1']!;
    // A comma inside a value exercises CSV quoting.
    final quoted = decodeMultiCityTables(
      cities: 'city_id,name,founded\ncity_1,City 1,2026-11-02\n',
      userData: 'city_id,key,value\ncity_1,note,"hello, world"\n',
    ).tablesById['city_1']!;
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
      encodeMultiCityTables(
        MultiCityTables(
          cities: const [
            CityRecord(id: 'city_1', name: 'City 1', founded: '2026-11-02'),
          ],
          tablesById: {'city_1': worldToSheetTables(again)},
        ),
      ),
      encodeMultiCityTables(
        MultiCityTables(
          cities: const [
            CityRecord(id: 'city_1', name: 'City 1', founded: '2026-11-02'),
          ],
          tablesById: {'city_1': worldToSheetTables(world)},
        ),
      ),
    );
  });

  group('multi-city tables', () {
    test('two cities round-trip with no cross-decoding', () {
      final first = handwrittenTables();
      final second = SheetTables(
        userData: {...first.userData, 'seed': '42'},
        tiles: const [
          ['9', '9', 'road', 'complete', 'asphalt', '', '', ''],
        ],
        ownedParcels: const [
          ['5', '5'],
          ['6', '5'],
        ],
      );
      final documents = encodeMultiCityTables(
        MultiCityTables(
          cities: const [
            CityRecord(id: 'city_1', name: 'Alpha', founded: '2026-11-01'),
            CityRecord(id: 'city_2', name: 'Beta', founded: '2026-11-02'),
          ],
          tablesById: {'city_1': first, 'city_2': second},
        ),
      );

      // City-major blocks: every Tiles row of city_1 precedes city_2's.
      final tilesCityIds = [
        for (final row in decodeCsvRows(documents[tilesSheetName]!)) row[0],
      ];
      expect(
        tilesCityIds.sublist(0, first.tiles.length),
        everyElement('city_1'),
      );
      expect(tilesCityIds.sublist(first.tiles.length), everyElement('city_2'));

      final decoded = decodeMultiCityTables(
        cities: documents[citiesSheetName]!,
        userData: documents[userDataSheetName]!,
        tiles: documents[tilesSheetName]!,
        props: documents[propsSheetName]!,
        ownedParcels: documents[ownedParcelsSheetName]!,
        projects: documents[projectsSheetName]!,
      );
      expect(decoded.cities.map((record) => record.id), ['city_1', 'city_2']);
      expect(decoded.cities.first.name, 'Alpha');
      expect(decoded.tablesById['city_1']!.userData, first.userData);
      expect(decoded.tablesById['city_1']!.tiles, first.tiles);
      expect(decoded.tablesById['city_1']!.ownedParcels, first.ownedParcels);
      expect(decoded.tablesById['city_2']!.userData['seed'], '42');
      expect(decoded.tablesById['city_2']!.tiles, second.tiles);
      expect(decoded.tablesById['city_2']!.ownedParcels, second.ownedParcels);
      expect(decoded.nextCityId(), 'city_3');
    });

    test('city ids sort numerically and mint past the highest', () {
      expect(MultiCityTables().nextCityId(), 'city_1');
      expect(
        MultiCityTables(
          tablesById: const {'city_1': SheetTables(), 'city_10': SheetTables()},
        ).nextCityId(),
        'city_11',
        reason: 'city_10 sorts after city_9, not after city_1',
      );
      expect(
        () => cityIdNumber('parcel-world-7'),
        throwsA(isA<FormatException>()),
      );
    });

    test('the same parcel in two cities fails the decode', () {
      final documents = encodeMultiCityTables(
        MultiCityTables(
          cities: const [
            CityRecord(id: 'city_1', name: 'A', founded: '2026-11-01'),
            CityRecord(id: 'city_2', name: 'B', founded: '2026-11-01'),
          ],
          tablesById: const {
            'city_1': SheetTables(
              ownedParcels: [
                ['0', '0'],
              ],
            ),
            'city_2': SheetTables(
              ownedParcels: [
                ['0', '0'],
              ],
            ),
          },
        ),
      );
      expect(
        () => decodeMultiCityTables(
          cities: documents[citiesSheetName]!,
          userData: documents[userDataSheetName]!,
          tiles: documents[tilesSheetName]!,
          props: documents[propsSheetName]!,
          ownedParcels: documents[ownedParcelsSheetName]!,
          projects: documents[projectsSheetName]!,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('owned by both'),
          ),
        ),
      );
    });

    test('an unmigrated single-city save fails visibly', () {
      // The old five-sheet shape: no Cities document, no city column.
      // There is no migration code, so this is the intended failure.
      expect(
        () => decodeMultiCityTables(
          userData: 'key,value\nseed,7\n',
          tiles:
              'x,y,kind,status,detail,variant,facing,project\n'
              '4,4,road,complete,asphalt,,,\n',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('multi-city format'),
          ),
        ),
      );
    });
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

  test('a road project delivering through the parcel centre validates', () {
    // The pre-founding era parked a free starter road at (4,4), and
    // the loader re-derived any road there as free — which broke
    // saves whose road project had delivered a PAID tile onto that
    // cell mid-project (delivered project roads must carry the
    // standard price). Every road now loads at the standard price,
    // wherever it sits.
    final world = sheetTablesToWorld(
      SheetTables(
        userData: const {
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
        ownedParcels: const [
          ['0', '0'],
        ],
        tiles: const [
          ['4', '4', 'road', 'complete', 'asphalt', '', '', '3'],
          ['5', '4', 'road', 'planned', 'asphalt', '', '', '3'],
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
        projects: const [
          ['3', 'road', 'asphalt', '', ''],
        ],
      ),
      content: content,
      terrainProvider: terrain,
    );
    expect(
      world.roads
          .singleWhere((road) => road.cell == const CellCoord(4, 4))
          .pricePaid,
      content.economy.roadTileCostCoins,
    );
    expect(world.constructions.single.roadCells, [
      const CellCoord(4, 4),
      const CellCoord(5, 4),
    ]);
    expect(
      () => validateParcelWorldState(world, content, terrain),
      returnsNormally,
    );
  });

  test('the progression high-water persists', () {
    // A world whose stored reached milestone exceeds what its
    // population would derive: it survives the round-trip
    // verbatim — a future population dip can shrink nothing.
    final world =
        sheetTablesToWorld(
          handwrittenTables(),
          content: content,
          terrainProvider: terrain,
        ).copyWith(
          population: 60,
          progressionMilestoneId: 'village',
          progressionMilestonePopulation: 50,
        );
    final reloaded = sheetTablesToWorld(
      worldToSheetTables(world),
      content: content,
      terrainProvider: terrain,
    );
    expect(reloaded.progressionMilestoneId, 'village');
    expect(reloaded.progressionMilestonePopulation, 50);
    expect(reloaded.unlockedCatalogueIds, contains('community-clinic'));

    // Legacy saves with no milestone row derive once from their
    // stored population — exact, because population has only ever
    // grown — and write the row on their first save under the new
    // rules.
    expect(
      handwrittenTables().userData.containsKey('progression_milestone'),
      isFalse,
      reason: 'the handwritten tables are a pre-migration save',
    );
    final legacyTables = SheetTables(
      userData: {...handwrittenTables().userData, 'population': '60'},
      ownedParcels: handwrittenTables().ownedParcels,
      tiles: handwrittenTables().tiles,
      projects: handwrittenTables().projects,
    );
    final migrated = sheetTablesToWorld(
      legacyTables,
      content: content,
      terrainProvider: terrain,
    );
    expect(migrated.progressionMilestoneId, 'village');
    expect(
      worldToSheetTables(migrated).userData['progression_milestone'],
      'village',
      reason: 'the first save after migration writes the row',
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
        ['5', '6', '7', '7', 'rocks', '', ''],
      ]),
      content: content,
      terrainProvider: terrain,
    );
    expect(world.props, hasLength(4));
    expect(world.props.first.id, 'prop:5,5:3.3');
    final queries = WorldQueries(world, terrain);
    expect(queries.propsByCell[const CellCoord(5, 5)], hasLength(2));
    // Ground and completed road carry props.
    expect(queries.propAt(const CellCoord(5, 4), 0, 0), isNotNull);
    expect(queries.propAt(const CellCoord(5, 6), 7, 7), isNotNull);
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
      encodeMultiCityTables(
        MultiCityTables(
          cities: const [
            CityRecord(id: 'city_1', name: 'City 1', founded: '2026-11-02'),
          ],
          tablesById: {'city_1': worldToSheetTables(again)},
        ),
      ),
      encodeMultiCityTables(
        MultiCityTables(
          cities: const [
            CityRecord(id: 'city_1', name: 'City 1', founded: '2026-11-02'),
          ],
          tablesById: {'city_1': worldToSheetTables(world)},
        ),
      ),
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

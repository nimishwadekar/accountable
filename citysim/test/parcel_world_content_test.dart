import 'package:citysim/content/asset_content_source.dart';
import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:citysim/world/road_sprite_resolver.dart';
import 'package:citysim/world/terrain_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ContentBundle content;

  setUpAll(() async {
    content = await loadContentBundle(const AssetContentSource());
  });

  test(
    'all logical catalogue and road-mask roles resolve to supplied art',
    () async {
      final roles = <String>{
        ...content.catalogue.expand((definition) => definition.assetRoles),
        for (var mask = 0; mask < 16; mask++) roadSpriteRole(mask),
        ...requiredSpriteRoles,
      };
      for (final role in roles) {
        final definition = content.sprite(role);
        expect(definition, isNotNull, reason: role);
        // Every door facing of the sprite must bundle as a loadable asset.
        for (final path in content.allAssetPaths(role)) {
          expect(await rootBundle.load(path), isNotNull, reason: path);
        }
      }
    },
  );

  test('sprite side shifts validate within half the sprite width', () {
    // The seeded sprites carry no side shifts at all.
    final seeded = validateContentData(
      catalogue: content.catalogue,
      sprites: content.sprites,
      economy: content.economy,
      ambience: content.ambience,
      terrain: content.terrain,
    );
    expect(
      seeded.where((issue) => issue.message.contains('side shift')),
      isEmpty,
    );

    // A sprite shifted past half its width fails validation, a
    // non-compass side key fails too, and an in-range entry passes.
    final role = content.catalogue.first.assetRoles.first;
    final outOfRange = {
      ...content.sprites,
      role: content.sprites[role]!.copyWith(
        sideShifts: const {'south': (0.75, 0)},
      ),
    };
    expect(
      validateContentData(
        catalogue: content.catalogue,
        sprites: outOfRange,
        economy: content.economy,
        ambience: content.ambience,
        terrain: content.terrain,
      ).any(
        (issue) =>
            issue.severity == 'error' && issue.message.contains('side shift'),
      ),
      isTrue,
    );
    final badSide = {
      ...content.sprites,
      role: content.sprites[role]!.copyWith(sideShifts: const {'up': (0.1, 0)}),
    };
    expect(
      validateContentData(
        catalogue: content.catalogue,
        sprites: badSide,
        economy: content.economy,
        ambience: content.ambience,
        terrain: content.terrain,
      ).any(
        (issue) =>
            issue.severity == 'error' &&
            issue.message.contains('not a compass side'),
      ),
      isTrue,
    );
    final inRange = {
      ...content.sprites,
      role: content.sprites[role]!.copyWith(
        sideShifts: const {'south': (0, -0.5)},
      ),
    };
    expect(
      validateContentData(
        catalogue: content.catalogue,
        sprites: inRange,
        economy: content.economy,
        ambience: content.ambience,
        terrain: content.terrain,
      ).where((issue) => issue.message.contains('side shift')),
      isEmpty,
    );
  });

  test('road walkable masks parse, round-trip, and validate', () {
    // The live content is the user's working file — road roles may
    // carry paint at any time — so this test never assumes blankness;
    // it builds its own sprites and pins the mechanics.

    // A mask-less sprite omits walkable from its JSON.
    final fresh = SpriteDefinition.fromJson(const {
      'path': 'sprites/roads/straight/some-tile.png',
      'groundAnchor': [0.5, 1],
    });
    expect(fresh.walkable, isEmpty);
    expect(fresh.toJson().containsKey('walkable'), isFalse);

    // Eight row bytes round-trip, and bits read per subtile: bit x of
    // row y, row 0 the north edge, bit 0 the west edge.
    final painted = content
        .sprite('road.straight.se')!
        .copyWith(walkable: const [255, 0, 0, 0, 0, 0, 0, 128]);
    expect(painted.walkableAt(0, 0), isTrue);
    expect(painted.walkableAt(7, 0), isTrue);
    expect(painted.walkableAt(7, 7), isTrue);
    expect(painted.walkableAt(6, 7), isFalse);
    expect(painted.walkableAt(0, 1), isFalse);
    expect(SpriteDefinition.fromJson(painted.toJson()).walkable, const [
      255,
      0,
      0,
      0,
      0,
      0,
      0,
      128,
    ]);

    // A road role validates clean with a well-formed mask...
    final valid = {...content.sprites, 'road.straight.se': painted};
    expect(
      validateContentData(
        catalogue: content.catalogue,
        sprites: valid,
        economy: content.economy,
        ambience: content.ambience,
        terrain: content.terrain,
      ).where((issue) => issue.message.contains('walkable')),
      isEmpty,
    );

    // ...while a wrong length, an out-of-range byte, or paint on a
    // non-road sprite each report their own issue.
    final issues = validateContentData(
      catalogue: content.catalogue,
      sprites: {
        ...content.sprites,
        'road.straight.se': painted.copyWith(walkable: const [255, 0]),
        'road.straight.sw': painted.copyWith(
          walkable: const [0, 0, 0, 0, 0, 0, 0, 256],
        ),
        content.catalogue.first.assetRoles.first: content
            .sprites[content.catalogue.first.assetRoles.first]!
            .copyWith(walkable: const [1, 0, 0, 0, 0, 0, 0, 0]),
      },
      economy: content.economy,
      ambience: content.ambience,
      terrain: content.terrain,
    );
    expect(
      issues.any(
        (issue) =>
            issue.severity == 'error' &&
            issue.message.contains('exactly eight row bytes'),
      ),
      isTrue,
    );
    expect(
      issues.any(
        (issue) => issue.severity == 'error' && issue.message.contains('0–255'),
      ),
      isTrue,
    );
    expect(
      issues.any(
        (issue) =>
            issue.severity == 'warning' &&
            issue.message.contains('only road and bridge tiles'),
      ),
      isTrue,
    );
  });

  test('bridge surface lift parses, round-trips, and validates', () {
    // Both deck roles carry the measured lift: 12 world px is where
    // the art draws the deck surface, and the ramps' incline derives
    // from it — a silent change would sink people into the deck.
    expect(content.sprite('bridge.body.se')!.surfaceLift, 12);
    expect(content.sprite('bridge.body.sw')!.surfaceLift, 12);
    expect(content.sprite('road.straight.se')!.surfaceLift, 0);

    // Zero lift stays out of the JSON; authored values round-trip.
    final fresh = SpriteDefinition.fromJson(const {
      'path': 'sprites/bridges/body/some-tile.png',
      'groundAnchor': [0.5, 1],
    });
    expect(fresh.toJson().containsKey('surfaceLift'), isFalse);
    final lifted = fresh.copyWith(surfaceLift: 12);
    expect(SpriteDefinition.fromJson(lifted.toJson()).surfaceLift, 12);

    // Negative lift is an error.
    expect(
      validateContentData(
        catalogue: content.catalogue,
        sprites: {
          ...content.sprites,
          'bridge.body.se': lifted.copyWith(surfaceLift: -1),
        },
        economy: content.economy,
        ambience: content.ambience,
        terrain: content.terrain,
      ).any(
        (issue) =>
            issue.severity == 'error' && issue.message.contains('surfaceLift'),
      ),
      isTrue,
    );
  });

  test('the tile grid validates its alpha and colour channels', () {
    final bad = AmbienceContent(
      ambientTimeScale: content.ambience.ambientTimeScale,
      vegetationSway: content.ambience.vegetationSway,
      pedestrians: content.ambience.pedestrians,
      unownedLandWash: content.ambience.unownedLandWash,
      tileGrid: const TileGridContent(alpha: 300, colorRgb: [30, 101, 82]),
    );
    expect(
      validateContentData(
        catalogue: content.catalogue,
        sprites: content.sprites,
        economy: content.economy,
        ambience: bad,
        terrain: content.terrain,
      ).any(
        (issue) =>
            issue.severity == 'error' && issue.message.contains('Tile grid'),
      ),
      isTrue,
    );
  });

  test('content seed snapshot holds the seeded defaults', () {
    // Snapshot guard: these values are the seeded defaults the dashboard
    // starts from — the original nine models, the promoted Buggy
    // Studio pack art, and the promoted props. Editing them in the
    // editor is expected; editing them by accident in the JSON is not.
    expect(content.catalogue, hasLength(40));
    final byId = {for (final model in content.catalogue) model.id: model};
    expect(byId['small-home']!.costCoins, 3);
    expect(byId['small-home']!.population, 1);
    expect(byId['small-home']!.unlockAtPopulation, 0);
    expect(byId['cafe']!.costCoins, 3);
    expect(byId['flower-garden']!.costCoins, 1);
    expect(byId['flower-garden']!.kind, StructureKind.decoration);
    expect(byId['flower-garden']!.population, 0);
    expect(byId['pine-tree']!.costCoins, 2);
    expect(byId['medium-home']!.costCoins, 4);
    expect(byId['medium-home']!.unlockAtPopulation, 5);
    expect(byId['fruit-market']!.costCoins, 5);
    expect(byId['community-clinic']!.costCoins, 6);
    expect(byId['community-clinic']!.unlockAtPopulation, 10);
    expect(byId['apartments']!.costCoins, 8);
    expect(byId['apartments']!.footprintColumns, 2);
    expect(byId['apartments']!.footprintRows, 2);
    expect(byId['apartments']!.unlockAtPopulation, 20);
    expect(byId['city-office']!.costCoins, 8);

    // Promoted pack art: representative snapshot of the new models.
    expect(byId['small-home']!.assetRoles, hasLength(6));
    expect(byId['medium-home']!.assetRoles, hasLength(5));
    expect(byId['city-office']!.assetRoles, hasLength(5));
    expect(byId['ice-cream-shop']!.unlockAtPopulation, 0);
    expect(byId['large-home']!.costCoins, 5);
    expect(byId['large-home']!.assetRoles, hasLength(6));
    expect(byId['large-home']!.unlockAtPopulation, 10);
    expect(byId['warehouse']!.footprintColumns, 2);
    expect(byId['warehouse']!.subcategory, 'industrial');
    expect(byId['construction-site']!.kind, StructureKind.building);
    expect(byId['construction-site']!.population, 0);
    expect(byId['hospital']!.unlockAtPopulation, 30);

    // Promoted props: representative snapshot of the decoration batch.
    expect(byId['common-tree']!.kind, StructureKind.decoration);
    expect(byId['common-tree']!.costCoins, 2);
    expect(byId['common-tree']!.assetRoles, hasLength(2));
    expect(byId['street-lamp']!.costCoins, 3);
    expect(byId['street-lamp']!.subcategory, 'streetside');
    expect(byId['traffic-light']!.costCoins, 5);
    expect(byId['rocks']!.assetRoles, hasLength(6));
    expect(byId['rocks']!.subcategory, 'rocks');
    expect(byId['tires']!.subcategory, 'clutter');
    expect(byId['wild-grass']!.costCoins, 1);

    expect(content.economy.startingWalletCoins, 0);
    expect(content.economy.startingBuilderCapacity, 1);
    expect(content.economy.roadTileCostCoins, 1);
    expect(content.economy.bridgeTileCostCoins, 2);
    expect(
      content.economy.parcelBaseCoins,
      8,
      reason: 'flat parcel price: every parcel on the map costs the same',
    );
    expect(content.economy.builderProgression, isEmpty);
    expect(
      content.economy.builderCapacityForPopulation(1000),
      1,
      reason: 'an empty progression keeps one builder forever',
    );

    expect(content.ambience.ambientTimeScale, 1.0);
    // 0.6 draws a person at ~1.8 m on the 0.2 m/px scale ruler.
    expect(content.ambience.pedestrians.spriteScale, closeTo(0.6, 0.001));
  });

  test('negative cell coordinates map to the correct neighboring parcels', () {
    expect(parcelForCell(const CellCoord(-1, 0)), const ParcelCoord(-1, 0));
    expect(parcelForCell(const CellCoord(-8, -8)), const ParcelCoord(-1, -1));
    expect(parcelForCell(const CellCoord(-9, -9)), const ParcelCoord(-2, -2));
  });

  test('road sprite roles keep their openings facing connected neighbours', () {
    // End caps are named for the capped side, so a single connection to the
    // north needs the cap facing away from it.
    expect(roadSpriteRole(roadNorth), 'road.end.sw');
    expect(roadSpriteRole(roadEast), 'road.end.nw');
    expect(roadSpriteRole(roadSouth), 'road.end.ne');
    expect(roadSpriteRole(roadWest), 'road.end.se');
    // Corners are named for the elbow, opposite the two open edges.
    expect(roadSpriteRole(roadNorth | roadEast), 'road.corner.w');
    expect(roadSpriteRole(roadEast | roadSouth), 'road.corner.n');
    expect(roadSpriteRole(roadSouth | roadWest), 'road.corner.e');
    expect(roadSpriteRole(roadWest | roadNorth), 'road.corner.s');
    // Straights are named for their axis.
    expect(roadSpriteRole(roadNorth | roadSouth), 'road.straight.sw');
    expect(roadSpriteRole(roadEast | roadWest), 'road.straight.se');
  });

  group('roadCrossingRole', () {
    // Lays out the given cells as roads and resolves the crossing for
    // the target tile, exactly the way the renderer does.
    String? crossingAt(List<(int, int)> cells, (int, int) target) {
      final roadCells = {for (final cell in cells) CellCoord(cell.$1, cell.$2)};
      final cell = CellCoord(target.$1, target.$2);
      return roadCrossingRole(
        roadNeighborMask(cell, roadCells),
        cell,
        roadCells,
      );
    }

    test('approach tiles beside a junction face it, per compass side', () {
      // A cross to the north; the approach below it crosses toward it.
      expect(
        crossingAt(
          [(0, -2), (0, -1), (1, -1), (-1, -1), (0, 0), (0, 1), (0, 2)],
          (0, 0),
        ),
        'road.pelican.ne',
      );
      // A T to the south (stem east).
      expect(
        crossingAt([(0, -2), (0, -1), (0, 0), (0, 1), (1, 1), (0, 2)], (0, 0)),
        'road.pelican.sw',
      );
      // A cross to the west.
      expect(
        crossingAt(
          [(-2, 0), (-1, 0), (-1, -1), (-1, 1), (0, 0), (1, 0), (2, 0)],
          (0, 0),
        ),
        'road.pelican.nw',
      );
      // A T to the east (stem south).
      expect(
        crossingAt([(-2, 0), (-1, 0), (0, 0), (1, 0), (1, 1), (2, 0)], (0, 0)),
        'road.pelican.se',
      );
    });

    test('only junctions earn crossings, and only on approach tiles', () {
      // A corner beside a straight is a bend, not a junction.
      expect(
        crossingAt([(0, -1), (1, -1), (0, 0), (0, 1), (0, 2)], (0, 0)),
        isNull,
      );
      // A plain run of straights has no junction to cross toward.
      expect(
        crossingAt([(0, -2), (0, -1), (0, 0), (0, 1), (0, 2)], (0, 0)),
        isNull,
      );
      // The junction tiles themselves are not approaches — the crossing
      // belongs to the tile beside them.
      expect(
        crossingAt(
          [(0, -2), (0, -1), (1, -1), (-1, -1), (0, 0), (0, 1), (0, 2)],
          (0, -1),
        ),
        isNull,
        reason: 'the cross tile is the junction, not an approach',
      );
      // End caps never cross — pelican art only exists for straights.
      expect(
        crossingAt([(0, 0), (0, 1), (1, 1), (-1, 1)], (0, 0)),
        isNull,
        reason: 'a dead-end stub beside a junction is an end cap',
      );
    });

    test('a tile between two junctions faces the busier one', () {
      // Cross north (four arms) against T south (three): the crossing
      // faces the cross.
      expect(
        crossingAt(
          [(0, -2), (1, -1), (-1, -1), (0, -1), (0, 0), (0, 1), (1, 1), (0, 2)],
          (0, 0),
        ),
        'road.pelican.ne',
      );
      // Reversed: the cross sits to the south, the T to the north.
      expect(
        crossingAt(
          [(0, -2), (1, -1), (0, -1), (0, 0), (0, 1), (1, 1), (-1, 1), (0, 2)],
          (0, 0),
        ),
        'road.pelican.sw',
      );
    });

    test('equally busy junctions tiebreak in compass order', () {
      // Two Ts, north and south: north wins.
      expect(
        crossingAt(
          [(0, -2), (1, -1), (0, -1), (0, 0), (0, 1), (1, 1), (0, 2)],
          (0, 0),
        ),
        'road.pelican.ne',
      );
      // Two crosses, west and east: east wins.
      expect(
        crossingAt(
          [
            (-2, 0),
            (-2, -1),
            (-2, 1),
            (-1, 0),
            (0, 0),
            (1, 0),
            (1, -1),
            (1, 1),
            (2, 0),
          ],
          (0, 0),
        ),
        'road.pelican.se',
      );
    });
  });

  test('ambient pedestrian walk-cycle frames bundle as assets', () async {
    for (final character in ['a', 'b', 'c']) {
      for (final direction in ['NE', 'NW', 'SE', 'SW']) {
        for (final frame in [1, 2, 3, 4]) {
          final path =
              'assets/characters/'
              'char_${character}_walk_${direction}_f0$frame.png';
          expect(await rootBundle.load(path), isNotNull, reason: path);
        }
      }
    }
  });

  test('terrain samples the authored parcel map with ocean beyond it', () {
    final provider = ContentTerrainProvider(content.terrain);
    // Authored parcels return their base terrain, seed-independent.
    expect(provider.sample(const CellCoord(4, 4), 145).kind, TerrainKind.grass);
    expect(provider.sample(const CellCoord(4, 4), 999).kind, TerrainKind.grass);
    // The east and west authored water parcels.
    expect(provider.sample(const CellCoord(8, 4), 145).kind, TerrainKind.water);
    expect(
      provider.sample(const CellCoord(-4, 2), 145).kind,
      TerrainKind.water,
    );
    // Beyond the authored map is fog — the uncharted default.
    expect(provider.sample(const CellCoord(40, 2), 145).kind, TerrainKind.fog);
    expect(content.terrain.isOnMap(const ParcelCoord(1, 0)), isTrue);
    expect(content.terrain.isOnMap(const ParcelCoord(9, 9)), isFalse);
    expect(content.terrain.parcels, hasLength(49));
  });

  test('tile overrides parse, round-trip, and resolve over the base', () {
    // A tile map with an override inside a grass parcel and one
    // inside a water parcel, plus a stray on uncharted space.
    final terrain = TerrainContent.fromJson({
      'generatorVersion': 1,
      'parcels': {'0,0': 'grass', '1,0': 'water'},
      'tiles': {'3,4': 'water', '12,2': 'grass', '40,40': 'water'},
    });
    // Round-trip keeps the sparse map and its keys.
    final back = TerrainContent.fromJson(terrain.toJson());
    expect(back.tiles, {
      const CellCoord(3, 4): TerrainKind.water,
      const CellCoord(12, 2): TerrainKind.grass,
      const CellCoord(40, 40): TerrainKind.water,
    });
    // A map without overrides stays out of the JSON.
    expect(
      TerrainContent.fromJson({
        'generatorVersion': 1,
        'parcels': {'0,0': 'grass'},
      }).toJson().containsKey('tiles'),
      isFalse,
    );

    // Resolution: the override wins, absent keys fall back to the
    // parcel base, uncharted space stays fog even under a stray.
    final provider = ContentTerrainProvider(terrain);
    expect(provider.sample(const CellCoord(3, 4), 7).kind, TerrainKind.water);
    expect(provider.sample(const CellCoord(4, 4), 7).kind, TerrainKind.grass);
    expect(provider.sample(const CellCoord(12, 2), 7).kind, TerrainKind.grass);
    expect(provider.sample(const CellCoord(11, 2), 7).kind, TerrainKind.water);
    expect(provider.sample(const CellCoord(40, 40), 7).kind, TerrainKind.fog);

    // Validation: the stray tile outside authored parcels reports;
    // fog tiles report; a clean pair of overrides passes.
    final strayIssues = validateContentData(
      catalogue: content.catalogue,
      sprites: content.sprites,
      economy: content.economy,
      ambience: content.ambience,
      terrain: terrain,
    );
    expect(
      strayIssues.where((issue) => issue.message.contains('unauthored parcel')),
      isNotEmpty,
      reason: 'the stray tile at (40,40) is flagged',
    );
    expect(
      validateContentData(
        catalogue: content.catalogue,
        sprites: content.sprites,
        economy: content.economy,
        ambience: content.ambience,
        terrain: TerrainContent.fromJson({
          'generatorVersion': 1,
          'parcels': {'0,0': 'grass'},
          'tiles': {'3,4': 'water', '5,1': 'fog', '40,40': 'water'},
        }),
      ).where((issue) => issue.message.contains('cannot be fog')),
      isNotEmpty,
      reason: 'fog is not a tile-level kind',
    );
    expect(
      validateContentData(
        catalogue: content.catalogue,
        sprites: content.sprites,
        economy: content.economy,
        ambience: content.ambience,
        terrain: TerrainContent.fromJson({
          'generatorVersion': 1,
          'parcels': {'0,0': 'grass', '1,0': 'water'},
          'tiles': {'3,4': 'water', '12,2': 'grass'},
        }),
      ).where((issue) => issue.message.startsWith('Tile ')),
      isEmpty,
      reason: 'grass and water overrides inside authored parcels pass',
    );
  });

  test('authored fog parcels are a validation error, not a terrain', () {
    // Parsing stays lenient — old files still load — but authoring fog
    // is a mistake worth reporting: fog is not a terrain type, only
    // the look of uncharted space.
    final terrain = TerrainContent.fromJson(const {
      'generatorVersion': 1,
      'parcels': {'0,0': 'grass', '2,2': 'fog'},
    });
    final provider = ContentTerrainProvider(terrain);
    expect(
      provider.sample(const CellCoord(18, 18), 7).kind,
      TerrainKind.fog,
      reason: 'a legacy fog parcel still samples as fog',
    );
    expect(
      provider.sample(const CellCoord(40, 40), 7).kind,
      TerrainKind.fog,
      reason: 'unauthored parcels default to fog',
    );
    expect(
      validateContentData(
        catalogue: content.catalogue,
        sprites: content.sprites,
        economy: content.economy,
        ambience: content.ambience,
        terrain: terrain,
      ).any(
        (issue) =>
            issue.severity == 'error' &&
            issue.message.contains('Parcel 2,2 cannot be fog'),
      ),
      isTrue,
    );
  });
}

import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:citysim/world/road_sprite_resolver.dart';
import 'package:citysim/world/terrain_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'frozen_content.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ContentBundle content;

  setUpAll(() {
    content = frozenContent();
  });

  test('sprite side shifts validate within half the sprite width', () {
    // The seeded sprites carry no side shifts at all.
    final seeded = validateContentData(
      catalogue: content.catalogue,
      sprites: content.sprites,
      economy: content.economy,
      ambience: content.ambience,
      terrain: content.terrain,
      progression: content.progression,
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
        progression: content.progression,
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
        progression: content.progression,
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
        progression: content.progression,
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
        progression: content.progression,
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
      progression: content.progression,
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
    // (The shipped decks' own lift is pinned in
    // shipped_content_test.dart.)
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
        progression: content.progression,
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
      cars: content.ambience.cars,
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
        progression: content.progression,
      ).any(
        (issue) =>
            issue.severity == 'error' && issue.message.contains('Tile grid'),
      ),
      isTrue,
    );
  });

  test('the sway zoom gate parses, round-trips, and validates', () {
    // The authored gate: sway draws only at 0.75× camera scale and
    // closer — a content-tunable LOD switch, zero keeping the sway
    // at every zoom. (The shipped gate's own value is pinned in
    // shipped_content_test.dart.)
    expect(content.ambience.vegetationSway.minScale, 0.75);
    final fresh = VegetationSwayContent.fromJson(
      content.ambience.vegetationSway.toJson(),
    );
    expect(fresh.minScale, 0.75, reason: 'the gate round-trips');

    final bad = AmbienceContent(
      ambientTimeScale: content.ambience.ambientTimeScale,
      vegetationSway: VegetationSwayContent(
        maxAngleRadians: content.ambience.vegetationSway.maxAngleRadians,
        baseFrequency: content.ambience.vegetationSway.baseFrequency,
        frequencySteps: content.ambience.vegetationSway.frequencySteps,
        frequencyStep: content.ambience.vegetationSway.frequencyStep,
        minScale: -1,
      ),
      pedestrians: content.ambience.pedestrians,
      cars: content.ambience.cars,
      unownedLandWash: content.ambience.unownedLandWash,
      tileGrid: content.ambience.tileGrid,
    );
    expect(
      validateContentData(
        catalogue: content.catalogue,
        sprites: content.sprites,
        economy: content.economy,
        ambience: bad,
        terrain: content.terrain,
        progression: content.progression,
      ).any(
        (issue) =>
            issue.severity == 'error' &&
            issue.message.contains('sway zoom gate'),
      ),
      isTrue,
    );
  });

  test('construction is free by rule', () {
    // Buildings are gated by land, road access, and staged time —
    // never by money; coins buy parcels, roads, and bridges. A
    // priced model of any kind is a validation error; the shipped
    // catalogue's own zero prices are pinned in
    // shipped_content_test.dart.
    final priced = [
      for (final model in content.catalogue)
        if (model.id == 'street-lamp') model.copyWith(costCoins: 3) else model,
    ];
    expect(
      validateContentData(
        catalogue: priced,
        sprites: content.sprites,
        economy: content.economy,
        ambience: content.ambience,
        terrain: content.terrain,
        progression: content.progression,
      ).any(
        (issue) =>
            issue.severity == 'error' &&
            issue.message.contains('construction is free'),
      ),
      isTrue,
    );
  });

  test('the authored map can always be founded', () {
    // The founding claim needs a parcel the city hall can stand on
    // with its front road, so content validation requires the map to
    // offer at least one — an all-water map could never start a new
    // game. (The shipped map's own claimability is pinned in
    // shipped_content_test.dart.)
    final unfoundable = TerrainContent(
      generatorVersion: content.terrain.generatorVersion,
      parcels: {const ParcelCoord(0, 0): TerrainKind.water},
    );
    expect(
      validateContentData(
        catalogue: content.catalogue,
        sprites: content.sprites,
        economy: content.economy,
        ambience: content.ambience,
        terrain: unfoundable,
        progression: content.progression,
      ).any(
        (issue) =>
            issue.severity == 'error' &&
            issue.message.contains('room for the city hall'),
      ),
      isTrue,
    );
  });

  test('a homes-only town must be able to pay its upkeep from the floor', () {
    // The floor's design promise: a town of only homes always earns
    // its way back. The frozen bundle keeps it — 30% of the small
    // home's 500 tax is 150 against 100 upkeep — and a floor too
    // thin for a home's own upkeep warns.
    expect(
      validateContentData(
        catalogue: content.catalogue,
        sprites: content.sprites,
        economy: content.economy,
        ambience: content.ambience,
        terrain: content.terrain,
        progression: content.progression,
      ).where((issue) => issue.message.contains('homes-only')),
      isEmpty,
    );

    // A floor too thin for the small home's upkeep warns: a town of
    // only homes could never pay its upkeep.
    final thin = content.economy.copyWith(homeTaxUnemploymentFloorPercent: 10);
    final issues = validateContentData(
      catalogue: content.catalogue,
      sprites: content.sprites,
      economy: thin,
      ambience: content.ambience,
      terrain: content.terrain,
      progression: content.progression,
    );
    expect(
      issues.any(
        (issue) =>
            issue.severity == 'warning' &&
            issue.message.contains('small-home') &&
            issue.message.contains('homes-only'),
      ),
      isTrue,
      reason: '10% of the small home\'s 500 tax is 50, under its 100 upkeep',
    );
    // It warns, it does not error — balance is the content suite's job.
    expect(issues.where((issue) => issue.severity == 'error'), isEmpty);
  });

  test('progression milestones validate structure and floors', () {
    ProgressionContent withMilestones(List<Map<String, Object?>> raw) =>
        ProgressionContent.fromJson({'milestones': raw});

    // Structural errors: duplicate ids, non-increasing thresholds,
    // unknown and disabled models, a model in two milestones.
    expect(
      validateContentData(
        catalogue: content.catalogue,
        sprites: content.sprites,
        economy: content.economy,
        ambience: content.ambience,
        terrain: content.terrain,
        progression: withMilestones([
          {
            'id': 'a',
            'name': 'A',
            'population': 0,
            'models': ['small-home'],
          },
          {'id': 'a', 'name': 'Again', 'population': 5, 'models': const []},
        ]),
      ).any((issue) => issue.message.contains('Duplicate milestone')),
      isTrue,
    );
    expect(
      validateContentData(
        catalogue: content.catalogue,
        sprites: content.sprites,
        economy: content.economy,
        ambience: content.ambience,
        terrain: content.terrain,
        progression: withMilestones([
          {
            'id': 'a',
            'name': 'A',
            'population': 5,
            'models': ['small-home'],
          },
          {'id': 'b', 'name': 'B', 'population': 5, 'models': const []},
        ]),
      ).any((issue) => issue.message.contains('strictly above')),
      isTrue,
    );
    expect(
      validateContentData(
        catalogue: content.catalogue,
        sprites: content.sprites,
        economy: content.economy,
        ambience: content.ambience,
        terrain: content.terrain,
        progression: withMilestones([
          {
            'id': 'a',
            'name': 'A',
            'population': 0,
            'models': ['not-a-model'],
          },
        ]),
      ).any((issue) => issue.message.contains('unknown model')),
      isTrue,
    );
    expect(
      validateContentData(
        catalogue: content.catalogue,
        sprites: content.sprites,
        economy: content.economy,
        ambience: content.ambience,
        terrain: content.terrain,
        progression: withMilestones([
          {
            'id': 'a',
            'name': 'A',
            'population': 0,
            'models': ['small-home'],
          },
          {
            'id': 'b',
            'name': 'B',
            'population': 5,
            'models': ['small-home'],
          },
        ]),
      ).any((issue) => issue.message.contains('two milestones')),
      isTrue,
    );

    // Balance warnings, not errors: no home at the population-0
    // milestone is a dead new game (warned, pinned on the shipped
    // content by the content suite); a building in no milestone is
    // dead content, while a nature-capable decoration in none is
    // the legitimate not-part-of-progression bucket.
    final issues = validateContentData(
      catalogue: content.catalogue,
      sprites: content.sprites,
      economy: content.economy,
      ambience: content.ambience,
      terrain: content.terrain,
      progression: withMilestones([
        {
          'id': 'a',
          'name': 'A',
          'population': 0,
          'models': ['cafe'],
        },
      ]),
    );
    expect(
      issues.any(
        (issue) =>
            issue.severity == 'warning' &&
            issue.message.contains('residential model unlocks'),
      ),
      isTrue,
    );
    expect(
      issues
          .where((issue) => issue.severity == 'error')
          .any((issue) => issue.message.contains('milestone')),
      isFalse,
      reason: 'the missing starter home warns, it does not error',
    );
    expect(
      issues.any(
        (issue) =>
            issue.severity == 'warning' &&
            issue.message.contains('small-home') &&
            issue.message.contains('never placeable'),
      ),
      isTrue,
      reason: 'an unassigned building is dead content',
    );
    expect(
      issues.any((issue) => issue.message.contains('pine-tree')),
      isFalse,
      reason: 'an unassigned nature-capable decoration is legitimate',
    );
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
    // Sample cells the tile overrides have not painted — a bundle may
    // carry any number of them (parcel size 8).
    CellCoord baseCell(ParcelCoord parcel) {
      for (final cell in parcel.cells(8)) {
        if (!content.terrain.tiles.containsKey(cell)) return cell;
      }
      fail('every cell of $parcel carries a tile override');
    }

    // Authored parcels return their base terrain, seed-independent.
    final grass = baseCell(const ParcelCoord(0, 0));
    expect(provider.sample(grass, 145).kind, TerrainKind.grass);
    expect(provider.sample(grass, 999).kind, TerrainKind.grass);
    // The east and west authored water parcels.
    expect(
      provider.sample(baseCell(const ParcelCoord(1, 0)), 145).kind,
      TerrainKind.water,
    );
    expect(
      provider.sample(baseCell(const ParcelCoord(-1, 0)), 145).kind,
      TerrainKind.water,
    );
    // Beyond the authored map is fog — the uncharted default. The
    // frozen map's charted block spans x −3..6 and y −1..2 (40
    // parcels), so the probe sits in parcel (9,0), east of it. (The
    // shipped map's own size is pinned in shipped_content_test.dart.)
    expect(provider.sample(const CellCoord(72, 2), 145).kind, TerrainKind.fog);
    expect(content.terrain.isOnMap(const ParcelCoord(1, 0)), isTrue);
    expect(content.terrain.isOnMap(const ParcelCoord(9, 9)), isFalse);
    expect(content.terrain.parcels, hasLength(40));
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
      progression: content.progression,
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
        progression: content.progression,
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
        progression: content.progression,
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
        progression: content.progression,
      ).any(
        (issue) =>
            issue.severity == 'error' &&
            issue.message.contains('Parcel 2,2 cannot be fog'),
      ),
      isTrue,
    );
  });

  test('terrain nature rows validate model, terrain, and anchors', () {
    TerrainContent withProps(List<TerrainProp> props) => TerrainContent(
      generatorVersion: content.terrain.generatorVersion,
      parcels: content.terrain.parcels,
      tiles: content.terrain.tiles,
      props: props,
    );

    List<String> natureIssues(List<TerrainProp> props) => [
      for (final issue in validateContentData(
        catalogue: content.catalogue,
        sprites: content.sprites,
        economy: content.economy,
        ambience: content.ambience,
        terrain: withProps(props),
        progression: content.progression,
      ))
        if (issue.severity == 'error' && issue.message.contains('ature'))
          issue.message,
    ];

    // A sound row on starter grass passes clean.
    expect(
      natureIssues(const [
        TerrainProp(
          catalogueId: 'pine-tree',
          cell: CellCoord(2, 2),
          subtileX: 3,
          subtileY: 4,
        ),
      ]),
      isEmpty,
    );

    // Water refuses the row — the model needs land.
    expect(
      natureIssues(const [
        TerrainProp(
          catalogueId: 'pine-tree',
          cell: CellCoord(-6, 2),
          subtileX: 0,
          subtileY: 0,
        ),
      ]),
      everyElement(contains('cannot stand on water')),
    );

    // Unknown models and non-decoration models refuse too.
    expect(
      natureIssues(const [
        TerrainProp(
          catalogueId: 'unknown-tree',
          cell: CellCoord(2, 2),
          subtileX: 0,
          subtileY: 0,
        ),
      ]),
      isNotEmpty,
    );
    expect(
      natureIssues(const [
        TerrainProp(
          catalogueId: 'small-home',
          cell: CellCoord(2, 2),
          subtileX: 0,
          subtileY: 0,
        ),
      ]),
      isNotEmpty,
    );

    // Two rows never share a subtile.
    expect(
      natureIssues(const [
        TerrainProp(
          catalogueId: 'pine-tree',
          cell: CellCoord(2, 2),
          subtileX: 3,
          subtileY: 4,
        ),
        TerrainProp(
          catalogueId: 'rocks',
          cell: CellCoord(2, 2),
          subtileX: 3,
          subtileY: 4,
        ),
      ]),
      everyElement(contains('share the subtile')),
    );

    // Rows off the authored map refuse.
    expect(
      natureIssues(const [
        TerrainProp(
          catalogueId: 'pine-tree',
          cell: CellCoord(400, 400),
          subtileX: 0,
          subtileY: 0,
        ),
      ]),
      isNotEmpty,
    );
  });
}

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

  test('sprite facing offsets validate within half a tile', () {
    // The seeded sprites carry no out-of-range offsets.
    final seeded = validateContentData(
      catalogue: content.catalogue,
      sprites: content.sprites,
      economy: content.economy,
      ambience: content.ambience,
      terrain: content.terrain,
    );
    expect(
      seeded.where((issue) => issue.message.contains('facingOffset')),
      isEmpty,
    );

    // A sprite pushed past half a tile fails validation, and one inside
    // the range passes.
    final role = content.catalogue.first.assetRoles.first;
    final outOfRange = {
      ...content.sprites,
      role: content.sprites[role]!.copyWith(facingOffset: 0.75),
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
            issue.severity == 'error' && issue.message.contains('facingOffset'),
      ),
      isTrue,
    );
    final inRange = {
      ...content.sprites,
      role: content.sprites[role]!.copyWith(facingOffset: -0.5),
    };
    expect(
      validateContentData(
        catalogue: content.catalogue,
        sprites: inRange,
        economy: content.economy,
        ambience: content.ambience,
        terrain: content.terrain,
      ).where((issue) => issue.message.contains('facingOffset')),
      isEmpty,
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
    expect(content.ambience.pedestrians.spriteScale, closeTo(0.7, 0.001));
    expect(content.ambience.waterShimmer.bands, 6);
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
    // Beyond the authored map is open ocean.
    expect(
      provider.sample(const CellCoord(40, 2), 145).kind,
      TerrainKind.water,
    );
    expect(content.terrain.isOnMap(const ParcelCoord(1, 0)), isTrue);
    expect(content.terrain.isOnMap(const ParcelCoord(9, 9)), isFalse);
    expect(content.terrain.parcels, hasLength(49));
  });
}

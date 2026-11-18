/// Pins on the shipped content JSONs.
///
/// This suite asserts what the *data* files carry — seeded defaults,
/// findable maps, free decorations, milestone shape. It is the
/// content-side guard: these tests fail when a JSON drifts, not when
/// game code changes. Validation *rules* (synthetic bad content) live
/// with the game code in `parcel_world_content_test.dart`.
library;

import 'package:citysim/content/asset_content_source.dart';
import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:citysim/world/road_sprite_resolver.dart';
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

  test('the shipped map can always be founded and its props are free', () {
    // The founding purchase needs a parcel with five or more land
    // cells, so the shipped map must offer at least one.
    expect(
      content.terrain.parcels.keys.any(
        (coord) => content.terrain.landCellCount(coord) >= foundingLandCells,
      ),
      isTrue,
      reason: 'the shipped map has a findable founding parcel',
    );
    // Decorations are free by product rule — the one thing a new
    // settlement can spend on before its first road.
    for (final model in content.catalogue) {
      if (model.kind == StructureKind.decoration) {
        expect(model.costCoins, 0, reason: model.id);
      }
    }
    // The sway gate: sway draws only at 0.75× camera scale and closer.
    expect(content.ambience.vegetationSway.minScale, 0.75);
    // The parcel-mode claim tint: a muted slate, distinct from the
    // unowned wash's green.
    expect(content.ambience.claimedLandWash.alpha, 64);
    expect(content.ambience.claimedLandWash.colorRgb, const [130, 130, 145]);
  });

  test('the shipped progression is a complete, ordered milestone ladder', () {
    final milestones = content.progression.sorted;
    expect(milestones, hasLength(7));
    expect(
      [for (final milestone in milestones) milestone.population],
      [0, 15, 50, 120, 300, 800, 2000],
    );
    // The ladder is complete: every enabled model belongs to a
    // milestone or is legitimately nature-only (none are today).
    final assigned = {for (final milestone in milestones) ...milestone.models};
    final enabled = {for (final model in content.purchaseableModels) model.id};
    expect(enabled.difference(assigned), isEmpty, reason: 'no strays');
    expect(assigned.difference(enabled), isEmpty, reason: 'no ghosts');
    // The fresh-game floor: a home unlocks from the start.
    expect(milestones.first.models, contains('small-home'));
  });

  test('content seed snapshot holds the seeded defaults', () {
    // Snapshot guard: these values are the seeded defaults the dashboard
    // starts from — the original nine models, the promoted Buggy
    // Studio pack art, and the promoted props. Editing them in the
    // editor is expected; editing them by accident in the JSON is not.
    expect(content.catalogue, hasLength(40));
    final byId = {for (final model in content.catalogue) model.id: model};
    expect(byId['small-home']!.costCoins, 0);
    expect(byId['small-home']!.taxCoins, 500);
    expect(byId['small-home']!.upkeepCoins, 100);
    expect(byId['small-home']!.constructionStages, 2);
    expect(byId['small-home']!.population, 3);
    expect(
      content.progression.milestoneForModel('small-home')!.id,
      'homestead',
      reason: 'the cottage unlocks from the start',
    );
    expect(byId['cafe']!.costCoins, 0);
    expect(byId['cafe']!.netCoinsPerCheckIn, 1550);
    expect(byId['flower-garden']!.costCoins, 0);
    expect(byId['flower-garden']!.kind, StructureKind.decoration);
    expect(byId['flower-garden']!.population, 0);
    expect(byId['pine-tree']!.costCoins, 0);
    expect(byId['medium-home']!.costCoins, 0);
    expect(
      content.progression.milestoneForModel('medium-home')!.population,
      15,
    );
    expect(byId['fruit-market']!.costCoins, 0);
    expect(byId['community-clinic']!.costCoins, 0);
    expect(byId['community-clinic']!.upkeepCoins, 1500);
    expect(
      content.progression.milestoneForModel('community-clinic')!.population,
      50,
    );
    expect(byId['apartments']!.costCoins, 0);
    expect(byId['apartments']!.taxCoins, 6800);
    expect(byId['apartments']!.footprintColumns, 2);
    expect(byId['apartments']!.footprintRows, 2);
    expect(
      content.progression.milestoneForModel('apartments')!.population,
      300,
    );
    expect(byId['city-office']!.costCoins, 0);

    // Promoted pack art: representative snapshot of the new models.
    expect(byId['small-home']!.assetRoles, hasLength(6));
    expect(byId['medium-home']!.assetRoles, hasLength(5));
    expect(byId['city-office']!.assetRoles, hasLength(5));
    expect(byId['ice-cream-shop']!.kind, StructureKind.building);
    expect(
      content.progression.milestoneForModel('ice-cream-shop')!.id,
      'homestead',
    );
    expect(byId['large-home']!.costCoins, 0);
    expect(byId['large-home']!.assetRoles, hasLength(6));
    expect(content.progression.milestoneForModel('large-home')!.population, 50);
    expect(byId['warehouse']!.footprintColumns, 2);
    expect(byId['warehouse']!.subcategory, 'industrial');
    expect(byId['construction-site']!.kind, StructureKind.building);
    expect(byId['construction-site']!.population, 0);
    expect(content.progression.milestoneForModel('hospital')!.population, 2000);

    // Promoted props: representative snapshot of the decoration batch.
    expect(byId['common-tree']!.kind, StructureKind.decoration);
    expect(byId['common-tree']!.costCoins, 0);
    expect(byId['common-tree']!.assetRoles, hasLength(2));
    expect(byId['street-lamp']!.costCoins, 0);
    expect(byId['street-lamp']!.subcategory, 'streetside');
    expect(byId['traffic-light']!.costCoins, 0);
    expect(byId['rocks']!.assetRoles, hasLength(6));
    expect(byId['rocks']!.subcategory, 'rocks');
    expect(byId['tires']!.subcategory, 'clutter');
    expect(byId['wild-grass']!.costCoins, 0);

    // The founding stake was cut from 100k to 20k — a deliberate
    // tightening of the opening once whole-stretch roads and the
    // unemployment floor made the early game faster and safer.
    expect(content.economy.startingTreasuryCoins, 20000);
    expect(content.economy.roadTileCostCoins, 2500);
    expect(content.economy.bridgeTileCostCoins, 50000);
    expect(
      content.economy.parcelBaseCoins,
      15000,
      reason:
          'the flat part of the parcel price, before the population '
          'surcharge',
    );
    expect(content.economy.parcelPerPopulationCoins, 150);
    expect(content.economy.roadUpkeepCoinsPerTile, 10);
    expect(content.economy.bridgeUpkeepCoinsPerTile, 300);
    expect(content.economy.roadTaxCoinsPerTile, 0);
    expect(content.economy.bridgeTaxCoinsPerTile, 0);
    // Stage-2.1 seeds: waiting-list demand and contentment.
    expect(content.economy.migrationPercentPerCheckIn, 2);
    expect(content.economy.employmentPercentPerCheckIn, 5);
    expect(content.economy.waitingPopulationCapPercent, 10);
    expect(content.economy.unemploymentTolerancePercent, 10);
    expect(content.economy.jobPullPercentPerCheckIn, 10);
    expect(content.economy.contentmentFloorPercent, 30);
    // The unemployment floor — the soft-lock fix from the reviewer
    // playtest: homes pay at least this share of their levy with no
    // jobs, so a homes-only town can always earn its way back.
    expect(content.economy.homeTaxUnemploymentFloorPercent, 30);
    // Services are demanded exactly at the city milestone (300), so
    // the demand never arrives before the fire and police stations
    // that answer it unlock — the 250 gap was a measured income
    // valley (see docs/sim/economy-feel-report.md).
    expect(content.economy.serviceRequirementPopulation, 300);
    expect(content.economy.requiredServiceCategories, [
      'fire',
      'police',
      'health',
    ]);
    expect(byId['small-home']!.population, 3);
    expect(byId['apartments']!.population, 40);
    expect(byId['cafe']!.jobs, 8);
    expect(byId['tall-office']!.jobs, 300);
    expect(byId['fire-station']!.serviceCategory, 'fire');
    expect(byId['fire-station']!.serviceCapacity, 1200);
    expect(byId['community-clinic']!.serviceCategory, 'health');
    expect(byId['community-clinic']!.serviceCapacity, 400);
    expect(byId['hospital']!.serviceCategory, 'health');
    expect(byId['water-tower']!.serviceCategory, isNull);

    expect(content.ambience.ambientTimeScale, 1.0);
    // 0.6 draws a person at ~1.8 m on the 0.2 m/px scale ruler.
    expect(content.ambience.pedestrians.spriteScale, closeTo(0.6, 0.001));
    // Street life follows population: 20% of the live save's 254 is
    // the walker count the tuned ambience carries.
    expect(content.ambience.pedestrians.populationPercent, 20);
    // Traffic follows population too: ten types, percents summing
    // to one hundred, a sedan-heavy civilian mix, and colour
    // variants rolled per trip. Tuned down to 2% once population
    // began counting people — 10% of 254 was a parking lot.
    expect(content.ambience.cars.populationPercent, 2);
    expect(content.ambience.cars.minTripCells, 10);
    expect(content.ambience.cars.types, hasLength(9));
    expect(
      content.ambience.cars.types.fold(0, (sum, type) => sum + type.percent),
      100,
    );
    expect(
      content.ambience.cars.types
          .firstWhere((type) => type.id == 'sedan')
          .variants,
      const ['blue', 'white', 'red'],
    );
    // The E-W straight carries the painted traffic lanes (editor,
    // 2026-11): right-hand drive — eastbound rows 4-5, westbound
    // rows 2-3, and nothing painted for the cross directions.
    expect(content.sprite('road.straight.se')!.lanes['east-1'], const [
      0,
      0,
      0,
      0,
      255,
      255,
      0,
      0,
    ]);
    expect(content.sprite('road.straight.se')!.lanes['west-1'], const [
      0,
      0,
      255,
      255,
      0,
      0,
      0,
      0,
    ]);
    expect(content.sprite('road.straight.se')!.lanes['north-1'], isNull);
    // Render tuning is authored on the Vehicles page (2026-11),
    // so it grows with tuning; the invariant is that every entry
    // names a real type with in-range, well-named anchors.
    for (final entry in content.ambience.cars.render.entries) {
      expect(
        content.ambience.cars.types.any((type) => type.id == entry.key),
        isTrue,
        reason: 'render tuning "${entry.key}" names a vehicle type',
      );
      for (final anchor in entry.value.anchor.entries) {
        expect(
          const ['NE', 'NW', 'SE', 'SW'].contains(anchor.key),
          isTrue,
          reason: 'anchor direction "${anchor.key}" is valid',
        );
        expect(anchor.value.$1, inInclusiveRange(-0.5, 1.5));
        expect(anchor.value.$2, inInclusiveRange(-0.5, 1.5));
      }
    }
  });
}

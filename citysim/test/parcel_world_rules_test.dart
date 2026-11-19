import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/storage/sheet_tables.dart';
import 'package:citysim/storage/world_sheet_codec.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:citysim/world/terrain_provider.dart';
import 'package:citysim/world/world_content.dart';
import 'package:citysim/world/world_queries.dart';
import 'package:citysim/world/world_reducer.dart';
import 'package:citysim/world/world_rules.dart';
import 'package:citysim/world/world_state.dart';
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

  /// The untouched first minute of a new game: nothing owned, nothing
  /// built — the player has yet to choose a founding parcel.
  ParcelWorldState freshWorld() => newParcelWorldState(
    content: content,
    seed: 123456,
    today: DateTime.utc(2026, 11, 2),
  );

  /// A settled start: parcel (0,0) owned with its city hall (3×3,
  /// north of the road) and the hall's front road at (4,4) — the
  /// shape every town-building test begins from, assembled directly
  /// through the save codec so no coins, days, or events are spent
  /// reaching it. (The founding itself is covered from [freshWorld]
  /// above.) The road at (4,4) IS the hall's front road: the root of
  /// the connected network every test builds on.
  ParcelWorldState newWorld() => sheetTablesToWorld(
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

  /// The heartbeat: a simulated day passes and the town report runs
  /// — taxes, upkeep, then every in-flight project one stage.
  ParcelWorldState nextDay(ParcelWorldState world) =>
      checkInWorldForToday(advanceWorldDays(world, 1), content);

  /// What building tests mean by "the town's structures": everything
  /// standing except the founding hall the settled fixture carries.
  List<PlacedStructure> built(ParcelWorldState world) => [
    for (final structure in world.structures)
      if (structure.catalogueId != 'city-hall') structure,
  ];

  /// The pre-founding-era settled shape: parcel and road, no hall.
  /// Only the rejection test may build it — every valid town carries
  /// its hall.
  ParcelWorldState newWorldHallLess() => sheetTablesToWorld(
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

  /// Plans a road stretch and lets the next check-in land it whole.
  /// Call only when the stretch is the sole in-flight work: a
  /// check-in advances every project, not one.
  ParcelWorldState planAndSettleRoad(
    ParcelWorldState world, {
    required List<CellCoord> cells,
  }) {
    world = planRoadStretch(world, content, terrain, cells: cells);
    return nextDay(world);
  }

  /// Check-ins until no construction remains.
  ParcelWorldState settleAll(ParcelWorldState world) {
    while (world.constructions.isNotEmpty) {
      world = nextDay(world);
    }
    return world;
  }

  group('parcel-world bootstrap and clocks', () {
    test('a new game owns nothing and builds nothing', () {
      final world = freshWorld();

      expect(world.parcels, isEmpty);
      expect(world.roads, isEmpty);
      expect(world.structures, isEmpty);
      expect(world.props, isEmpty);
      expect(world.coins, content.economy.startingTreasuryCoins);
      expect(world.population, 0);
      expect(
        world.unlockedCatalogueIds,
        content.progression.modelsUnlockedThrough(
          content.progression.sorted.first,
        ),
        reason: 'starting unlocks are the from-start milestone',
      );
      expect(world.progressionMilestoneId, content.progression.sorted.first.id);
      expect(
        () => validateParcelWorldState(world, content, terrain),
        returnsNormally,
        reason: 'a zero-parcel save is a valid save',
      );
    });

    test('founding places the hall, its front road, and claims the parcel', () {
      var world = freshWorld();

      // Any charted parcel with room for the hall and its road: free,
      // no neighbour required — there is nothing to be adjacent to
      // yet. The hall is 3×3 facing south at (3,1), so its front road
      // lands at (4,4).
      final quote = quoteCityFounding(
        world,
        content,
        terrain,
        origin: const CellCoord(3, 1),
        facing: 'south',
      );
      expect(quote.parcel, const ParcelCoord(0, 0));
      expect(quote.frontCell, const CellCoord(4, 4));
      expect(quote.footprint.length, 9);
      expect(
        world.coins,
        content.economy.startingTreasuryCoins,
        reason: 'quoting never spends',
      );
      world = foundCity(
        world,
        content,
        terrain,
        origin: const CellCoord(3, 1),
        facing: 'south',
      );
      expect(world.parcels.single.coord, const ParcelCoord(0, 0));
      expect(world.parcels.single.pricePaid, 0);
      expect(world.coins, content.economy.startingTreasuryCoins);
      expect(world.roads.single.cell, const CellCoord(4, 4));
      expect(world.roads.single.pricePaid, 0);
      final hall = world.constructions.single;
      expect(hall.catalogueId, 'city-hall');
      expect(hall.facing, 'south');
      expect(
        world.events.last.kind,
        'city-founded',
        reason: 'founding is the town\'s first event',
      );
      expect(
        () => validateParcelWorldState(world, content, terrain),
        returnsNormally,
      );

      // The outside connection is live the moment founding lands:
      // the front road roots the network even while the hall rises.
      expect(connectedRoadCells(world, content), {const CellCoord(4, 4)});

      // The second parcel is a normal purchase: adjacent, priced by
      // the settlement's size.
      final second = quoteParcelPurchase(
        world,
        content,
        terrain,
        const ParcelCoord(0, 1),
      );
      expect(
        second.price,
        content.economy.parcelBaseCoins +
            content.economy.parcelPerPopulationCoins * world.population,
      );
      expect(
        () => quoteParcelPurchase(
          world,
          content,
          terrain,
          const ParcelCoord(4, 4),
        ),
        throwsA(isA<WorldRuleViolation>()),
        reason: 'a non-adjacent second parcel is refused',
      );

      // Land before the hall: nothing can be bought, because
      // founding is the hall's act — it claims its own parcel.
      expect(
        () => purchaseParcel(
          freshWorld(),
          content,
          terrain,
          const ParcelCoord(0, 0),
        ),
        throwsA(isA<WorldRuleViolation>()),
        reason: 'an unfounded city cannot buy land',
      );

      // The hall and its road need dry land, and both must fit inside
      // the one parcel founding claims.
      final waterParcel = content.terrain.parcels.entries
          .firstWhere((entry) => entry.value == TerrainKind.water)
          .key;
      final waterOrigin = CellCoord(
        waterParcel.x * 8 + 3,
        waterParcel.y * 8 + 1,
      );
      expect(
        () => quoteCityFounding(
          freshWorld(),
          content,
          terrain,
          origin: waterOrigin,
          facing: 'south',
        ),
        throwsA(isA<WorldRuleViolation>()),
        reason: 'the hall refuses open water',
      );
      expect(
        () => quoteCityFounding(
          freshWorld(),
          content,
          terrain,
          origin: const CellCoord(6, 6),
          facing: 'south',
        ),
        throwsA(isA<WorldRuleViolation>()),
        reason: 'the hall and its road must fit within one parcel',
      );
      // Not only open water: a mostly-drowned parcel with one land
      // cell fails the same buildability bar. A synthetic map pins
      // this regardless of what the authored terrain carries.
      final sparseLand = ContentTerrainProvider(
        TerrainContent(
          generatorVersion: content.terrain.generatorVersion,
          parcels: {const ParcelCoord(0, 0): TerrainKind.grass},
          tiles: {
            for (final cell in const ParcelCoord(0, 0).cells())
              if (cell != const CellCoord(0, 0)) cell: TerrainKind.water,
          },
        ),
      );
      expect(
        sparseLand.natureProps,
        isEmpty,
        reason: 'the synthetic map carries no nature',
      );
      expect(
        () => quoteCityFounding(
          freshWorld(),
          content,
          sparseLand,
          origin: const CellCoord(0, 0),
          facing: 'south',
        ),
        throwsA(isA<WorldRuleViolation>()),
        reason: 'a drowned parcel cannot host the hall',
      );
      // Another city's claim is as final as ownership: founding
      // refuses a parcel already taken.
      expect(
        () => quoteCityFounding(
          freshWorld(),
          content,
          terrain,
          origin: const CellCoord(3, 1),
          facing: 'south',
          claimedParcels: {const ParcelCoord(0, 0)},
        ),
        throwsA(isA<WorldRuleViolation>()),
        reason: 'another city has claimed that parcel',
      );
    });

    test('milestones cross once per check-in, named, and never re-lock', () {
      // A founded town with one home, then a population jump through
      // two milestones in one step — both cross together, each with
      // one named event.
      var world = grantWorldDebugCoins(newWorld(), 30);
      world = _buildCottage(
        world,
        content,
        terrain,
        const CellCoord(3, 4),
        nextDay,
      );
      world = world.copyWith(population: 60, employedPopulation: 60);
      // The cottage's settling check-ins consumed the founding day;
      // cross on the next one.
      world = nextDay(world);
      final crossed = world.events
          .where((event) => event.kind == 'milestone-reached')
          .toList();
      expect(crossed.map((event) => event.payload['milestoneId']), [
        'hamlet',
        'village',
      ], reason: 'both crossed milestones report, in order');
      expect(crossed.first.description, contains('Hamlet reached'));
      expect(world.progressionMilestoneId, 'village');
      expect(world.progressionMilestonePopulation, 50);
      expect(
        world.unlockedCatalogueIds,
        containsAll(['medium-home', 'community-clinic']),
      );
      expect(world.unlockedCatalogueIds, isNot(contains('church')));

      // The population dips below both thresholds: nothing re-locks,
      // in the session and across a save round-trip — the reload
      // reads the stored high-water milestone, never raw population.
      world = world.copyWith(population: 3, employedPopulation: 3);
      expect(world.unlockedCatalogueIds, contains('community-clinic'));
      final reloaded = sheetTablesToWorld(
        worldToSheetTables(world),
        content: content,
        terrainProvider: terrain,
      );
      expect(reloaded.progressionMilestoneId, 'village');
      expect(
        reloaded.unlockedCatalogueIds,
        contains('community-clinic'),
        reason: 'a reload keeps the high-water, not the population',
      );
      expect(
        () => validateParcelWorldState(reloaded, content, terrain),
        returnsNormally,
      );
      // A further check-in at the dipped population crosses nothing.
      final afterDip = checkInWorldForToday(
        advanceWorldDays(reloaded, 1),
        content,
      );
      expect(
        afterDip.events
            .where((event) => event.kind == 'milestone-reached')
            .isEmpty,
        isTrue,
      );
    });

    test(
      'check-in is explicit and idempotent; advancing days never funds work',
      () {
        var world = newWorld();
        world = checkInWorldForToday(world, content);
        // An empty town still pays its one road's upkeep: the report
        // is the whole economy now, and no coin is granted.
        expect(world.coins, content.economy.startingTreasuryCoins - 10);
        final report = world.events.lastWhere((e) => e.kind == 'check-in');
        expect(report.payload['taxes'], 0);
        expect(report.payload['upkeep'], 10);
        expect(report.payload['upkeepShortfall'], 0);
        expect(checkInWorldForToday(world, content), same(world));

        world = advanceWorldDays(world, 1);
        expect(
          world.coins,
          content.economy.startingTreasuryCoins - 10,
          reason: 'a day advance does not check in',
        );
        world = checkInWorldForToday(world, content);
        expect(world.coins, content.economy.startingTreasuryCoins - 20);

        final constructionDay = world.constructionDay;
        world = setWorldCalendarDate(
          world,
          world.simulatedDate.subtract(const Duration(days: 3)),
        );
        expect(world.constructionDay, constructionDay);
        expect(canCheckInWorldToday(world), isFalse);
        expect(checkInWorldForToday(world, content), same(world));
        expect(world.coins, content.economy.startingTreasuryCoins - 20);
      },
    );

    test('rewinding cannot backfill an uncredited earlier day', () {
      var world = newWorld();
      world = advanceWorldDays(world, 5);
      world = checkInWorldForToday(world, content);
      final afterReport = world.coins;
      world = setWorldCalendarDate(
        world,
        world.simulatedDate.subtract(const Duration(days: 4)),
      );

      expect(canCheckInWorldToday(world), isFalse);
      expect(checkInWorldForToday(world, content), same(world));
      expect(world.coins, afterReport);
    });
  });

  group('construction projects and staged work', () {
    test(
      'road plans are upfront purchases that land whole the next check-in',
      () {
        var world = grantWorldDebugCoins(newWorld(), 5);
        world = planRoadStretch(
          world,
          content,
          terrain,
          cells: const [CellCoord(5, 4), CellCoord(6, 4)],
        );
        final project = world.constructions.single;
        expect(project.kind, WorldConstructionKind.road);
        expect(
          world.coins,
          5 +
              content.economy.startingTreasuryCoins -
              2 * content.economy.roadTileCostCoins,
          reason: 'the whole stretch is paid upfront',
        );
        expect(world.roads, hasLength(1));
        // A second stretch plans while the first is in flight — roads
        // never block each other.
        world = planRoadStretch(
          world,
          content,
          terrain,
          cells: const [CellCoord(3, 4)],
        );
        expect(world.constructions, hasLength(2));

        world = advanceWorldDays(world, 30);
        expect(world.roads, hasLength(1), reason: 'days never build anything');

        // One check-in lays every tile of every stretch, whatever
        // their lengths — the whole street arrives the day after its
        // plan, so a stack of single-tile plans buys no extra speed.
        world = nextDay(world);
        expect(world.roads, hasLength(4));
        expect(
          world.roads.any((road) => road.cell == const CellCoord(5, 4)),
          isTrue,
        );
        expect(
          world.roads.any((road) => road.cell == const CellCoord(6, 4)),
          isTrue,
          reason: 'the long stretch lands whole',
        );
        expect(
          world.roads.any((road) => road.cell == const CellCoord(3, 4)),
          isTrue,
          reason: 'every in-flight stretch lands together',
        );
        expect(
          world.constructions.where(
            (job) => job.roadCells.contains(const CellCoord(5, 4)),
          ),
          isEmpty,
          reason: 'the stretch settles on the check-in after its plan',
        );
        // The plans were paid upfront (pinned above); the ledger also
        // carries each check-in's road upkeep now.
        expect(
          world.events.where((event) => event.kind == 'road-project-complete'),
          isNotEmpty,
        );
        validateParcelWorldState(world, content, terrain);
      },
    );

    test(
      'building sites are free plans that advance one stage per check-in',
      () {
        var world = newWorld();
        world = startStructureConstruction(
          world,
          content,
          terrain,
          catalogueId: 'small-home',
          origin: const CellCoord(3, 4),
        );
        final project = world.constructions.single;
        expect(project.kind, WorldConstructionKind.structure);
        expect(project.stagesDone, 0);
        expect(project.population, 3);
        expect(world.coins, content.economy.startingTreasuryCoins);
        expect(built(world), isEmpty);
        expect(world.population, 0);
        // Concurrency is unlimited (the builder cap was removed
        // 2026-11-16): a second site plans fine while the first is
        // still rising — coins, land, and staged time are the only
        // limits. Planned on a throwaway state so the staged-count
        // assertions below keep tracking the single cottage.
        final withSecond = startStructureConstruction(
          world,
          content,
          terrain,
          catalogueId: 'small-home',
          origin: const CellCoord(5, 4),
        );
        expect(
          withSecond.constructions,
          hasLength(2),
          reason: 'any number of sites may rise at once',
        );

        world = advanceWorldDays(world, 14);
        expect(world.constructions.single.stagesDone, 0);
        expect(built(world), isEmpty, reason: 'days never build anything');

        world = nextDay(world);
        expect(world.constructions.single.stagesDone, 1);
        expect(built(world), isEmpty);
        world = nextDay(world);

        expect(built(world).single.catalogueId, 'small-home');
        expect(built(world).single.population, 3);
        expect(world.population, 1);
        expect(
          world.constructions,
          isEmpty,
          reason: 'completion settles the project',
        );
        validateParcelWorldState(world, content, terrain);
      },
    );

    test('decorations place instantly and free', () {
      var world = grantWorldDebugCoins(newWorld(), 2);
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'flower-garden',
        origin: const CellCoord(2, 2),
      );

      expect(
        world.coins,
        2 + content.economy.startingTreasuryCoins,
        reason: 'props are free in the staged economy',
      );
      expect(built(world), isEmpty);
      expect(world.props.single.catalogueId, 'flower-garden');
      expect(
        content.structure('flower-garden')!.assetRoles,
        contains(world.props.single.assetRole),
        reason: 'the rolled variant must be one of the model\'s roles',
      );
      expect(world.constructions, isEmpty);
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'small-home',
        origin: const CellCoord(3, 4),
      );
      expect(world.constructions, hasLength(1));
      validateParcelWorldState(world, content, terrain);
    });

    test('promoted prop decorations place instantly with rolled variants', () {
      var world = grantWorldDebugCoins(newWorld(), 8);
      for (final (index, catalogueId) in [
        'street-lamp',
        'rocks',
        'common-tree',
      ].indexed) {
        world = startStructureConstruction(
          world,
          content,
          terrain,
          catalogueId: catalogueId,
          origin: CellCoord(2 + index, 6),
        );
      }

      final placed = world.props;
      expect(placed, hasLength(3));
      for (final catalogueId in ['street-lamp', 'rocks', 'common-tree']) {
        final prop = placed.singleWhere(
          (prop) => prop.catalogueId == catalogueId,
        );
        expect(
          content.structure(catalogueId)!.assetRoles,
          contains(prop.assetRole),
          reason: 'the rolled variant must be one of the model\'s roles',
        );
      }
      // No construction project for any of them, and none costs a coin.
      expect(world.constructions, isEmpty);
      expect(world.coins, 8 + content.economy.startingTreasuryCoins);
      validateParcelWorldState(world, content, terrain);
    });

    test('placements roll sprite variants deterministically', () {
      var world = grantWorldDebugCoins(newWorld(), 30);
      // Two cottages fit beside the starter road (the hall owns the
      // north side); extend the road south, then place four more
      // beside it for six rolls of the six-variant cottage.
      final nearRoad = [const CellCoord(3, 4), const CellCoord(5, 4)];
      final rolled = <String?>[];
      for (final origin in nearRoad) {
        world = startStructureConstruction(
          world,
          content,
          terrain,
          catalogueId: 'small-home',
          origin: origin,
        );
        rolled.add(world.constructions.single.assetRole);
        world = settleAll(world);
      }
      world = planAndSettleRoad(
        world,
        cells: const [CellCoord(4, 5), CellCoord(4, 6)],
      );
      for (final origin in [
        const CellCoord(3, 5),
        const CellCoord(5, 5),
        const CellCoord(3, 6),
        const CellCoord(5, 6),
      ]) {
        world = startStructureConstruction(
          world,
          content,
          terrain,
          catalogueId: 'small-home',
          origin: origin,
        );
        rolled.add(world.constructions.single.assetRole);
        world = settleAll(world);
      }

      // Six placements of a six-variant model should exercise more than
      // one variant, every structure keeps its rolled role, and the same
      // seed replays the same sequence.
      expect(rolled.length, greaterThan(1));
      final structureRoles = built(world).map((s) => s.assetRole).toList();
      expect(
        built(world).every(
          (structure) => content
              .structure('small-home')!
              .assetRoles
              .contains(structure.assetRole),
        ),
        isTrue,
      );

      final replay = grantWorldDebugCoins(newWorld(), 30);
      var replayed = replay;
      final replayRoles = <String?>[];
      for (final origin in nearRoad) {
        replayed = startStructureConstruction(
          replayed,
          content,
          terrain,
          catalogueId: 'small-home',
          origin: origin,
        );
        replayRoles.add(replayed.constructions.single.assetRole);
        replayed = settleAll(replayed);
      }
      replayed = planAndSettleRoad(
        replayed,
        cells: const [CellCoord(4, 5), CellCoord(4, 6)],
      );
      replayed = startStructureConstruction(
        replayed,
        content,
        terrain,
        catalogueId: 'small-home',
        origin: const CellCoord(3, 5),
      );
      replayRoles.add(replayed.constructions.single.assetRole);
      expect(replayRoles, rolled.take(3), reason: 'same seed, same rolls');

      final decoded = sheetTablesToWorld(
        worldToSheetTables(world),
        content: content,
        terrainProvider: terrain,
      );
      expect(
        built(decoded).map((s) => s.assetRole).toList(),
        structureRoles,
        reason: 'variant snapshots survive the sheet round-trip',
      );
    });

    test('buildings larger than 1x1 need a road along a whole side', () {
      // A 2×2 footprint at (4,5) touches the starter road only at its
      // north-west corner cell (4,4): one adjacent road is not
      // frontage for a multi-cell building.
      var world = grantWorldDebugCoins(newWorld(), 10);
      final apartments = content.structure('apartments')!;
      final footprint = structureFootprint(apartments, const CellCoord(4, 5));
      expect(
        WorldQueries(world, terrain).buildingHasRoadAccess(footprint),
        isFalse,
        reason: 'a single corner-touching road is not a frontage',
      );
      expect(
        () => quoteStructurePlacement(
          world,
          content,
          terrain,
          catalogueId: 'apartments',
          origin: const CellCoord(4, 5),
        ),
        throwsA(isA<WorldRuleViolation>()),
      );

      // The north side is (4,4) and (5,4): the starter road already
      // runs at (4,4), and paving (5,4) completes the frontage.
      world = planAndSettleRoad(world, cells: const [CellCoord(5, 4)]);
      expect(
        WorldQueries(world, terrain).buildingHasRoadAccess(footprint),
        isTrue,
        reason: 'a road running along the full north side is frontage',
      );

      // One-cell buildings keep the any-adjacent-road rule: the same
      // corner touch is plenty for a cottage.
      expect(
        WorldQueries(world, terrain).buildingHasRoadAccess(
          structureFootprint(
            content.structure('small-home')!,
            const CellCoord(5, 5),
          ),
        ),
        isTrue,
      );
    });

    test('building facings follow the adjacent road side', () {
      // The starter road sits at (4,4): grid east of (3,4), north of
      // (4,5), and west of (5,4). The saved facing is the bordering
      // road side itself. (The hall owns the road's north flank.)
      var world = grantWorldDebugCoins(newWorld(), 30);
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'small-home',
        origin: const CellCoord(3, 4),
      );
      expect(world.constructions.single.facing, 'east');

      world = settleAll(world);
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'small-home',
        origin: const CellCoord(4, 5),
      );
      expect(world.constructions.single.facing, 'north');
      expect(
        () => validateParcelWorldState(world, content, terrain),
        returnsNormally,
      );
    });

    test('facings swap only while roads border both art variants', () {
      var world = grantWorldDebugCoins(newWorld(), 30);
      // A single-side plan is fixed: the road east of (3,4) is its only
      // frontage.
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'small-home',
        origin: const CellCoord(3, 4),
      );
      final fixedProject = world.constructions.single;
      expect(
        () => swapStructureFacing(
          world,
          content,
          terrain,
          projectId: fixedProject.id,
        ),
        throwsA(isA<WorldRuleViolation>()),
      );
      world = settleAll(world);

      // Grow a crossroads so (6,5) and (5,6) each see roads on both
      // art variants: (6,5) has its north (6,4) — the left variant —
      // and west (5,5) — the right; (5,6) has its north (5,5) and
      // west (4,6). Each stretch is planned and settled before the
      // next is drawn.
      world = planAndSettleRoad(
        world,
        cells: const [CellCoord(4, 5), CellCoord(5, 5)],
      );
      world = planAndSettleRoad(world, cells: const [CellCoord(5, 4)]);
      world = planAndSettleRoad(world, cells: const [CellCoord(6, 4)]);
      world = planAndSettleRoad(world, cells: const [CellCoord(4, 6)]);

      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'small-home',
        origin: const CellCoord(6, 5),
      );
      final project = world.constructions.single;
      expect(project.facing, 'north', reason: 'the left-variant side wins');

      world = swapStructureFacing(
        world,
        content,
        terrain,
        projectId: project.id,
      );
      expect(world.constructions.single.facing, 'west');
      world = settleAll(world);

      // The player's pre-placement choice is honoured on both variants.
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'small-home',
        origin: const CellCoord(5, 6),
        preferredFacing: 'west',
      );
      expect(world.constructions.single.facing, 'west');
      world = settleAll(world);

      expect(
        () => validateParcelWorldState(world, content, terrain),
        returnsNormally,
      );

      // The chosen sides survive the sheet round-trip.
      final decoded = sheetTablesToWorld(
        worldToSheetTables(world),
        content: content,
        terrainProvider: terrain,
      );
      expect(
        decoded.structures.map((s) => s.facing).toList(),
        world.structures.map((s) => s.facing).toList(),
        reason: 'door-side snapshots survive the sheet round-trip',
      );
    });

    test('population gates unlock models', () {
      // Content-driven progression: a town grown past the Hamlet
      // milestone the real way — homes and jobs in balance — with
      // the unlock grants coming through load-time reconciliation.
      var world = grantWorldDebugCoins(newWorld(), 30);
      world = _buildCottage(
        world,
        content,
        terrain,
        const CellCoord(3, 4),
        nextDay,
      );
      world = world.copyWith(
        unlockedCatalogueIds: {...world.unlockedCatalogueIds, 'fruit-market'},
      );
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'fruit-market',
        origin: const CellCoord(4, 5),
      );
      world = settleAll(world);
      // A settled, employed town grown past Hamlet the way play
      // would — homes and jobs in balance.
      world = world.copyWith(population: 20, employedPopulation: 20);
      expect(world.population, 20);
      final reconciled = reconcileWorldProgression(world, content);
      expect(reconciled.unlockedCatalogueIds, contains('medium-home'));
      expect(reconciled.unlockedCatalogueIds, contains('fruit-market'));
      expect(
        reconciled.unlockedCatalogueIds,
        isNot(contains('community-clinic')),
      );
      validateParcelWorldState(reconciled, content, terrain);
    });

    test('reconciliation grants unlocks only upward', () {
      var world = grantWorldDebugCoins(newWorld(), 9);
      world = _buildCottage(
        world,
        content,
        terrain,
        const CellCoord(3, 4),
        nextDay,
      );
      world = world.copyWith(population: 3, employedPopulation: 3);
      expect(world.population, 3);

      // Simulate lowered content thresholds: a hand-built variant of
      // the bundle where the Hamlet milestone sits at population 2.
      final hamlet = content.progression.byId('hamlet')!;
      final lowered = ContentBundle(
        manifest: content.manifest,
        terrain: content.terrain,
        catalogue: content.catalogue,
        sprites: content.sprites,
        economy: content.economy,
        ambience: content.ambience,
        progression: ProgressionContent(
          milestones: [
            for (final milestone in content.progression.milestones)
              milestone.id == hamlet.id
                  ? MilestoneDefinition(
                      id: milestone.id,
                      name: milestone.name,
                      population: 2,
                      models: milestone.models,
                    )
                  : milestone,
          ],
        ),
      );

      final reconciled = reconcileWorldProgression(world, lowered);
      expect(reconciled.unlockedCatalogueIds, contains('medium-home'));
      expect(reconciled.progressionMilestoneId, 'hamlet');
      expect(
        reconcileWorldProgression(reconciled, lowered),
        same(reconciled),
        reason: 'reconciliation is idempotent',
      );
      // The original content still validates: unlocks never go down.
      validateParcelWorldState(reconciled, content, terrain);
    });
  });

  group('demand, occupancy, and contentment', () {
    test('the founding rhythm: home, shop, home', () {
      var world = newWorld();
      // A fresh town's waiting list grows from day one — population
      // zero is vacuously full and fully employed.
      world = nextDay(world);
      expect(world.waitingPopulation, 1, reason: 'the vacuous kickstart');
      expect(world.population, 0);

      // The cottage completes and receives today's arrival — but
      // with no jobs, its citizens are unemployed and pay no tax.
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
      var report = world.events.lastWhere((e) => e.kind == 'check-in');
      expect(report.payload['populationArrived'], 1);
      expect(
        report.payload['taxes'],
        0,
        reason: 'an unemployed citizen pays nothing',
      );

      // A shop opens and employs the family; the list refills the
      // same check-in — the town is full and fully employed again.
      world = world.copyWith(
        unlockedCatalogueIds: {...world.unlockedCatalogueIds, 'fruit-market'},
      );
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'fruit-market',
        origin: const CellCoord(4, 5),
      );
      world = nextDay(world);
      world = nextDay(world);
      expect(world.employedPopulation, 1);
      expect(world.waitingPopulation, 1, reason: 'a prosperous town attracts');
      report = world.events.lastWhere((e) => e.kind == 'check-in');
      expect(report.payload['positionsStaffed'], 1);

      // The second home completes and newcomers arrive into it.
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'small-home',
        origin: const CellCoord(5, 4),
      );
      world = nextDay(world);
      world = nextDay(world);
      expect(world.population, 4);
      validateParcelWorldState(world, content, terrain);
    });

    test('tolerance admits one jobless family, then gates migration', () {
      var world = newWorld();
      world = _buildCottage(
        world,
        content,
        terrain,
        const CellCoord(3, 4),
        nextDay,
      );
      expect(world.population, 1);
      expect(
        world.waitingPopulation,
        1,
        reason:
            'tolerance floors at one, so the list refills '
            'behind the first jobless family',
      );

      // The second family exhausts the list; the third home finds
      // nobody waiting — unemployment is now above tolerance and
      // migration pauses until jobs exist.
      world = _buildCottage(
        world,
        content,
        terrain,
        const CellCoord(5, 4),
        nextDay,
      );
      world = _buildCottage(
        world,
        content,
        terrain,
        const CellCoord(4, 5),
        nextDay,
      );
      expect(world.population, 2);
      expect(world.waitingPopulation, 0);
      expect(world.unemployment, 2);
      final ledger = townLedger(world, content);
      expect(ledger.residentialVacancy, 7);
      expect(ledger.employmentDemand, 2);
    });

    test('vacant buildings pay no tax but full upkeep', () {
      var world = grantWorldDebugCoins(newWorld(), 100);
      // A café with no population to employ: it completes, staffs
      // nothing, earns nothing, and drains upkeep forever.
      world = planAndSettleRoad(
        world,
        cells: const [CellCoord(5, 4), CellCoord(6, 4), CellCoord(7, 4)],
      );
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'cafe',
        origin: const CellCoord(6, 5),
      );
      world = nextDay(world);
      world = nextDay(world);
      expect(world.population, 0);
      expect(world.employedPopulation, 0);
      final cafe = content.structure('cafe')!;
      final before = world.coins;
      world = nextDay(world);
      final report = world.events.lastWhere((e) => e.kind == 'check-in');
      expect(
        report.payload['taxes'],
        0,
        reason: 'a café with no staff earns nothing',
      );
      expect(
        report.payload['upkeep'],
        cafe.upkeepCoins + 40,
        reason:
            'full upkeep plus four road tiles — the '
            'anti-shop-farming guard',
      );
      expect(world.coins, before - cafe.upkeepCoins - 40);
    });

    test('the town reports its physical footprint', () {
      // A fresh world: one 8×8 parcel, the founding road tile, and
      // the 3×3 city hall.
      var world = newWorld();
      expect(world.ownedTileCount, 64);
      expect(
        world.builtTileCount,
        10,
        reason: 'the founding road plus the hall',
      );

      // A cottage adds its one footprint tile to built-up land,
      // never to the limits.
      world = _buildCottage(
        world,
        content,
        terrain,
        const CellCoord(3, 4),
        nextDay,
      );
      expect(world.ownedTileCount, 64);
      expect(world.builtTileCount, 11);

      // Road tiles count as built-up land too.
      world = planAndSettleRoad(
        world,
        cells: const [CellCoord(3, 5), CellCoord(3, 6)],
      );
      expect(world.builtTileCount, 13);
    });

    test('service coverage scales contentment, floored at 30 percent', () {
      // A compact variant of the content with an early service
      // threshold, so the town already demands coverage.
      final demanding = ContentBundle(
        manifest: content.manifest,
        terrain: content.terrain,
        catalogue: content.catalogue,
        sprites: content.sprites,
        economy: content.economy.copyWith(serviceRequirementPopulation: 2),
        ambience: content.ambience,
        progression: content.progression,
      );
      var world = newWorld();
      world = _buildCottage(
        world,
        content,
        terrain,
        const CellCoord(3, 4),
        nextDay,
      );
      world = world.copyWith(
        unlockedCatalogueIds: {...world.unlockedCatalogueIds, 'fruit-market'},
      );
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'fruit-market',
        origin: const CellCoord(4, 5),
      );
      world = nextDay(world);
      world = nextDay(world);
      // The street extends east while its flank is still open — the
      // second cottage then lines the extension at (6,5).
      world = planAndSettleRoad(
        world,
        cells: const [CellCoord(5, 4), CellCoord(6, 4), CellCoord(7, 4)],
      );
      world = _buildCottage(
        world,
        content,
        terrain,
        const CellCoord(6, 5),
        nextDay,
      );
      expect(world.population, 4);
      expect(
        world.employedPopulation,
        4,
        reason: 'the market employs every citizen',
      );

      // No services at all: coverage zero across the board and
      // contentment rests on the floor.
      final noServices = townLedger(world, demanding);
      expect(noServices.coverage['fire'], 0.0);
      expect(noServices.coverage['police'], 0.0);
      expect(noServices.coverage['health'], 0.0);
      expect(
        noServices.contentment,
        demanding.economy.contentmentFloorPercent,
        reason: 'no coverage at all hits the floor',
      );

      // Contentment is appeal, never a tax collector: the same
      // primed town (waiting list 5, two beds open) checks in under
      // a content economy (no service categories — contentment 100)
      // and under the demanding one (contentment 30). Full appeal
      // moves a resident; the unhappy town stalls — stagnation,
      // not ruin.
      final contentEconomy = ContentBundle(
        manifest: content.manifest,
        terrain: content.terrain,
        catalogue: content.catalogue,
        sprites: content.sprites,
        economy: content.economy.copyWith(
          serviceRequirementPopulation: 2,
          requiredServiceCategories: const [],
        ),
        ambience: content.ambience,
        progression: content.progression,
      );
      final primed = world.copyWith(waitingPopulation: 5);
      int arrivedWith(ContentBundle bundle) {
        final played = checkInWorldForToday(
          advanceWorldDays(primed, 1),
          bundle,
        );
        return (played.events
                        .lastWhere((event) => event.kind == 'check-in')
                        .payload['populationArrived']
                    as num?)
                ?.toInt() ??
            0;
      }

      expect(
        arrivedWith(contentEconomy),
        1,
        reason: 'full appeal: the migration budget moves a resident',
      );
      expect(
        arrivedWith(demanding),
        0,
        reason: 'the contentment floor stalls arrivals — stagnation, not ruin',
      );

      // A fire station south of an eastward road covers the town:
      // fire climbs to full, contentment rises off the floor but
      // stays capped by the missing categories — the average.
      world = world.copyWith(
        unlockedCatalogueIds: {...world.unlockedCatalogueIds, 'fire-station'},
      );
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'fire-station',
        origin: const CellCoord(6, 2),
      );
      world = settleAll(world);
      final withFire = townLedger(world, demanding);
      expect(withFire.coverage['fire'], 1.0);
      expect(withFire.contentment, greaterThan(noServices.contentment));
      expect(
        withFire.contentment,
        lessThan(100),
        reason: 'police and health are still missing',
      );
      // Same town, different contentment, same levy — the
      // multiplier is gone from taxes entirely.
      expect(
        townLedger(world, contentEconomy).taxes,
        withFire.taxes,
        reason: 'contentment scales arrivals, never taxes',
      );
      // And the station's jobs never enter the levy: demolishing it
      // changes upkeep and coverage, not one coin of tax.
      final station = world.structures.firstWhere(
        (structure) => structure.catalogueId == 'fire-station',
      );
      final withoutStation = demolishStructure(
        world,
        content,
        structureId: station.id,
      );
      expect(
        townLedger(withoutStation, demanding).taxes,
        withFire.taxes,
        reason: 'civic jobs are appeal, not levy denominators',
      );
      validateParcelWorldState(world, content, terrain);
    });

    test('only employed people pay, at the aggregate rates', () {
      var world = newWorld();
      // One part-occupied home plus one staffed market: with one
      // citizen employed of three housed and one position staffed
      // of six, the home pays a third of its tax and the market a
      // sixth of its.
      world = _buildCottage(
        world,
        content,
        terrain,
        const CellCoord(3, 4),
        nextDay,
      );
      world = world.copyWith(
        unlockedCatalogueIds: {...world.unlockedCatalogueIds, 'fruit-market'},
      );
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'fruit-market',
        origin: const CellCoord(4, 5),
      );
      world = nextDay(world);
      world = nextDay(world);
      expect(world.population, 2);
      expect(world.employedPopulation, 1);
      final home = content.structure('small-home')!;
      final shop = content.structure('fruit-market')!;
      final ledger = townLedger(world, content);
      expect(
        ledger.grossTaxes,
        closeTo(home.taxCoins / 3 + shop.taxCoins / 6, 0.001),
      );
      expect(
        ledger.taxes,
        ledger.grossTaxes.round(),
        reason: 'contentment is 100% below the service threshold',
      );
      expect(ledger.residentialDemand, 1, reason: 'the list refilled');
      expect(ledger.employmentDemand, 1);
    });
  });

  group('check-in economy', () {
    test('the report collects taxes, pays upkeep, then advances stages', () {
      var world = newWorld();
      // A settled home with a job: taxes flow from employment.
      world = _buildCottage(
        world,
        content,
        terrain,
        const CellCoord(3, 4),
        nextDay,
      );
      world = world.copyWith(
        unlockedCatalogueIds: {...world.unlockedCatalogueIds, 'fruit-market'},
      );
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'fruit-market',
        origin: const CellCoord(4, 5),
      );
      world = nextDay(world);
      world = nextDay(world);

      world = nextDay(world);
      final report = world.events.lastWhere(
        (event) => event.kind == 'check-in',
      );
      final home = content.structure('small-home')!;
      final shop = content.structure('fruit-market')!;
      expect(
        report.payload['taxes'],
        (home.taxCoins / 3 + shop.taxCoins / 6).round(),
        reason: 'one citizen of three employed, one position of six staffed',
      );
      expect(
        report.payload['upkeep'],
        home.upkeepCoins + shop.upkeepCoins + 10,
        reason: 'home and shop upkeep plus the starter road tile',
      );
      expect(report.payload['upkeepShortfall'], 0);
      expect(
        world.totalCoinsEarned - world.totalCoinsSpent,
        world.coins,
        reason: 'the earned-minus-spent ledger still reconciles',
      );
    });

    test('tax starts at employment, not completion', () {
      var world = newWorld();
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'small-home',
        origin: const CellCoord(3, 4),
      );
      // The home completes and newcomers arrive — with no job the
      // levy floors instead of vanishing: the unemployment floor is
      // the soft-lock fix (a homes-only town used to earn nothing
      // forever).
      world = nextDay(world);
      world = nextDay(world);
      world = nextDay(world);
      final unemployed = world.events.lastWhere(
        (event) => event.kind == 'check-in',
      );
      expect(
        unemployed.payload['taxes'],
        (content.structure('small-home')!.taxCoins *
                content.economy.homeTaxUnemploymentFloorPercent /
                100)
            .round(),
        reason: 'no citizen has a job, so homes pay the levy floor',
      );
      expect(
        unemployed.payload['unemployed'],
        1,
        reason: 'the pre-arrival unemployment that produced the floor taxes',
      );
      expect(world.population, 2);

      // A shop opens and employs a citizen: the next report
      // collects — the home at its employment rate, the shop at
      // its staffing rate.
      world = world.copyWith(
        unlockedCatalogueIds: {...world.unlockedCatalogueIds, 'fruit-market'},
      );
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'fruit-market',
        origin: const CellCoord(4, 5),
      );
      world = nextDay(world);
      world = nextDay(world);
      expect(world.employedPopulation, 1);
      world = nextDay(world);
      final report = world.events.lastWhere(
        (event) => event.kind == 'check-in',
      );
      expect(
        report.payload['taxes'],
        (content.structure('small-home')!.taxCoins / 3 +
                content.structure('fruit-market')!.taxCoins / 6)
            .round(),
        reason:
            'one of three housed citizens employed, one of six jobs '
            'staffed',
      );
      expect(
        report.payload['upkeep'],
        content.structure('small-home')!.upkeepCoins +
            content.structure('fruit-market')!.upkeepCoins +
            10,
        reason: 'home and shop upkeep plus the starter road tile',
      );
    });

    test('home taxes floor at the unemployment rate and top up with jobs', () {
      // Two settled homes (six beds) around the starter road; the
      // levy is read straight from the ledger at several employment
      // levels. The floor binds below its rate, the raw rate wins
      // above it, and full employment pays the whole levy.
      var world = newWorld();
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'small-home',
        origin: const CellCoord(3, 4),
      );
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'small-home',
        origin: const CellCoord(4, 5),
      );
      world = settleAll(world);
      final homeTax = 2 * content.structure('small-home')!.taxCoins;
      final floor = content.economy.homeTaxUnemploymentFloorPercent;
      expect(floor, greaterThan(0), reason: 'the shipped content sets a floor');

      var ledger = townLedger(
        world.copyWith(population: 6, employedPopulation: 0),
        content,
      );
      expect(
        ledger.taxes,
        (homeTax * floor / 100).round(),
        reason: 'total unemployment pays the floor, not zero',
      );
      ledger = townLedger(
        world.copyWith(population: 6, employedPopulation: 1),
        content,
      );
      expect(
        ledger.taxes,
        (homeTax * floor / 100).round(),
        reason: 'a sixth employed is still under the floor rate',
      );
      ledger = townLedger(
        world.copyWith(population: 6, employedPopulation: 3),
        content,
      );
      expect(
        ledger.taxes,
        (homeTax * 0.5).round(),
        reason: 'half employed pays the raw rate above the floor',
      );
      ledger = townLedger(
        world.copyWith(population: 6, employedPopulation: 6),
        content,
      );
      expect(ledger.taxes, homeTax, reason: 'full employment pays it all');
    });

    test('a homes-only town recovers through the unemployment floor', () {
      // The reviewer soft-lock, reproduced: homes ring the only
      // road, no jobs anywhere, and the treasury is empty. Before
      // the floor this town earned nothing forever — no taxes
      // without employment, no roads or land without taxes, and
      // nothing to demolish. The floor's trickle must let it buy a
      // road, open a café, and restart employment.
      var world = newWorld();
      for (final origin in [const CellCoord(3, 4), const CellCoord(4, 5)]) {
        world = startStructureConstruction(
          world,
          content,
          terrain,
          catalogueId: 'small-home',
          origin: origin,
        );
      }
      world = settleAll(world);
      world = nextDay(world);
      world = nextDay(world);
      expect(world.employedPopulation, 0, reason: 'no jobs exist');
      expect(world.population, greaterThan(0));

      // The museum state: an empty treasury that must refill through
      // the floor alone.
      var recovered = world.copyWith(coins: 0);
      final floorOnly =
          (2 *
                  content.structure('small-home')!.taxCoins *
                  content.economy.homeTaxUnemploymentFloorPercent /
                  100)
              .round();
      var guard = 0;
      while (recovered.coins < 3 * content.economy.roadTileCostCoins &&
          guard++ < 90) {
        recovered = nextDay(recovered);
      }
      expect(
        recovered.coins,
        greaterThanOrEqualTo(3 * content.economy.roadTileCostCoins),
        reason: 'the floor accrues enough to extend the road',
      );
      final floorReport = recovered.events.lastWhere(
        (event) => event.kind == 'check-in',
      );
      expect(floorReport.payload['taxes'], floorOnly);

      // Extend the street east, open a café on the new frontage, and
      // let staffing climb: employment restarts and the levy rises
      // above the floor.
      recovered = planRoadStretch(
        recovered,
        content,
        terrain,
        cells: const [CellCoord(5, 4), CellCoord(6, 4), CellCoord(7, 4)],
      );
      recovered = nextDay(recovered);
      recovered = startStructureConstruction(
        recovered,
        content,
        terrain,
        catalogueId: 'cafe',
        origin: const CellCoord(6, 3),
      );
      recovered = settleAll(recovered);
      for (var day = 0; day < 6; day++) {
        recovered = nextDay(recovered);
      }
      expect(
        recovered.employedPopulation,
        greaterThan(0),
        reason: 'the café staffs the unemployed',
      );
      final report = recovered.events.lastWhere(
        (event) => event.kind == 'check-in',
      );
      expect(
        report.payload['taxes'] as int,
        greaterThan(floorOnly),
        reason: 'commerce income lifts the levy above the floor',
      );
      expect(
        (report.payload['unemployed'] as int) < recovered.population,
        isTrue,
        reason: 'some citizens hold jobs again',
      );
    });

    test('an empty treasury floors at zero; work advances anyway', () {
      // A treasury set to exactly one parcel's price, spent on that
      // parcel — the earned-minus-spent ledger stays consistent.
      var world = newWorld().copyWith(
        coins: content.economy.parcelBaseCoins,
        totalCoinsEarned: content.economy.parcelBaseCoins,
      );
      world = purchaseParcel(world, content, terrain, const ParcelCoord(1, 0));
      expect(world.coins, 0);

      // Free home and café plans in a broke town: the starter road's
      // upkeep goes unpaid, the shortfall is reported, and the
      // stages still advance — money never blocks labor.
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'small-home',
        origin: const CellCoord(5, 4),
      );
      world = nextDay(world);
      final report = world.events.lastWhere(
        (event) => event.kind == 'check-in',
      );
      expect(report.payload['upkeepPaid'], 0);
      expect(
        report.payload['upkeepShortfall'],
        10,
        reason: 'the starter road upkeep is unpaid',
      );
      expect(world.coins, 0);
      expect(world.constructions.single.stagesDone, 1);

      world = nextDay(world);
      expect(
        built(world),
        hasLength(1),
        reason: 'the home completes with an empty treasury',
      );

      // Recovery runs on employment, not completion: a shop opens,
      // the family works, and taxes slowly refill the treasury.
      world = world.copyWith(
        unlockedCatalogueIds: {...world.unlockedCatalogueIds, 'fruit-market'},
      );
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'fruit-market',
        origin: const CellCoord(4, 5),
      );
      world = settleAll(world);
      // Employment ramps one position per check-in, and the first
      // staffed day's taxes do not yet out-earn upkeep — recovery
      // needs the second.
      world = nextDay(world);
      world = nextDay(world);
      expect(
        world.coins,
        greaterThan(0),
        reason: 'employed taxes out-earn the upkeep shortfall',
      );
      validateParcelWorldState(world, content, terrain);
    });

    test('road and bridge creep ride alongside structure work', () {
      var world = grantWorldDebugCoins(newWorld(), 60000);
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'small-home',
        origin: const CellCoord(3, 4),
      );

      // Roads and bridges plan freely while the home rises — every
      // project kind advances together, one step per check-in.
      world = planRoadStretch(
        world,
        content,
        terrain,
        cells: const [CellCoord(4, 5)],
      );
      world = startBridgeConstruction(
        world,
        content,
        terrain,
        nearBank: const CellCoord(5, 5),
        farBank: const CellCoord(5, 7),
      );
      expect(world.constructions, hasLength(3));

      // One check-in advances all three at once.
      world = nextDay(world);
      expect(
        world.constructions
            .singleWhere((job) => job.kind == WorldConstructionKind.structure)
            .stagesDone,
        1,
      );
      expect(
        world.roads.any((road) => road.cell == const CellCoord(4, 5)),
        isTrue,
        reason: 'the road laid its first tile',
      );
      expect(
        world.constructions
            .singleWhere((job) => job.kind == WorldConstructionKind.bridge)
            .stagesDone,
        1,
        reason: 'the near bank delivered',
      );
      validateParcelWorldState(world, content, terrain);
    });
  });

  group('demolition', () {
    test('demolishing with spare beds moves nobody', () {
      var world = newWorld();
      world = _buildCottage(
        world,
        content,
        terrain,
        const CellCoord(3, 4),
        nextDay,
      );
      world = _buildCottage(
        world,
        content,
        terrain,
        const CellCoord(5, 4),
        nextDay,
      );
      world = world.copyWith(
        population: 3,
        employedPopulation: 0,
        waitingPopulation: 0,
      );
      final coins = world.coins;
      final id = built(world).first.id;
      final quote = quoteStructureDemolition(world, content, structureId: id);
      expect(quote.bedsAfter, 3, reason: 'one three-bed cottage remains');
      expect(quote.stayers, 3, reason: 'the remaining beds house everyone');
      expect(quote.evicted, 0);
      world = demolishStructure(world, content, structureId: id);
      expect(built(world), hasLength(1));
      expect(world.population, 3, reason: 'residents moved, none lost');
      expect(world.waitingPopulation, 0);
      expect(world.coins, coins, reason: 'no refund, no charge');
      final event = world.events.last;
      expect(event.kind, 'structure-demolished');
      expect(event.payload['evicted'], 0);
      expect(
        () => validateParcelWorldState(world, content, terrain),
        returnsNormally,
      );
    });

    test('the eviction cascade: stay, wait, and leave for good', () {
      var world = newWorld();
      world = _buildCottage(
        world,
        content,
        terrain,
        const CellCoord(3, 4),
        nextDay,
      );
      world = _buildCottage(
        world,
        content,
        terrain,
        const CellCoord(5, 4),
        nextDay,
      );
      world = world.copyWith(
        population: 5,
        employedPopulation: 2,
        waitingPopulation: 0,
      );
      final id = built(world).first.id;
      final quote = quoteStructureDemolition(world, content, structureId: id);
      // One cottage remains: three beds for five residents. The
      // waiting list's cap is ten percent of the survivors, floored
      // at one — so one evicted resident waits, one leaves for good.
      expect(quote.bedsAfter, 3);
      expect(quote.stayers, 3);
      expect(quote.evicted, 2);
      expect(quote.joinDemand, 1);
      expect(quote.leftTown, 1);
      world = demolishStructure(world, content, structureId: id);
      expect(world.population, 3);
      expect(world.waitingPopulation, 1);
      expect(
        world.employedPopulation,
        0,
        reason: 'no jobs remain, so nobody stays employed',
      );
      expect(
        () => validateParcelWorldState(world, content, terrain),
        returnsNormally,
      );
      // The loss round-trips through the save.
      final reloaded = sheetTablesToWorld(
        worldToSheetTables(world),
        content: content,
        terrainProvider: terrain,
      );
      expect(reloaded.population, 3);
      expect(reloaded.waitingPopulation, 1);
      expect(reloaded.employedPopulation, 0);
      expect(built(reloaded), hasLength(1));
    });

    test('demolishing a staffed workplace unemploys its workers', () {
      var world = newWorld();
      world = _buildCottage(
        world,
        content,
        terrain,
        const CellCoord(3, 4),
        nextDay,
      );
      // The café is a 2×1 lot: its street edge needs a full two-tile
      // road along its west side.
      world = planAndSettleRoad(world, cells: const [CellCoord(4, 5)]);
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'cafe',
        origin: const CellCoord(5, 4),
      );
      world = settleAll(world);
      world = world.copyWith(
        population: 3,
        employedPopulation: 2,
        waitingPopulation: 0,
      );
      final cafe = world.structures.firstWhere(
        (structure) => structure.catalogueId == 'cafe',
      );
      world = demolishStructure(world, content, structureId: cafe.id);
      expect(world.employedPopulation, 0, reason: 'the workplace is gone');
      expect(world.population, 3, reason: 'residents keep their homes');
      expect(
        () => validateParcelWorldState(world, content, terrain),
        returnsNormally,
      );
    });

    test('a homes-only town frees frontage and builds its way out', () {
      // The playtest soft-lock, as a regression: every free cell
      // beside the road tile carries a home (the hall owns the
      // fourth), so nothing else can sit against the road and no
      // jobs can ever arrive. Demolition is the escape — one home
      // comes down, commerce takes its place on the freed frontage,
      // and the town can recover.
      var world = newWorld();
      for (final cell in [
        const CellCoord(3, 4),
        const CellCoord(5, 4),
        const CellCoord(4, 5),
      ]) {
        world = _buildCottage(world, content, terrain, cell, nextDay);
      }
      world = world.copyWith(
        population: 6,
        employedPopulation: 0,
        waitingPopulation: 0,
        // The market unlocks at the hamlet milestone this town never
        // reached — granted here like the demand tests grant it,
        // because the frontage, not the unlock, is under test.
        unlockedCatalogueIds: {...world.unlockedCatalogueIds, 'fruit-market'},
      );
      expect(
        () => startStructureConstruction(
          world,
          content,
          terrain,
          catalogueId: 'fruit-market',
          origin: const CellCoord(3, 3),
        ),
        throwsA(isA<WorldRuleViolation>()),
        reason: '(3,3) touches no road — the frontage is spent',
      );
      final home = world.structures.firstWhere(
        (structure) => structure.origin == const CellCoord(3, 4),
      );
      world = demolishStructure(world, content, structureId: home.id);
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'fruit-market',
        origin: const CellCoord(3, 4),
      );
      expect(
        world.constructions.single.catalogueId,
        'fruit-market',
        reason: 'commerce takes the freed frontage — the recovery path',
      );
    });

    test('in-flight sites are not demolishable', () {
      var world = newWorld();
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'small-home',
        origin: const CellCoord(3, 4),
      );
      final siteId = world.constructions.single.id;
      expect(
        () => quoteStructureDemolition(world, content, structureId: siteId),
        throwsA(isA<WorldRuleViolation>()),
        reason: 'a site is not a building — its work finishes in days',
      );
    });
  });

  group('the outside connection', () {
    test('only the hall\'s front road roots the network', () {
      var world = newWorld();
      // The front road at (4,4) is the root; a fresh street touching
      // the hall's SIDE joins nothing.
      world = planAndSettleRoad(world, cells: const [CellCoord(2, 4)]);
      // (2,4) touches the hall's west flank (3,4)... wait — it
      // touches the hall cell (3,4)? No: the hall occupies columns
      // 3-5, so (2,4) is free ground beside it, connected to the
      // network only through (3,4) — which is a building, not a
      // road. The side street is an island.
      expect(connectedRoadCells(world, content), {
        const CellCoord(4, 4),
      }, reason: 'a road beside the hall is not the front road');
      // A cottage on the side street refuses: frontage exists, the
      // connection does not.
      expect(
        () => startStructureConstruction(
          world,
          content,
          terrain,
          catalogueId: 'small-home',
          origin: const CellCoord(1, 4),
        ),
        throwsA(
          isA<WorldRuleViolation>().having(
            (error) => error.message,
            'message',
            contains('no outside connection'),
          ),
        ),
        reason: 'frontage without connection carries no buildings',
      );
      // Join the side street to the front road and the same cottage
      // places: the network reached it.
      world = planAndSettleRoad(world, cells: const [CellCoord(3, 4)]);
      expect(connectedRoadCells(world, content), {
        const CellCoord(4, 4),
        const CellCoord(2, 4),
        const CellCoord(3, 4),
      });
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'small-home',
        origin: const CellCoord(1, 4),
      );
      expect(world.constructions.single.catalogueId, 'small-home');
      validateParcelWorldState(world, content, terrain);
    });

    test('a bridge welds the network across water', () {
      // The founding road at (4,4) reaches the channel's near bank
      // via a street; the far bank's street is an island until the
      // bridge opens, then both join the root.
      var world = grantWorldDebugCoins(newWorld(), 600000);
      // The far street lives in parcel (2,0), past the water parcel
      // (1,0) — both bought so the far bank's ground is owned.
      world = purchaseParcel(world, content, terrain, const ParcelCoord(1, 0));
      world = purchaseParcel(world, content, terrain, const ParcelCoord(2, 0));
      world = planAndSettleRoad(
        world,
        cells: const [CellCoord(5, 4), CellCoord(6, 4)],
      );
      final farStreet = [
        for (var column = 17; column <= 19; column++) CellCoord(column, 4),
      ];
      world = planAndSettleRoad(world, cells: farStreet);
      expect(
        connectedRoadCells(world, content).containsAll(farStreet),
        isFalse,
        reason: 'the far street is an island before the bridge',
      );
      world = startBridgeConstruction(
        world,
        content,
        terrain,
        nearBank: const CellCoord(7, 4),
        farBank: const CellCoord(16, 4),
      );
      world = settleAll(world);
      expect(
        connectedRoadCells(world, content).containsAll(farStreet),
        isTrue,
        reason: 'the bridge welds the far street to the root',
      );
      // And a cottage on the far street places.
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'small-home',
        origin: const CellCoord(17, 3),
      );
      expect(world.constructions.single.catalogueId, 'small-home');
      validateParcelWorldState(world, content, terrain);
    });

    test('all four facings plant the front road on the right cell', () {
      // Each facing quotes the road at the middle of that face, one
      // cell out — the compass the arrow shows.
      final fresh = freshWorld();
      final cases = {
        'north': const CellCoord(4, 2),
        'east': const CellCoord(6, 4),
        'south': const CellCoord(4, 6),
        'west': const CellCoord(2, 4),
      };
      for (final entry in cases.entries) {
        final quote = quoteCityFounding(
          fresh,
          content,
          terrain,
          origin: const CellCoord(3, 3),
          facing: entry.key,
        );
        expect(quote.frontCell, entry.value, reason: entry.key);
      }
    });

    test(
      'the hall is permanent: demolition refuses, and a second cannot found',
      () {
        var world = newWorld();
        final hall = world.structures.firstWhere(
          (structure) => structure.catalogueId == 'city-hall',
        );
        expect(
          () => quoteStructureDemolition(world, content, structureId: hall.id),
          throwsA(
            isA<WorldRuleViolation>().having(
              (error) => error.message,
              'message',
              contains("town's root"),
            ),
          ),
        );
        // The hall never places through the catalogue either — not
        // even unlocked.
        world = world.copyWith(
          unlockedCatalogueIds: {...world.unlockedCatalogueIds, 'city-hall'},
        );
        expect(
          () => startStructureConstruction(
            world,
            content,
            terrain,
            catalogueId: 'city-hall',
            origin: const CellCoord(3, 4),
          ),
          throwsA(
            isA<WorldRuleViolation>().having(
              (error) => error.message,
              'message',
              contains('only through founding'),
            ),
          ),
        );
      },
    );

    test('bridge banks are not frontage', () {
      // A bridge over the channel: both its banks are road tiles,
      // but a building may not face either — a landing is not a
      // street, whatever art paves it.
      var world = grantWorldDebugCoins(newWorld(), 600000);
      world = purchaseParcel(world, content, terrain, const ParcelCoord(1, 0));
      world = purchaseParcel(world, content, terrain, const ParcelCoord(2, 0));
      world = planAndSettleRoad(
        world,
        cells: const [CellCoord(5, 4), CellCoord(6, 4)],
      );
      world = startBridgeConstruction(
        world,
        content,
        terrain,
        nearBank: const CellCoord(7, 4),
        farBank: const CellCoord(16, 4),
      );
      world = settleAll(world);
      expect(world.roadsByCell.containsKey(const CellCoord(16, 4)), isTrue);
      expect(
        () => startStructureConstruction(
          world,
          content,
          terrain,
          catalogueId: 'small-home',
          origin: const CellCoord(16, 3),
        ),
        throwsA(isA<WorldRuleViolation>()),
        reason: 'a bridge landing is not frontage',
      );
      expect(
        () => startStructureConstruction(
          world,
          content,
          terrain,
          catalogueId: 'small-home',
          origin: const CellCoord(7, 3),
        ),
        throwsA(isA<WorldRuleViolation>()),
        reason: 'the near landing is not frontage either',
      );
      validateParcelWorldState(world, content, terrain);
    });

    test('a save with a building off the network is refused', () {
      // A hand-edited shape: the hall roots (4,4), but a cottage
      // stands on a road that never reached it. The validator names
      // the building — saves are data, and this one is wrong.
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
            ['6', '6', 'road', 'complete', 'asphalt', '', '', ''],
            [
              '6',
              '5',
              'structure',
              'complete',
              'small-home',
              'home-small-yellow',
              'south',
              '',
            ],
          ],
          projects: const [],
        ),
        content: content,
        terrainProvider: terrain,
      );
      expect(
        () => validateParcelWorldState(world, content, terrain),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('off the city hall'),
          ),
        ),
      );
    });

    test('a save whose city owns land without a hall is refused', () {
      // The no-migration contract: pre-founding saves fail loudly on
      // load, by absence — no version code anywhere.
      expect(
        () => validateParcelWorldState(newWorldHallLess(), content, terrain),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('no city hall'),
          ),
        ),
      );
    });
  });

  group('parcel purchase and natural terrain', () {
    test('another city\'s claim refuses purchase and founding', () {
      // One map, exclusive parcels: the session passes every other
      // city's parcels as the claim set, and the same rules refuse
      // them — founding included.
      final fresh = freshWorld();
      expect(
        () => quoteCityFounding(
          fresh,
          content,
          terrain,
          origin: const CellCoord(3, 1),
          facing: 'south',
          claimedParcels: {const ParcelCoord(0, 0)},
        ),
        throwsA(
          isA<WorldRuleViolation>().having(
            (error) => error.message,
            'message',
            contains('Another city has claimed'),
          ),
        ),
        reason: 'founding cannot take a foreign-held parcel',
      );
      // Without the claim the same spot founds normally — single-city
      // callers behave exactly as before.
      expect(
        () => quoteCityFounding(
          fresh,
          content,
          terrain,
          origin: const CellCoord(3, 1),
          facing: 'south',
        ),
        returnsNormally,
      );

      var world = grantWorldDebugCoins(newWorld(), 200);
      // The settled start already owns (0,0) with its road; expansion
      // is the purchase under test.
      const neighbor = ParcelCoord(1, 0);
      expect(
        () => purchaseParcel(
          world,
          content,
          terrain,
          neighbor,
          claimedParcels: {neighbor},
        ),
        throwsA(isA<WorldRuleViolation>()),
        reason: 'expansion cannot take a foreign-held parcel',
      );
      expect(
        () => purchaseParcel(world, content, terrain, neighbor),
        returnsNormally,
      );
    });

    test('parcels are neighboring purchases and owning land is not access', () {
      var world = grantWorldDebugCoins(newWorld(), 15000);
      // Authored water parcels are buyable like any other map parcel.
      world = purchaseParcel(world, content, terrain, const ParcelCoord(1, 0));
      expect(world.parcels, hasLength(2));
      // So is the grass parcel across the water — adjacency is the only
      // purchase requirement now.
      world = purchaseParcel(world, content, terrain, const ParcelCoord(2, 0));
      expect(world.parcels, hasLength(3));
      // Ownership is not access: nothing beyond the water is
      // reachable on foot until a bridge opens.
      expect(
        WorldQueries(world, terrain).isLandReachable(const CellCoord(16, 4)),
        isFalse,
      );
    });

    test('parcel prices scale with the settlement population', () {
      var world = grantWorldDebugCoins(newWorld(), 500);
      final base = content.economy.parcelBaseCoins;
      final perPopulation = content.economy.parcelPerPopulationCoins;

      // Population zero: the flat base price, and the quote exposes
      // the breakdown the buy dialog shows.
      final atZero = quoteParcelPurchase(
        world,
        content,
        terrain,
        const ParcelCoord(1, 0),
      );
      expect(atZero.price, base);
      expect(atZero.basePrice, base);
      expect(atZero.perPopulationCoins, perPopulation);

      // A town of population three: the price rises by exactly the
      // per-population surcharge — expanding a grown town costs more.
      world = world.copyWith(population: 3, employedPopulation: 3);
      expect(world.population, 3);
      final atThree = quoteParcelPurchase(
        world,
        content,
        terrain,
        const ParcelCoord(1, 0),
      );
      expect(atThree.price, base + 3 * perPopulation);

      // The purchase charges the scaled price and records it.
      world = purchaseParcel(world, content, terrain, const ParcelCoord(1, 0));
      expect(world.parcels.last.pricePaid, base + 3 * perPopulation);
      expect(
        world.totalCoinsSpent,
        greaterThanOrEqualTo(base + 3 * perPopulation),
      );
      validateParcelWorldState(world, content, terrain);
    });

    test('water parcels are buyable but fog beyond the map is not', () {
      var world = grantWorldDebugCoins(newWorld(), 30000);
      world = purchaseParcel(world, content, terrain, const ParcelCoord(-1, 0));
      final queries = WorldQueries(world, terrain);
      // Sample a cell the live tile overrides have not painted — live
      // content may carry any number of them.
      CellCoord unoverriddenCell(ParcelCoord parcel) {
        for (final cell in parcel.cells(newWorld().parcelSize)) {
          if (!content.terrain.tiles.containsKey(cell)) return cell;
        }
        fail('every cell of $parcel carries a tile override');
      }

      expect(
        queries.terrainAt(unoverriddenCell(const ParcelCoord(-1, 0))).kind,
        TerrainKind.water,
      );
      expect(
        queries.isLandReachable(const CellCoord(-6, 2)),
        isFalse,
        reason:
            'owning the west water parcel does not reach the land '
            'beyond it',
      );
      // Buy out to the authored edge, then the fog refuses.
      world = purchaseParcel(world, content, terrain, const ParcelCoord(-2, 0));
      world = purchaseParcel(world, content, terrain, const ParcelCoord(-3, 0));
      expect(
        () => purchaseParcel(world, content, terrain, const ParcelCoord(-4, 0)),
        throwsA(isA<WorldRuleViolation>()),
        reason: 'beyond the authored map is fog — uncharted and unbuyable',
      );
    });
  });

  test('a freshly planned bridge over land validates immediately', () {
    // Disconnected from any road, spanning owned dry land only — the
    // store validates on save, so a fresh plan (zero coins funded)
    // must satisfy save validation as-is.
    var world = grantWorldDebugCoins(newWorld(), 60000);
    world = planAndSettleRoad(
      world,
      cells: const [CellCoord(2, 6), CellCoord(3, 6), CellCoord(4, 6)],
    );
    world = startBridgeConstruction(
      world,
      content,
      terrain,
      nearBank: const CellCoord(5, 6),
      farBank: const CellCoord(7, 6),
    );
    final job = world.constructions.single;
    expect(job.kind, WorldConstructionKind.bridge);
    expect(job.stagesDone, 0);
    expect(job.waterCells, const [CellCoord(6, 6)]);
    validateParcelWorldState(world, content, terrain);

    // The first check-in delivers the near bank as a road tile and
    // the state stays valid mid-construction.
    world = nextDay(world);
    expect(
      world.roads.any((road) => road.cell == const CellCoord(5, 6)),
      isTrue,
    );
    validateParcelWorldState(
      world,
      content,
      terrain,
    ); // Cell by cell to completion: the store validates on every save,
    // so the finished disconnected bridge must validate too — the
    // far bank opens as a road tile with it.
    while (world.constructions.isNotEmpty) {
      world = nextDay(world);
      validateParcelWorldState(world, content, terrain);
    }
    final bridge = world.bridges.single;
    expect(bridge.nearBank, const CellCoord(5, 6));
    expect(bridge.farBank, const CellCoord(7, 6));
    expect(
      world.roads.any((road) => road.cell == const CellCoord(7, 6)),
      isTrue,
      reason: 'the far bank opens as a road with the bridge',
    );
    expect(
      bridge.pricePaid,
      1 * content.economy.bridgeTileCostCoins +
          2 * content.economy.roadTileCostCoins,
      reason: 'one span tile plus two road-priced banks, paid upfront',
    );
  });

  test('a bridge creeps tile by tile before opening the far bank', () {
    var world = grantWorldDebugCoins(newWorld(), 500000);
    // Everything under the bridge must be owned up front: the water
    // parcel and the far-bank parcel are bought before planning.
    world = purchaseParcel(world, content, terrain, const ParcelCoord(1, 0));
    world = purchaseParcel(world, content, terrain, const ParcelCoord(2, 0));
    // Roads stop one tile short: both bridge banks need vacant land.
    world = planAndSettleRoad(
      world,
      cells: [for (var column = 5; column <= 6; column++) CellCoord(column, 4)],
    );
    // The east water parcel spans cells x 8..15: an eight-tile span
    // with vacant banks either side.
    final quote = quoteBridge(
      world,
      content,
      terrain,
      nearBank: const CellCoord(7, 4),
      farBank: const CellCoord(16, 4),
    );
    expect(quote.spanCells, [
      for (var column = 8; column <= 15; column++) CellCoord(column, 4),
    ]);
    // Flat per-tile pricing: eight span tiles plus two road-priced
    // banks, all paid upfront.
    expect(
      quote.bridgeCost,
      8 * content.economy.bridgeTileCostCoins +
          2 * content.economy.roadTileCostCoins,
    );

    world = startBridgeConstruction(
      world,
      content,
      terrain,
      nearBank: const CellCoord(7, 4),
      farBank: const CellCoord(16, 4),
    );
    final coinsAfterPlanning = world.coins;
    expect(world.bridges, isEmpty);
    world = advanceWorldDays(world, 100);
    expect(world.bridges, isEmpty, reason: 'days never fund anything');

    // The first check-in delivers the near bank as a road tile.
    world = nextDay(world);
    expect(
      world.roads.any((road) => road.cell == const CellCoord(7, 4)),
      isTrue,
      reason: 'the near bank becomes a road with the first delivery',
    );
    expect(world.bridges, isEmpty);

    while (world.constructions.isNotEmpty) {
      world = nextDay(world);
    }
    final queries = WorldQueries(world, terrain);
    expect(world.bridges, hasLength(1));
    expect(
      world.roads.any((road) => road.cell == const CellCoord(16, 4)),
      isTrue,
      reason: 'the far bank opens with the bridge',
    );
    // The bank is a landing, not frontage: a cottage beside it needs
    // a real street beyond, paved onto the far shore — which the
    // bridge's weld keeps connected to the hall's network.
    world = planAndSettleRoad(world, cells: const [CellCoord(17, 4)]);
    expect(
      quoteStructurePlacement(
        world,
        content,
        terrain,
        catalogueId: 'small-home',
        origin: const CellCoord(17, 3),
      ).price,
      0,
      reason: 'building plans are free in the staged economy',
    );
    expect(queries.isLandReachable(const CellCoord(16, 4)), isTrue);
    expect(world.coins, lessThan(coinsAfterPlanning));
    validateParcelWorldState(world, content, terrain);
  });

  test('straight-line projection picks the closer axis', () {
    // Horizontal: the column delta dominates.
    expect(
      straightLineBetween(const CellCoord(4, 4), const CellCoord(7, 5)),
      const [
        CellCoord(4, 4),
        CellCoord(5, 4),
        CellCoord(6, 4),
        CellCoord(7, 4),
      ],
    );
    // Vertical: the row delta dominates.
    expect(
      straightLineBetween(const CellCoord(4, 4), const CellCoord(5, 8)),
      const [
        CellCoord(4, 4),
        CellCoord(4, 5),
        CellCoord(4, 6),
        CellCoord(4, 7),
        CellCoord(4, 8),
      ],
    );
    // Ties go horizontal.
    expect(
      straightLineBetween(const CellCoord(4, 4), const CellCoord(6, 6)),
      const [CellCoord(4, 4), CellCoord(5, 4), CellCoord(6, 4)],
    );
    // Start == end yields a single tile.
    expect(
      straightLineBetween(const CellCoord(4, 4), const CellCoord(4, 4)),
      const [CellCoord(4, 4)],
    );
    // Projection also runs backwards (end west/north of start).
    expect(
      straightLineBetween(const CellCoord(6, 4), const CellCoord(4, 4)),
      const [CellCoord(6, 4), CellCoord(5, 4), CellCoord(4, 4)],
    );
  });

  test('roads place anywhere on owned land without connectivity', () {
    // An isolated stretch in the corner of the starter parcel, far
    // from the starter road, quotes and funds fine.
    var world = grantWorldDebugCoins(newWorld(), 3);
    world = planRoadStretch(
      world,
      content,
      terrain,
      cells: const [CellCoord(1, 1), CellCoord(2, 1)],
    );
    world = nextDay(world);
    world = nextDay(world);
    expect(world.roads, hasLength(3), reason: 'starter + the isolated pair');
    validateParcelWorldState(world, content, terrain);
  });

  test('road sections span between junctions, elbows, and dead ends', () {
    var world = grantWorldDebugCoins(newWorld(), 20);
    // A T shape: a three-tile stem east of the starter road with a
    // two-tile branch south from its middle.
    world = planAndSettleRoad(
      world,
      cells: const [CellCoord(5, 4), CellCoord(6, 4), CellCoord(7, 4)],
    );
    world = planAndSettleRoad(
      world,
      cells: const [CellCoord(6, 5), CellCoord(6, 6)],
    );
    final queries = WorldQueries(world, terrain);
    // The stem splits at the junction (6,4): junction cells bound
    // sections and belong to none, so tapping east of it selects the
    // short run to the dead end.
    expect(queries.roadSectionAt(const CellCoord(7, 4)), const [
      CellCoord(7, 4),
    ], reason: 'the junction bounds the eastern run');
    // Tapping the branch selects the vertical run below the junction.
    expect(queries.roadSectionAt(const CellCoord(6, 6)), const [
      CellCoord(6, 5),
      CellCoord(6, 6),
    ]);
    // Tapping a non-road cell selects nothing.
    expect(queries.roadSectionAt(const CellCoord(2, 2)), isEmpty);
  });

  test('active funded road project round-trips through the save', () {
    var world = grantWorldDebugCoins(newWorld(), 20);
    world = purchaseParcel(world, content, terrain, const ParcelCoord(1, 0));
    world = planRoadStretch(
      world,
      content,
      terrain,
      cells: const [CellCoord(5, 4), CellCoord(6, 4)],
    );
    world = nextDay(world);

    final decoded = sheetTablesToWorld(
      worldToSheetTables(world),
      content: content,
      terrainProvider: terrain,
    );
    validateParcelWorldState(decoded, content, terrain);
    // Round-tripping the rebuilt world again is a fixed point: the same
    // tables come back out.
    expect(
      encodeMultiCityTables(
        MultiCityTables(
          cities: const [
            CityRecord(id: 'city_1', name: 'City 1', founded: '2026-11-02'),
          ],
          tablesById: {'city_1': worldToSheetTables(decoded)},
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

  test('a vertical one-tile bridge round-trips through the save', () {
    var world = grantWorldDebugCoins(newWorld(), 50000);
    // Two short roads north and south of the crossing; the banks
    // themselves stay vacant land so the span is a single vertical
    // tile between them.
    world = planAndSettleRoad(
      world,
      cells: const [CellCoord(2, 1), CellCoord(2, 2)],
    );
    world = planAndSettleRoad(
      world,
      cells: const [CellCoord(2, 6), CellCoord(2, 7)],
    );
    world = startBridgeConstruction(
      world,
      content,
      terrain,
      nearBank: const CellCoord(2, 3),
      farBank: const CellCoord(2, 5),
    );
    world = settleAll(world);

    final decoded = sheetTablesToWorld(
      worldToSheetTables(world),
      content: content,
      terrainProvider: terrain,
    );
    final bridge = decoded.bridges.single;
    expect(bridge.waterCells, const [CellCoord(2, 4)]);
    expect(bridge.nearBank, const CellCoord(2, 3));
    expect(bridge.farBank, const CellCoord(2, 5));
    validateParcelWorldState(decoded, content, terrain);
  });

  test('non-square lots turn with their door side', () {
    // The clinic's footprint is 2×1 — wide along the street. Beside
    // an east-west road it stays as declared; beside a north-south
    // road it turns a quarter so its street edge faces the road.
    // (The clinic is population-gated; grant the unlock a grown city
    // would already have.)
    var world = grantWorldDebugCoins(newWorld(), 30);
    world = world.copyWith(
      unlockedCatalogueIds: {...world.unlockedCatalogueIds, 'community-clinic'},
    );

    // An east-west street along row 4 (the starter road plus one).
    world = planAndSettleRoad(world, cells: const [CellCoord(5, 4)]);
    world = startStructureConstruction(
      world,
      content,
      terrain,
      catalogueId: 'community-clinic',
      origin: const CellCoord(4, 5),
    );
    var clinic = world.constructions.single;
    expect(clinic.facing, 'north');
    expect(clinic.footprint, const [CellCoord(4, 5), CellCoord(5, 5)]);
    world = settleAll(world);

    // A north-south street down column 6, joined to the row-4 street
    // at (6,4) — frontage must reach the hall's network.
    world = planAndSettleRoad(
      world,
      cells: const [
        CellCoord(6, 4),
        CellCoord(6, 5),
        CellCoord(6, 6),
        CellCoord(6, 7),
      ],
    );
    world = startStructureConstruction(
      world,
      content,
      terrain,
      catalogueId: 'community-clinic',
      origin: const CellCoord(5, 6),
    );
    clinic = world.constructions.single;
    expect(clinic.facing, 'east');
    expect(clinic.footprint, const [CellCoord(5, 6), CellCoord(5, 7)]);
    world = settleAll(world);

    expect(
      () => validateParcelWorldState(world, content, terrain),
      returnsNormally,
    );
  });

  test('door swaps turn non-square lots, and need the room', () {
    var world = grantWorldDebugCoins(newWorld(), 40);
    world = world.copyWith(
      unlockedCatalogueIds: {...world.unlockedCatalogueIds, 'community-clinic'},
    );

    // A corner-fronted clinic at (4,5): the row-4 street to its north
    // and a north-south road to its west. Swapping to the western
    // road turns the lot a quarter — the footprint transposes to run
    // south from the origin.
    world = planAndSettleRoad(world, cells: const [CellCoord(5, 4)]);
    world = planAndSettleRoad(
      world,
      cells: const [CellCoord(3, 4), CellCoord(3, 5)],
    );
    world = startStructureConstruction(
      world,
      content,
      terrain,
      catalogueId: 'community-clinic',
      origin: const CellCoord(4, 5),
    );
    var clinic = world.constructions.single;
    expect(clinic.facing, 'north');
    expect(clinic.footprint, const [CellCoord(4, 5), CellCoord(5, 5)]);

    world = swapStructureFacing(world, content, terrain, projectId: clinic.id);
    clinic = world.constructions.single;
    expect(clinic.facing, 'west');
    expect(clinic.footprint, const [CellCoord(4, 5), CellCoord(4, 6)]);
    world = settleAll(world);
    expect(
      () => validateParcelWorldState(world, content, terrain),
      returnsNormally,
    );

    // A clinic that cannot turn: its corner frontage offers the swap,
    // but the cell the turned lot needs is taken by a cottage, so the
    // swap refuses instead of clipping through it.
    world = planAndSettleRoad(world, cells: const [CellCoord(2, 5)]);
    world = planAndSettleRoad(
      world,
      cells: const [CellCoord(1, 5), CellCoord(1, 6), CellCoord(1, 7)],
    );
    world = startStructureConstruction(
      world,
      content,
      terrain,
      catalogueId: 'small-home',
      origin: const CellCoord(2, 7),
    );
    world = settleAll(world);
    world = startStructureConstruction(
      world,
      content,
      terrain,
      catalogueId: 'community-clinic',
      origin: const CellCoord(2, 6),
    );
    expect(world.constructions.single.facing, 'north');
    expect(
      () => swapStructureFacing(
        world,
        content,
        terrain,
        projectId: world.constructions.single.id,
      ),
      throwsA(isA<WorldRuleViolation>()),
      reason: 'the turned lot would land on the cottage at (2,7)',
    );
  });
}

/// Plans a small home and lets the check-ins raise it to completion.
ParcelWorldState _buildCottage(
  ParcelWorldState world,
  ContentBundle content,
  TerrainProvider terrain,
  CellCoord origin,
  ParcelWorldState Function(ParcelWorldState) nextDay,
) {
  world = startStructureConstruction(
    world,
    content,
    terrain,
    catalogueId: 'small-home',
    origin: origin,
  );
  final stages = content.structure('small-home')!.constructionStages;
  for (final _ in List.filled(stages, 0)) {
    world = nextDay(world);
  }
  return world;
}

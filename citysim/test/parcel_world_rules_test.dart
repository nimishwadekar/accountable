import 'package:citysim/content/asset_content_source.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ContentTerrainProvider terrain;
  late ContentBundle content;

  setUpAll(() async {
    content = await loadContentBundle(const AssetContentSource());
    terrain = ContentTerrainProvider(content.terrain);
  });

  /// The untouched first minute of a new game: nothing owned, nothing
  /// built — the player has yet to choose a founding parcel.
  ParcelWorldState freshWorld() => newParcelWorldState(
    content: content,
    seed: 123456,
    today: DateTime.utc(2026, 11, 2),
  );

  /// A settled start: parcel (0,0) owned with one road tile at its
  /// centre — the shape every town-building test begins from,
  /// assembled directly through the save codec so no coins, days, or
  /// events are spent reaching it. (The founding itself is covered
  /// from [freshWorld] above.)
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

  /// Plans a road stretch and lets the check-ins lay it fully. Call
  /// only when the stretch is the sole in-flight work: a check-in
  /// advances every project, not one.
  ParcelWorldState planAndSettleRoad(
    ParcelWorldState world, {
    required List<CellCoord> cells,
  }) {
    world = planRoadStretch(world, content, terrain, cells: cells);
    for (final _ in cells) {
      world = nextDay(world);
    }
    return world;
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

    test('the founding parcel is free, anywhere charted, and needs land', () {
      var world = freshWorld();

      // Any charted parcel with room to build: free, no neighbour
      // required — there is nothing to be adjacent to yet.
      final quote = quoteParcelPurchase(
        world,
        content,
        terrain,
        const ParcelCoord(0, 0),
      );
      expect(quote.price, 0, reason: 'the founding parcel is free');
      world = purchaseParcel(world, content, terrain, const ParcelCoord(0, 0));
      expect(world.parcels.single.coord, const ParcelCoord(0, 0));
      expect(world.parcels.single.pricePaid, 0);
      expect(world.coins, content.economy.startingTreasuryCoins);
      expect(
        world.events.last.description,
        'Parcel 0,0 claimed · the founding parcel, free',
      );
      expect(
        () => validateParcelWorldState(world, content, terrain),
        returnsNormally,
      );

      // The second parcel is a normal purchase: adjacent, priced by
      // the settlement's size.
      final second = quoteParcelPurchase(
        world,
        content,
        terrain,
        const ParcelCoord(1, 0),
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

      // The founding needs buildable ground: five or more land
      // cells. A water parcel would dead-end the opening — nothing
      // to road, nothing to build, no income for a second parcel.
      final waterParcel = content.terrain.parcels.entries
          .firstWhere((entry) => entry.value == TerrainKind.water)
          .key;
      expect(
        () => quoteParcelPurchase(world, content, terrain, waterParcel),
        returnsNormally,
        reason: 'paid purchases may still be water',
      );
      final fresh = freshWorld();
      expect(
        () => purchaseParcel(fresh, content, terrain, waterParcel),
        throwsA(isA<WorldRuleViolation>()),
        reason: 'the founding parcel refuses open water',
      );
      // Not only open water: a mostly-drowned parcel with four land
      // cells fails the same buildability bar. A synthetic map pins
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
        () =>
            purchaseParcel(fresh, content, sparseLand, const ParcelCoord(0, 0)),
        throwsA(isA<WorldRuleViolation>()),
        reason: 'four land cells cannot found a settlement',
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
      world = world.copyWith(population: 12, employedPopulation: 12);
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
      expect(world.progressionMilestonePopulation, 10);
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
        expect(world.coins, content.economy.startingTreasuryCoins - 1);
        final report = world.events.lastWhere((e) => e.kind == 'check-in');
        expect(report.payload['taxes'], 0);
        expect(report.payload['upkeep'], 1);
        expect(report.payload['upkeepShortfall'], 0);
        expect(checkInWorldForToday(world, content), same(world));

        world = advanceWorldDays(world, 1);
        expect(
          world.coins,
          content.economy.startingTreasuryCoins - 1,
          reason: 'a day advance does not check in',
        );
        world = checkInWorldForToday(world, content);
        expect(world.coins, content.economy.startingTreasuryCoins - 2);

        final constructionDay = world.constructionDay;
        world = setWorldCalendarDate(
          world,
          world.simulatedDate.subtract(const Duration(days: 3)),
        );
        expect(world.constructionDay, constructionDay);
        expect(canCheckInWorldToday(world), isFalse);
        expect(checkInWorldForToday(world, content), same(world));
        expect(world.coins, content.economy.startingTreasuryCoins - 2);
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
      'road plans are upfront purchases that creep one tile per check-in',
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
        // A second stretch plans while the first creeps — roads never
        // block each other.
        world = planRoadStretch(
          world,
          content,
          terrain,
          cells: const [CellCoord(3, 4)],
        );
        expect(world.constructions, hasLength(2));

        world = advanceWorldDays(world, 30);
        expect(world.roads, hasLength(1), reason: 'days never build anything');

        // One check-in lays one tile of each creeping stretch, in plan
        // order from the start.
        world = nextDay(world);
        expect(world.roads, hasLength(3));
        expect(
          world.roads.any((road) => road.cell == const CellCoord(5, 4)),
          isTrue,
          reason: 'the first planned tile lays first',
        );
        expect(
          world.roads.any((road) => road.cell == const CellCoord(3, 4)),
          isTrue,
          reason: 'every creeping stretch advances together',
        );
        world = nextDay(world);
        expect(world.roads, hasLength(4));
        expect(
          world.constructions.where(
            (job) => job.roadCells.contains(const CellCoord(5, 4)),
          ),
          isEmpty,
          reason: 'laying the last tile settles the stretch',
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
        expect(project.population, 1);
        expect(world.coins, content.economy.startingTreasuryCoins);
        expect(world.structures, isEmpty);
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
        expect(world.structures, isEmpty, reason: 'days never build anything');

        world = nextDay(world);
        expect(world.constructions.single.stagesDone, 1);
        expect(world.structures, isEmpty);
        world = nextDay(world);

        expect(world.structures.single.catalogueId, 'small-home');
        expect(world.structures.single.population, 1);
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
      expect(world.structures, isEmpty);
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
          origin: CellCoord(2 + index, 2),
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
      // Three cottages fit beside the starter road without blocking the
      // southern extension; extend the road, then place three more beside
      // it for six rolls of the six-variant cottage.
      final nearRoad = [
        const CellCoord(3, 4),
        const CellCoord(5, 4),
        const CellCoord(4, 3),
      ];
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
      final structureRoles = world.structures.map((s) => s.assetRole).toList();
      expect(
        world.structures.every(
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
      for (final origin in nearRoad.take(3)) {
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
      expect(replayRoles, rolled.take(3), reason: 'same seed, same rolls');

      final decoded = sheetTablesToWorld(
        worldToSheetTables(world),
        content: content,
        terrainProvider: terrain,
      );
      expect(
        decoded.structures.map((s) => s.assetRole).toList(),
        structureRoles,
        reason: 'variant snapshots survive the sheet round-trip',
      );
    });

    test('buildings larger than 1x1 need a road along a whole side', () {
      // A 2×2 footprint at (5,3) touches the starter road only at its
      // south-west corner cell (5,4): one adjacent road is no longer
      // frontage for a multi-cell building.
      var world = grantWorldDebugCoins(newWorld(), 10);
      final apartments = content.structure('apartments')!;
      final footprint = structureFootprint(apartments, const CellCoord(5, 3));
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
          origin: const CellCoord(5, 3),
        ),
        throwsA(isA<WorldRuleViolation>()),
      );

      // Roads along the whole north side (5,2) and (6,2) satisfy it.
      world = planAndSettleRoad(
        world,
        cells: const [
          CellCoord(4, 3),
          CellCoord(4, 2),
          CellCoord(5, 2),
          CellCoord(6, 2),
        ],
      );
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
            const CellCoord(5, 4),
          ),
        ),
        isTrue,
      );
    });

    test('building facings follow the adjacent road side', () {
      // The starter road sits at (4,4): grid east of (3,4), south of
      // (4,3), north of (4,5), and west of (5,4). The saved facing is
      // the bordering road side itself.
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
        origin: const CellCoord(4, 3),
      );
      expect(world.constructions.single.facing, 'south');
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
      // Content-driven progression: a town grown to six households
      // the real way — homes and jobs in balance — with the unlock
      // grants coming through load-time reconciliation.
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
      // A settled, employed town grown to six households the way
      // play would — homes and jobs in balance.
      world = world.copyWith(population: 6, employedPopulation: 6);
      expect(world.population, 6);
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
      expect(world.waitingHouseholds, 1, reason: 'the vacuous kickstart');
      expect(world.population, 0);

      // The cottage completes and receives today's household — but
      // with no jobs, its family is unemployed and pays no tax.
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
      expect(report.payload['householdsArrived'], 1);
      expect(
        report.payload['taxes'],
        0,
        reason: 'an unemployed household pays nothing',
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
      expect(world.waitingHouseholds, 1, reason: 'a prosperous town attracts');
      report = world.events.lastWhere((e) => e.kind == 'check-in');
      expect(report.payload['positionsStaffed'], 1);

      // The second home completes and its household arrives.
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'small-home',
        origin: const CellCoord(5, 4),
      );
      world = nextDay(world);
      world = nextDay(world);
      expect(world.population, 2);
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
        world.waitingHouseholds,
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
        const CellCoord(4, 3),
        nextDay,
      );
      expect(world.population, 2);
      expect(world.waitingHouseholds, 0);
      expect(world.unemployment, 2);
      final ledger = townLedger(world, content);
      expect(ledger.residentialVacancy, 1);
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
        cafe.upkeepCoins + 4,
        reason:
            'full upkeep plus four road tiles — the '
            'anti-shop-farming guard',
      );
      expect(world.coins, before - cafe.upkeepCoins - 4);
    });

    test('the town reports its physical footprint', () {
      // A fresh world: one 8×8 parcel and the founding road tile.
      var world = newWorld();
      expect(world.ownedTileCount, 64);
      expect(world.builtTileCount, 1, reason: 'the founding road');

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
      expect(world.builtTileCount, 2);

      // Road tiles count as built-up land too.
      world = planAndSettleRoad(
        world,
        cells: const [CellCoord(4, 3), CellCoord(4, 2)],
      );
      expect(world.builtTileCount, 4);
    });

    test('service coverage scales contentment, floored at 30 percent', () {
      // A compact variant of the content with an early service
      // threshold, so two households already demand coverage.
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
        origin: const CellCoord(4, 3),
      );
      world = nextDay(world);
      world = nextDay(world);
      world = _buildCottage(
        world,
        content,
        terrain,
        const CellCoord(5, 4),
        nextDay,
      );
      expect(world.population, 2);
      expect(
        world.employedPopulation,
        2,
        reason: 'the café employs both families',
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

      // A fire station south of an eastward road covers the town:
      // fire climbs to full, contentment rises off the floor but
      // stays capped by the missing categories — the average.
      world = world.copyWith(
        unlockedCatalogueIds: {...world.unlockedCatalogueIds, 'fire-station'},
      );
      world = planAndSettleRoad(
        world,
        cells: const [CellCoord(6, 4), CellCoord(7, 4)],
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
      validateParcelWorldState(world, content, terrain);
    });

    test('only employed people pay, at the aggregate rates', () {
      var world = newWorld();
      // One occupied home (unemployed) plus one staffed café: the
      // home pays nothing, the café pays a quarter of its tax.
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
      expect(world.population, 1);
      expect(world.employedPopulation, 1);
      final home = content.structure('small-home')!;
      final shop = content.structure('fruit-market')!;
      final ledger = townLedger(world, content);
      expect(
        ledger.grossTaxes,
        closeTo(home.taxCoins + shop.taxCoins / 3, 0.001),
      );
      expect(
        ledger.taxes,
        ledger.grossTaxes.round(),
        reason: 'contentment is 100% below the service threshold',
      );
      expect(ledger.residentialDemand, 1, reason: 'the list refilled');
      expect(ledger.employmentDemand, 0);
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
      expect(report.payload['taxes'], home.taxCoins + shop.taxCoins ~/ 3);
      expect(
        report.payload['upkeep'],
        shop.upkeepCoins + 1,
        reason: 'shop upkeep plus the starter road tile',
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
      // The home completes and its household arrives — but with no
      // job, every report collects nothing.
      world = nextDay(world);
      world = nextDay(world);
      world = nextDay(world);
      final unemployed = world.events.lastWhere(
        (event) => event.kind == 'check-in',
      );
      expect(
        unemployed.payload['taxes'],
        0,
        reason: 'the household has no job',
      );
      expect(world.population, 1);

      // A shop opens and employs the family: the next report
      // collects — the home at full, the shop at its staffing rate.
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
        content.structure('small-home')!.taxCoins +
            content.structure('fruit-market')!.taxCoins ~/ 3,
      );
      expect(
        report.payload['upkeep'],
        2,
        reason: 'shop upkeep plus the starter road tile',
      );
    });

    test('an empty treasury floors at zero; work advances anyway', () {
      var world = grantWorldDebugCoins(
        newWorld(),
        content.economy.parcelBaseCoins - content.economy.startingTreasuryCoins,
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
        1,
        reason: 'the starter road upkeep is unpaid',
      );
      expect(world.coins, 0);
      expect(world.constructions.single.stagesDone, 1);

      world = nextDay(world);
      expect(
        world.structures,
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
        origin: const CellCoord(4, 3),
      );
      world = settleAll(world);
      world = nextDay(world);
      expect(
        world.coins,
        greaterThan(0),
        reason: 'employed taxes out-earn the upkeep shortfall',
      );
      validateParcelWorldState(world, content, terrain);
    });

    test('road and bridge creep ride alongside structure work', () {
      var world = grantWorldDebugCoins(newWorld(), 200);
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

  group('parcel purchase and natural terrain', () {
    test('parcels are neighboring purchases and owning land is not access', () {
      var world = grantWorldDebugCoins(newWorld(), 100);
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

      // A town of three households: the price rises by exactly the
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
      var world = grantWorldDebugCoins(newWorld(), 100);
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
    var world = grantWorldDebugCoins(newWorld(), 50);
    world = planAndSettleRoad(
      world,
      cells: const [CellCoord(2, 2), CellCoord(3, 2), CellCoord(4, 2)],
    );
    world = startBridgeConstruction(
      world,
      content,
      terrain,
      nearBank: const CellCoord(5, 2),
      farBank: const CellCoord(7, 2),
    );
    final job = world.constructions.single;
    expect(job.kind, WorldConstructionKind.bridge);
    expect(job.stagesDone, 0);
    expect(job.waterCells, const [CellCoord(6, 2)]);
    validateParcelWorldState(world, content, terrain);

    // The first check-in delivers the near bank as a road tile and
    // the state stays valid mid-construction.
    world = nextDay(world);
    expect(
      world.roads.any((road) => road.cell == const CellCoord(5, 2)),
      isTrue,
    );
    validateParcelWorldState(world, content, terrain);

    // Cell by cell to completion: the store validates on every save,
    // so the finished disconnected bridge must validate too — the
    // far bank opens as a road tile with it.
    while (world.constructions.isNotEmpty) {
      world = nextDay(world);
      validateParcelWorldState(world, content, terrain);
    }
    final bridge = world.bridges.single;
    expect(bridge.nearBank, const CellCoord(5, 2));
    expect(bridge.farBank, const CellCoord(7, 2));
    expect(
      world.roads.any((road) => road.cell == const CellCoord(7, 2)),
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
    var world = grantWorldDebugCoins(newWorld(), 200);
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
    expect(
      quoteStructurePlacement(
        world,
        content,
        terrain,
        catalogueId: 'small-home',
        origin: const CellCoord(17, 4),
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
      encodeSheetTables(worldToSheetTables(decoded)),
      encodeSheetTables(worldToSheetTables(world)),
    );
  });

  test('a partially funded road keeps its build direction across a reload', () {
    var world = grantWorldDebugCoins(newWorld(), 10);
    // A disconnected stretch running west: its start is the east
    // (larger) end, so the codec's smallest-end fallback alone would
    // resume funding from the wrong end after a reload.
    world = planRoadStretch(
      world,
      content,
      terrain,
      cells: const [CellCoord(3, 7), CellCoord(2, 7), CellCoord(1, 7)],
    );
    world = nextDay(world);
    expect(
      world.roads.any((road) => road.cell == const CellCoord(3, 7)),
      isTrue,
    );

    final decoded = sheetTablesToWorld(
      worldToSheetTables(world),
      content: content,
      terrainProvider: terrain,
    );
    final reloaded = decoded.constructions.single;
    expect(
      reloaded.roadCells.first,
      const CellCoord(3, 7),
      reason: 'the funded end marks the plan start',
    );
    final played = checkInWorldForToday(advanceWorldDays(decoded, 1), content);
    expect(
      played.roads.any((road) => road.cell == const CellCoord(2, 7)),
      isTrue,
      reason: 'creep continues from the delivered end',
    );
  });

  test('a vertical one-tile bridge round-trips through the save', () {
    var world = grantWorldDebugCoins(newWorld(), 60);
    // Two short roads north and south of the crossing; the banks
    // themselves stay vacant land so the span is a single vertical
    // tile between them.
    world = planAndSettleRoad(
      world,
      cells: const [CellCoord(5, 1), CellCoord(5, 2)],
    );
    world = planAndSettleRoad(
      world,
      cells: const [CellCoord(5, 6), CellCoord(5, 7)],
    );
    world = startBridgeConstruction(
      world,
      content,
      terrain,
      nearBank: const CellCoord(5, 3),
      farBank: const CellCoord(5, 5),
    );
    world = settleAll(world);

    final decoded = sheetTablesToWorld(
      worldToSheetTables(world),
      content: content,
      terrainProvider: terrain,
    );
    final bridge = decoded.bridges.single;
    expect(bridge.waterCells, const [CellCoord(5, 4)]);
    expect(bridge.nearBank, const CellCoord(5, 3));
    expect(bridge.farBank, const CellCoord(5, 5));
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

    // A north-south street down column 6.
    world = planAndSettleRoad(
      world,
      cells: const [CellCoord(6, 5), CellCoord(6, 6), CellCoord(6, 7)],
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
    world = planAndSettleRoad(world, cells: const [CellCoord(3, 5)]);
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
    world = planAndSettleRoad(world, cells: const [CellCoord(1, 6)]);
    world = planAndSettleRoad(world, cells: const [CellCoord(1, 7)]);
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

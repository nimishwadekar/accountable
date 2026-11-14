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

  ParcelWorldState newWorld() => newParcelWorldState(
    content: content,
    seed: 123456,
    terrainProvider: terrain,
    today: DateTime.utc(2026, 11, 2),
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
    test('starts empty with one free starter road in the first parcel', () {
      final world = newWorld();

      expect(world.parcels.single.coord, const ParcelCoord(0, 0));
      expect(world.structures, isEmpty);
      expect(world.coins, content.economy.startingTreasuryCoins);
      expect(world.population, 0);
      expect(world.roads.single.cell, const CellCoord(4, 4));
      expect(world.roads.single.style, RoadStyle.asphalt);
      expect(world.roads.single.pricePaid, 0);
      expect(world.builderCapacity, 1);
      expect(
        world.unlockedCatalogueIds,
        content.purchaseableModels
            .where((model) => model.unlockAtPopulation == 0)
            .map((model) => model.id)
            .toSet(),
        reason: 'starting unlocks are derived from the catalogue',
      );
      expect(
        () => validateParcelWorldState(world, content, terrain),
        returnsNormally,
      );
    });

    test(
      'check-in is explicit and idempotent; advancing days never funds work',
      () {
        var world = newWorld();
        world = checkInWorldForToday(world, content);
        // An empty town still pays the starter road's upkeep: the
        // report is the whole economy now, and no coin is granted.
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

  group('builder projects and staged construction', () {
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
          project.builderSlot,
          isNull,
          reason: 'road creep uses no builder',
        );
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
        expect(project.builderSlot, 0);
        expect(project.stagesDone, 0);
        expect(project.population, 1);
        expect(world.coins, content.economy.startingTreasuryCoins);
        expect(world.structures, isEmpty);
        expect(world.population, 0);
        expect(
          () => startStructureConstruction(
            world,
            content,
            terrain,
            catalogueId: 'cafe',
            origin: const CellCoord(4, 3),
          ),
          throwsA(isA<WorldRuleViolation>()),
          reason: 'one builder holds one building site',
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
          reason: 'completion frees the builder',
        );
        validateParcelWorldState(world, content, terrain);
      },
    );

    test('decorations place instantly, free, and use no builder', () {
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
      // No builder project for any of them, and none costs a coin.
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

    test('population gates unlock models and grant builders', () {
      // Content-driven progression: build cottages (1 population each)
      // until the 5-population models unlock.
      var world = grantWorldDebugCoins(newWorld(), 30);
      // Four cottages fit beside the starter road tile.
      for (final origin in [
        const CellCoord(3, 4),
        const CellCoord(5, 4),
        const CellCoord(4, 3),
      ]) {
        world = _buildCottage(world, content, terrain, origin, nextDay);
      }
      // Extend the road south so two more cottages fit beside it.
      world = planAndSettleRoad(
        world,
        cells: const [CellCoord(4, 5), CellCoord(4, 6)],
      );
      for (final origin in [
        const CellCoord(3, 5),
        const CellCoord(5, 5),
        const CellCoord(4, 7),
      ]) {
        world = _buildCottage(world, content, terrain, origin, nextDay);
      }

      expect(world.population, 6);
      expect(world.unlockedCatalogueIds, contains('medium-home'));
      expect(world.unlockedCatalogueIds, contains('fruit-market'));
      expect(world.unlockedCatalogueIds, isNot(contains('community-clinic')));
      validateParcelWorldState(world, content, terrain);
    });

    test('reconciliation grants unlocks and builders only upward', () {
      var world = grantWorldDebugCoins(newWorld(), 9);
      for (final origin in [
        const CellCoord(3, 4),
        const CellCoord(5, 4),
        const CellCoord(4, 3),
      ]) {
        world = _buildCottage(world, content, terrain, origin, nextDay);
      }
      expect(world.population, 3);

      // Simulate lowered content thresholds: a hand-built variant of the
      // bundle where medium-home unlocks at population 2 and a builder is
      // granted at population 2.
      final lowered = ContentBundle(
        manifest: content.manifest,
        terrain: content.terrain,
        catalogue: [
          for (final model in content.catalogue)
            model.id == 'medium-home'
                ? model.copyWith(unlockAtPopulation: 2)
                : model,
        ],
        sprites: content.sprites,
        economy: _economyWithProgression(content, [
          const BuilderProgressionStep(atPopulation: 2, capacity: 2),
        ]),
        ambience: content.ambience,
      );

      final reconciled = reconcileWorldProgression(world, lowered);
      expect(reconciled.unlockedCatalogueIds, contains('medium-home'));
      expect(reconciled.builderCapacity, 2);
      expect(
        reconcileWorldProgression(reconciled, lowered),
        same(reconciled),
        reason: 'reconciliation is idempotent',
      );
      // The original content still validates: capacity never goes down.
      validateParcelWorldState(reconciled, content, terrain);
    });
  });

  group('check-in economy', () {
    test('the report collects taxes, pays upkeep, then advances stages', () {
      var world = newWorld();
      // A settled home beside the starter road: taxes 3, upkeep from
      // the starter road tile only.
      world = _buildCottage(
        world,
        content,
        terrain,
        const CellCoord(3, 4),
        nextDay,
      );
      final before = world.coins;

      world = nextDay(world);
      final report = world.events.lastWhere(
        (event) => event.kind == 'check-in',
      );
      final home = content.structure('small-home')!;
      expect(report.payload['taxes'], home.taxCoins);
      expect(
        report.payload['upkeep'],
        home.upkeepCoins + 1,
        reason: 'home upkeep plus the starter road tile',
      );
      expect(report.payload['upkeepShortfall'], 0);
      expect(report.payload['net'], home.taxCoins - home.upkeepCoins - 1);
      expect(world.coins, before + home.taxCoins - home.upkeepCoins - 1);
      expect(
        world.totalCoinsEarned - world.totalCoinsSpent,
        world.coins,
        reason: 'the earned-minus-spent ledger still reconciles',
      );
    });

    test('tax and upkeep start on completion, at the next report', () {
      var world = newWorld();
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'small-home',
        origin: const CellCoord(3, 4),
      );
      // Two stages: the completing report itself collects nothing,
      // because taxes run before stages advance.
      world = nextDay(world);
      world = nextDay(world);
      final completing = world.events.lastWhere(
        (event) => event.kind == 'check-in',
      );
      expect(
        completing.payload['taxes'],
        0,
        reason: 'taxes run before stages advance',
      );
      expect(world.structures, hasLength(1));

      world = nextDay(world);
      final report = world.events.lastWhere(
        (event) => event.kind == 'check-in',
      );
      expect(
        report.payload['taxes'],
        content.structure('small-home')!.taxCoins,
      );
      expect(report.payload['upkeep'], 1, reason: 'the starter road tile');
    });

    test('an empty treasury floors at zero; work advances anyway', () {
      var world = grantWorldDebugCoins(
        newWorld(),
        content.economy.parcelBaseCoins - content.economy.startingTreasuryCoins,
      );
      world = purchaseAdjacentParcel(
        world,
        content,
        terrain,
        const ParcelCoord(1, 0),
      );
      expect(world.coins, 0);

      // A free home plan in a broke town: the starter road's upkeep
      // goes unpaid, the shortfall is reported, and the stages still
      // advance — money never blocks labor.
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

      // Recovery: the completed home's tax refills the treasury over
      // the following reports.
      world = nextDay(world);
      final home = content.structure('small-home')!;
      expect(world.coins, home.taxCoins - home.upkeepCoins - 1);
      validateParcelWorldState(world, content, terrain);
    });

    test('builders gate buildings only; creep rides alongside', () {
      var world = grantWorldDebugCoins(newWorld(), 200);
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'small-home',
        origin: const CellCoord(3, 4),
      );
      expect(
        () => startStructureConstruction(
          world,
          content,
          terrain,
          catalogueId: 'cafe',
          origin: const CellCoord(4, 3),
        ),
        throwsA(isA<WorldRuleViolation>()),
        reason: 'one builder holds one building site',
      );

      // Roads and bridges plan freely while the builder is busy.
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
      world = purchaseAdjacentParcel(
        world,
        content,
        terrain,
        const ParcelCoord(1, 0),
      );
      expect(world.parcels, hasLength(2));
      // So is the grass parcel across the water — adjacency is the only
      // purchase requirement now.
      world = purchaseAdjacentParcel(
        world,
        content,
        terrain,
        const ParcelCoord(2, 0),
      );
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

      // Three settled cottages: the price rises by exactly the
      // per-population surcharge — expanding a grown town costs more.
      for (final origin in [
        const CellCoord(3, 4),
        const CellCoord(5, 4),
        const CellCoord(4, 3),
      ]) {
        world = _buildCottage(world, content, terrain, origin, nextDay);
      }
      expect(world.population, 3);
      final atThree = quoteParcelPurchase(
        world,
        content,
        terrain,
        const ParcelCoord(1, 0),
      );
      expect(atThree.price, base + 3 * perPopulation);

      // The purchase charges the scaled price and records it.
      world = purchaseAdjacentParcel(
        world,
        content,
        terrain,
        const ParcelCoord(1, 0),
      );
      expect(world.parcels.last.pricePaid, base + 3 * perPopulation);
      expect(
        world.totalCoinsSpent,
        greaterThanOrEqualTo(base + 3 * perPopulation),
      );
      validateParcelWorldState(world, content, terrain);
    });

    test('water parcels are buyable but fog beyond the map is not', () {
      var world = grantWorldDebugCoins(newWorld(), 100);
      world = purchaseAdjacentParcel(
        world,
        content,
        terrain,
        const ParcelCoord(-1, 0),
      );
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
      world = purchaseAdjacentParcel(
        world,
        content,
        terrain,
        const ParcelCoord(-2, 0),
      );
      world = purchaseAdjacentParcel(
        world,
        content,
        terrain,
        const ParcelCoord(-3, 0),
      );
      expect(
        () => purchaseAdjacentParcel(
          world,
          content,
          terrain,
          const ParcelCoord(-4, 0),
        ),
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
    expect(job.builderSlot, isNull, reason: 'bridge creep uses no builder');
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
    world = purchaseAdjacentParcel(
      world,
      content,
      terrain,
      const ParcelCoord(1, 0),
    );
    world = purchaseAdjacentParcel(
      world,
      content,
      terrain,
      const ParcelCoord(2, 0),
    );
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
    world = purchaseAdjacentParcel(
      world,
      content,
      terrain,
      const ParcelCoord(1, 0),
    );
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

EconomyContent _economyWithProgression(
  ContentBundle content,
  List<BuilderProgressionStep> progression,
) => EconomyContent(
  startingTreasuryCoins: content.economy.startingTreasuryCoins,
  startingBuilderCapacity: content.economy.startingBuilderCapacity,
  roadTileCostCoins: content.economy.roadTileCostCoins,
  bridgeTileCostCoins: content.economy.bridgeTileCostCoins,
  parcelBaseCoins: content.economy.parcelBaseCoins,
  builderProgression: progression,
);

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

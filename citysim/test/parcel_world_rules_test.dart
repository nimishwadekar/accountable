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

  // Plans and fully funds a road stretch: one coin completes the
  // next tile in order from the start.
  ParcelWorldState planAndFundRoad(
    ParcelWorldState world, {
    required List<CellCoord> cells,
  }) {
    world = planRoadStretch(world, content, terrain, cells: cells);
    final project = world.constructions.single;
    for (final _ in cells) {
      world = fundRoadProject(world, content, terrain, projectId: project.id);
    }
    return world;
  }

  group('parcel-world bootstrap and clocks', () {
    test('starts empty with one free starter road in the first parcel', () {
      final world = newWorld();

      expect(world.parcels.single.coord, const ParcelCoord(0, 0));
      expect(world.structures, isEmpty);
      expect(world.coins, 0);
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
        world = checkInWorldForToday(world);
        expect(world.coins, 1);
        expect(checkInWorldForToday(world), same(world));

        world = advanceWorldDays(world, 1);
        expect(world.coins, 1, reason: 'a day advance does not check in');
        world = checkInWorldForToday(world);
        expect(world.coins, 2);

        final constructionDay = world.constructionDay;
        world = setWorldCalendarDate(
          world,
          world.simulatedDate.subtract(const Duration(days: 3)),
        );
        expect(world.constructionDay, constructionDay);
        expect(canCheckInWorldToday(world), isFalse);
        expect(checkInWorldForToday(world), same(world));
        expect(world.coins, 2);
      },
    );

    test('rewinding cannot backfill an uncredited earlier day', () {
      var world = newWorld();
      world = advanceWorldDays(world, 5);
      world = checkInWorldForToday(world);
      expect(world.coins, 1);
      world = setWorldCalendarDate(
        world,
        world.simulatedDate.subtract(const Duration(days: 4)),
      );

      expect(canCheckInWorldToday(world), isFalse);
      expect(checkInWorldForToday(world), same(world));
      expect(world.coins, 1);
    });
  });

  group('builder projects and manual funding', () {
    test('road plan occupies one builder; funding builds tiles in order', () {
      var world = grantWorldDebugCoins(newWorld(), 5);
      world = planRoadStretch(
        world,
        content,
        terrain,
        cells: const [CellCoord(5, 4), CellCoord(6, 4)],
      );
      final project = world.constructions.single;
      expect(project.kind, WorldConstructionKind.road);
      expect(project.builderSlot, 0);
      expect(project.coinsFunded, 0);
      expect(world.coins, 5, reason: 'planning a road is free');
      expect(world.roads, hasLength(1));
      expect(
        () => planRoadStretch(
          world,
          content,
          terrain,
          cells: const [CellCoord(3, 4)],
        ),
        throwsA(isA<WorldRuleViolation>()),
        reason: 'the assigned builder prevents a second planned place',
      );

      world = fundRoadProject(world, content, terrain, projectId: project.id);
      expect(world.coins, 4);
      expect(world.roads, hasLength(2));
      expect(world.constructions.single.coinsFunded, 1);
      expect(
        world.roads.any((road) => road.cell == const CellCoord(5, 4)),
        isTrue,
        reason: 'funding completes the first tile in plan order',
      );
      world = advanceWorldDays(world, 30);
      expect(world.constructions, hasLength(1));
      expect(world.roads, hasLength(2));

      world = fundRoadProject(world, content, terrain, projectId: project.id);
      expect(world.coins, 3);
      expect(world.roads, hasLength(3));
      expect(
        world.constructions,
        isEmpty,
        reason: 'completion releases the builder',
      );
      expect(world.totalCoinsSpent, 2);
      validateParcelWorldState(world, content, terrain);
    });

    test(
      'building sites are free plans and complete only when fully funded',
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
        expect(project.totalCostCoins, 3);
        expect(project.population, 1);
        expect(world.coins, 0);
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
        );

        world = advanceWorldDays(world, 14);
        expect(world.constructions.single.coinsFunded, 0);
        expect(world.structures, isEmpty);
        world = grantWorldDebugCoins(world, 3);
        world = fundStructureProject(
          world,
          content,
          projectId: project.id,
          amount: 1,
        );
        expect(world.coins, 2);
        expect(world.constructions.single.progress, closeTo(1 / 3, 0.001));
        world = advanceWorldDays(world, 7);
        expect(world.structures, isEmpty);
        world = fundStructureProject(
          world,
          content,
          projectId: project.id,
          amount: 2,
        );

        expect(world.coins, 0);
        expect(world.structures.single.catalogueId, 'small-home');
        expect(world.structures.single.population, 1);
        expect(world.population, 1);
        expect(world.constructions, isEmpty);
        validateParcelWorldState(world, content, terrain);
      },
    );

    test('decorations buy instantly and do not occupy the builder', () {
      var world = grantWorldDebugCoins(newWorld(), 2);
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'flower-garden',
        origin: const CellCoord(2, 2),
      );

      expect(world.coins, 1);
      expect(world.structures.single.kind, StructureKind.decoration);
      expect(world.structures.single.population, 0);
      expect(
        content.structure('flower-garden')!.assetRoles,
        contains(world.structures.single.assetRole),
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

      final placed = world.structures;
      expect(placed, hasLength(3));
      expect(
        placed.every((structure) => structure.kind == StructureKind.decoration),
        isTrue,
      );
      for (final catalogueId in ['street-lamp', 'rocks', 'common-tree']) {
        final structure = placed.singleWhere(
          (structure) => structure.catalogueId == catalogueId,
        );
        expect(
          content.structure(catalogueId)!.assetRoles,
          contains(structure.assetRole),
          reason: 'the rolled variant must be one of the model\'s roles',
        );
      }
      // No builder project for any of them; only the coin costs hit.
      expect(world.constructions, isEmpty);
      expect(
        world.coins,
        8 -
            content.structure('street-lamp')!.costCoins -
            content.structure('rocks')!.costCoins -
            content.structure('common-tree')!.costCoins,
      );
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
        final project = world.constructions.single;
        world = fundStructureProject(
          world,
          content,
          projectId: project.id,
          amount: project.totalCostCoins,
        );
      }
      world = planRoadStretch(
        world,
        content,
        terrain,
        cells: const [CellCoord(4, 5), CellCoord(4, 6)],
      );
      final roadProject = world.constructions.single;
      for (final _ in [const CellCoord(4, 5), const CellCoord(4, 6)]) {
        world = fundRoadProject(
          world,
          content,
          terrain,
          projectId: roadProject.id,
        );
      }
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
        final project = world.constructions.single;
        world = fundStructureProject(
          world,
          content,
          projectId: project.id,
          amount: project.totalCostCoins,
        );
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
        final project = replayed.constructions.single;
        replayed = fundStructureProject(
          replayed,
          content,
          projectId: project.id,
          amount: project.totalCostCoins,
        );
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
      world = planAndFundRoad(
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

    test('building door sides follow the adjacent road half', () {
      // The starter road sits at (4,4): grid east of (3,4), south of
      // (4,3), north of (4,5), and west of (5,4). North/east frontage
      // faces the door right (screen-right half); south/west faces left.
      var world = grantWorldDebugCoins(newWorld(), 30);
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'small-home',
        origin: const CellCoord(3, 4),
      );
      expect(world.constructions.single.facing, 'right');

      world = fundStructureProject(
        world,
        content,
        projectId: world.constructions.single.id,
        amount: world.constructions.single.totalCostCoins,
      );
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'small-home',
        origin: const CellCoord(4, 3),
      );
      expect(world.constructions.single.facing, 'left');
      expect(
        () => validateParcelWorldState(world, content, terrain),
        returnsNormally,
      );
    });

    test('door sides swap only while roads touch both halves', () {
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
      world = fundStructureProject(
        world,
        content,
        projectId: fixedProject.id,
        amount: fixedProject.totalCostCoins,
      );

      // Grow a crossroads so (6,5) and (5,6) each see roads on both
      // screen halves: (6,5) has its north (6,4) and west (5,5); (5,6)
      // has its north (5,5) and west (4,6). Each stretch is planned and
      // fully funded before the next claims the builder again.
      world = planAndFundRoad(
        world,
        cells: const [CellCoord(4, 5), CellCoord(5, 5)],
      );
      world = planAndFundRoad(world, cells: const [CellCoord(5, 4)]);
      world = planAndFundRoad(world, cells: const [CellCoord(6, 4)]);
      world = planAndFundRoad(world, cells: const [CellCoord(4, 6)]);

      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'small-home',
        origin: const CellCoord(6, 5),
      );
      final project = world.constructions.single;
      expect(project.facing, 'right', reason: 'both halves default right');

      world = swapStructureFacing(
        world,
        content,
        terrain,
        projectId: project.id,
      );
      expect(world.constructions.single.facing, 'left');
      world = fundStructureProject(
        world,
        content,
        projectId: project.id,
        amount: project.totalCostCoins,
      );

      // The player's pre-placement choice is honoured on both halves.
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'small-home',
        origin: const CellCoord(5, 6),
        preferredFacing: 'left',
      );
      expect(world.constructions.single.facing, 'left');
      world = fundStructureProject(
        world,
        content,
        projectId: world.constructions.single.id,
        amount: world.constructions.single.totalCostCoins,
      );

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
        world = _buildCottage(world, content, terrain, origin);
      }
      // Extend the road south so two more cottages fit beside it.
      world = planRoadStretch(
        world,
        content,
        terrain,
        cells: const [CellCoord(4, 5), CellCoord(4, 6)],
      );
      final roadProject = world.constructions.single;
      for (final _ in [const CellCoord(4, 5), const CellCoord(4, 6)]) {
        world = fundRoadProject(
          world,
          content,
          terrain,
          projectId: roadProject.id,
        );
      }
      for (final origin in [
        const CellCoord(3, 5),
        const CellCoord(5, 5),
        const CellCoord(4, 7),
      ]) {
        world = _buildCottage(world, content, terrain, origin);
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
        world = _buildCottage(world, content, terrain, origin);
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

  group('parcel purchase and natural terrain', () {
    test('parcels are neighboring purchases and owning land is not access', () {
      var world = grantWorldDebugCoins(newWorld(), 30);
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

    test('water parcels are buyable but open ocean beyond the map is not', () {
      var world = grantWorldDebugCoins(newWorld(), 100);
      world = purchaseAdjacentParcel(
        world,
        content,
        terrain,
        const ParcelCoord(-1, 0),
      );
      final queries = WorldQueries(world, terrain);
      expect(queries.terrainAt(const CellCoord(-4, 2)).kind, TerrainKind.water);
      expect(
        queries.isLandReachable(const CellCoord(-6, 2)),
        isFalse,
        reason:
            'owning the west water parcel does not reach the land '
            'beyond it',
      );
      // Buy out to the authored edge, then the ocean refuses.
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
        reason: 'beyond the authored map is open ocean',
      );
    });
  });

  test('a freshly planned bridge over land validates immediately', () {
    // Disconnected from any road, spanning owned dry land only — the
    // store validates on save, so a fresh plan (zero coins funded)
    // must satisfy save validation as-is.
    var world = grantWorldDebugCoins(newWorld(), 10);
    world = planAndFundRoad(
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
    expect(job.coinsFunded, 0);
    expect(job.waterCells, const [CellCoord(6, 2)]);
    validateParcelWorldState(world, content, terrain);

    // Funding the first coin completes the near bank as a road tile
    // and the state stays valid mid-construction.
    world = fundBridgeProject(world, content, projectId: job.id, amount: 1);
    expect(
      world.roads.any((road) => road.cell == const CellCoord(5, 2)),
      isTrue,
    );
    validateParcelWorldState(world, content, terrain);

    // Coin by coin to completion: the store validates on every save,
    // so the finished disconnected bridge must validate too — the
    // far bank opens as a road tile with it.
    while (world.constructions.isNotEmpty) {
      world = fundBridgeProject(world, content, projectId: job.id, amount: 1);
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
      world.coins,
      10 - 3 - bridge.pricePaid,
      reason: 'road tiles + bridge',
    );
  });

  test('a bridge project funds tile by tile before opening the far bank', () {
    var world = grantWorldDebugCoins(newWorld(), 100);
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
    world = planRoadStretch(
      world,
      content,
      terrain,
      cells: [for (var column = 5; column <= 6; column++) CellCoord(column, 4)],
    );
    final roadProject = world.constructions.single;
    for (var column = 5; column <= 6; column++) {
      world = fundRoadProject(
        world,
        content,
        terrain,
        projectId: roadProject.id,
      );
    }
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
    // Flat per-tile pricing: eight span tiles plus two road-priced banks.
    expect(quote.bridgeCost, 8 * content.economy.bridgeTileCostCoins + 2);

    world = startBridgeConstruction(
      world,
      content,
      terrain,
      nearBank: const CellCoord(7, 4),
      farBank: const CellCoord(16, 4),
    );
    final bridgeProject = world.constructions.single;
    final coinsAfterPlanning = world.coins;
    expect(world.bridges, isEmpty);
    world = advanceWorldDays(world, 100);
    expect(world.bridges, isEmpty, reason: 'days never fund anything');

    // The first coin completes the near bank as a road tile.
    world = fundBridgeProject(
      world,
      content,
      projectId: bridgeProject.id,
      amount: 1,
    );
    expect(
      world.roads.any((road) => road.cell == const CellCoord(7, 4)),
      isTrue,
      reason: 'the near bank becomes a road with its first coins',
    );
    expect(world.bridges, isEmpty);

    world = fundBridgeProject(
      world,
      content,
      projectId: bridgeProject.id,
      amount: world.constructions.single.coinsRemaining,
    );
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
      3,
      reason: 'buildings beside any road count as accessed',
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
    final project = world.constructions.single;
    world = fundRoadProject(world, content, terrain, projectId: project.id);
    world = fundRoadProject(world, content, terrain, projectId: project.id);
    expect(world.roads, hasLength(3), reason: 'starter + the isolated pair');
    validateParcelWorldState(world, content, terrain);
  });

  test('road sections span between junctions, elbows, and dead ends', () {
    var world = grantWorldDebugCoins(newWorld(), 20);
    // A T shape: a three-tile stem east of the starter road with a
    // two-tile branch south from its middle.
    world = planAndFundRoad(
      world,
      cells: const [CellCoord(5, 4), CellCoord(6, 4), CellCoord(7, 4)],
    );
    world = planAndFundRoad(
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
    final project = world.constructions.single;
    world = fundRoadProject(world, content, terrain, projectId: project.id);

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
    final project = world.constructions.single;
    world = fundRoadProject(world, content, terrain, projectId: project.id);
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
    final played = fundRoadProject(
      decoded,
      content,
      terrain,
      projectId: reloaded.id,
    );
    expect(
      played.roads.any((road) => road.cell == const CellCoord(2, 7)),
      isTrue,
      reason: 'funding continues from the funded end',
    );
  });

  test('a vertical one-tile bridge round-trips through the save', () {
    var world = grantWorldDebugCoins(newWorld(), 20);
    // Two short roads north and south of the crossing; the banks
    // themselves stay vacant land so the span is a single vertical
    // tile between them.
    world = planAndFundRoad(
      world,
      cells: const [CellCoord(5, 1), CellCoord(5, 2)],
    );
    world = planAndFundRoad(
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
    final job = world.constructions.single;
    world = fundBridgeProject(
      world,
      content,
      projectId: job.id,
      amount: job.totalCostCoins,
    );

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
}

EconomyContent _economyWithProgression(
  ContentBundle content,
  List<BuilderProgressionStep> progression,
) => EconomyContent(
  startingWalletCoins: content.economy.startingWalletCoins,
  startingBuilderCapacity: content.economy.startingBuilderCapacity,
  roadTileCostCoins: content.economy.roadTileCostCoins,
  bridgeTileCostCoins: content.economy.bridgeTileCostCoins,
  parcelBaseCoins: content.economy.parcelBaseCoins,
  builderProgression: progression,
);

ParcelWorldState _buildCottage(
  ParcelWorldState world,
  ContentBundle content,
  TerrainProvider terrain,
  CellCoord origin,
) {
  world = startStructureConstruction(
    world,
    content,
    terrain,
    catalogueId: 'small-home',
    origin: origin,
  );
  final project = world.constructions.single;
  return fundStructureProject(
    world,
    content,
    projectId: project.id,
    amount: project.totalCostCoins,
  );
}

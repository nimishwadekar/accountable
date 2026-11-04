import 'package:citysim/content/asset_content_source.dart';
import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:citysim/world/terrain_provider.dart';
import 'package:citysim/world/world_queries.dart';
import 'package:citysim/world/world_reducer.dart';
import 'package:citysim/world/world_rules.dart';
import 'package:citysim/world/world_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const terrain = DemoTerrainProvider();
  late ContentBundle content;

  setUpAll(() async {
    content = await loadContentBundle(const AssetContentSource());
  });

  ParcelWorldState newWorld() => newParcelWorldState(
    content: content,
    seed: 123456,
    terrainProvider: terrain,
    today: DateTime.utc(2026, 11, 2),
  );

  // Plans and fully funds a dirt-road stretch, waiting for the builder
  // slot to free up between stretches.
  ParcelWorldState planAndFundRoad(
    ParcelWorldState world, {
    required List<CellCoord> cells,
  }) {
    world = planRoadStretch(
      world,
      content,
      terrain,
      cells: cells,
      style: RoadStyle.dirt,
    );
    final project = world.constructions.single;
    for (final cell in cells) {
      world = fundRoadTile(
        world,
        content,
        terrain,
        projectId: project.id,
        cell: cell,
      );
    }
    return world;
  }

  group('parcel-world bootstrap and clocks', () {
    test('starts empty with one free dirt road in the first parcel', () {
      final world = newWorld();

      expect(world.parcels.single.coord, const ParcelCoord(0, 0));
      expect(world.structures, isEmpty);
      expect(world.coins, 0);
      expect(world.population, 0);
      expect(world.roads.single.cell, const CellCoord(4, 4));
      expect(world.roads.single.style, RoadStyle.dirt);
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
    test(
      'road plan occupies one builder; only finished-road frontier tiles fund',
      () {
        var world = grantWorldDebugCoins(newWorld(), 5);
        world = planRoadStretch(
          world,
          content,
          terrain,
          cells: const [CellCoord(5, 4), CellCoord(6, 4)],
          style: RoadStyle.asphalt,
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
            style: RoadStyle.dirt,
          ),
          throwsA(isA<WorldRuleViolation>()),
          reason: 'the assigned builder prevents a second planned place',
        );
        expect(
          () => quoteRoadTileFunding(
            world,
            content,
            terrainProvider: terrain,
            projectId: project.id,
            cell: const CellCoord(6, 4),
          ),
          throwsA(isA<WorldRuleViolation>()),
          reason: 'the second planned tile does not touch a completed road yet',
        );

        world = fundRoadTile(
          world,
          content,
          terrain,
          projectId: project.id,
          cell: const CellCoord(5, 4),
        );
        expect(world.coins, 4);
        expect(world.roads, hasLength(2));
        expect(world.constructions.single.coinsFunded, 1);
        world = advanceWorldDays(world, 30);
        expect(world.constructions, hasLength(1));
        expect(world.roads, hasLength(2));

        world = fundRoadTile(
          world,
          content,
          terrain,
          projectId: project.id,
          cell: const CellCoord(6, 4),
        );
        expect(world.coins, 3);
        expect(world.roads, hasLength(3));
        expect(
          world.constructions,
          isEmpty,
          reason: 'completion releases the builder',
        );
        expect(world.totalCoinsSpent, 2);
        validateParcelWorldState(world, content, terrain);
      },
    );

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
        style: RoadStyle.dirt,
      );
      final roadProject = world.constructions.single;
      for (final cell in [const CellCoord(4, 5), const CellCoord(4, 6)]) {
        world = fundRoadTile(
          world,
          content,
          terrain,
          projectId: roadProject.id,
          cell: cell,
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

      final decoded = ParcelWorldState.fromJson(world.toJson());
      expect(
        decoded.structures.map((s) => s.assetRole).toList(),
        structureRoles,
        reason: 'variant snapshots survive the save round-trip',
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

      // The chosen sides survive the save round-trip.
      final decoded = ParcelWorldState.fromJson(world.toJson());
      expect(
        decoded.structures.map((s) => s.facing).toList(),
        world.structures.map((s) => s.facing).toList(),
        reason: 'door-side snapshots survive the save round-trip',
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
        style: RoadStyle.dirt,
      );
      final roadProject = world.constructions.single;
      for (final cell in [const CellCoord(4, 5), const CellCoord(4, 6)]) {
        world = fundRoadTile(
          world,
          content,
          terrain,
          projectId: roadProject.id,
          cell: cell,
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
      world = purchaseAdjacentParcel(
        world,
        content,
        terrain,
        const ParcelCoord(1, 0),
      );
      expect(world.parcels, hasLength(2));
      expect(
        WorldQueries(world, terrain).isLandReachable(const CellCoord(11, 4)),
        isTrue,
      );
      expect(
        WorldQueries(world, terrain).isRoadConnected(const CellCoord(13, 4)),
        isFalse,
        reason: 'land reachability is not road connectivity',
      );
      expect(
        () => purchaseAdjacentParcel(
          world,
          content,
          terrain,
          const ParcelCoord(2, 0),
        ),
        throwsA(isA<WorldRuleViolation>()),
      );
    });

    test(
      'lake land is routeable around, but ocean-only parcels cannot be bought',
      () {
        var world = grantWorldDebugCoins(newWorld(), 100);
        world = purchaseAdjacentParcel(
          world,
          content,
          terrain,
          const ParcelCoord(-1, 0),
        );
        final queries = WorldQueries(world, terrain);
        expect(
          queries.terrainAt(const CellCoord(-4, 2)).kind,
          TerrainKind.lake,
        );
        expect(queries.isLandReachable(const CellCoord(-6, 2)), isTrue);
      },
    );
  });

  test('a bridge project needs manual funding before opening the far bank', () {
    var world = grantWorldDebugCoins(newWorld(), 100);
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
      cells: [
        for (var column = 5; column <= 11; column++) CellCoord(column, 4),
      ],
      style: RoadStyle.asphalt,
    );
    final roadProject = world.constructions.single;
    for (var column = 5; column <= 11; column++) {
      world = fundRoadTile(
        world,
        content,
        terrain,
        projectId: roadProject.id,
        cell: CellCoord(column, 4),
      );
    }
    final quote = quoteRiverBridge(
      world,
      content,
      terrain,
      nearBank: const CellCoord(11, 4),
      farBank: const CellCoord(13, 4),
    );
    expect(quote.waterCells, [const CellCoord(12, 4)]);

    world = startRiverBridgeConstruction(
      world,
      content,
      terrain,
      nearBank: const CellCoord(11, 4),
      farBank: const CellCoord(13, 4),
    );
    final bridgeProject = world.constructions.single;
    expect(world.coins, 85, reason: 'parcel (8) and road tiles (7) were paid');
    expect(
      WorldQueries(world, terrain).isRoadConnected(const CellCoord(13, 4)),
      isFalse,
    );
    world = advanceWorldDays(world, 100);
    expect(world.bridges, isEmpty);

    world = fundBridgeProject(
      world,
      projectId: bridgeProject.id,
      amount: bridgeProject.totalCostCoins,
    );
    final queries = WorldQueries(world, terrain);
    expect(world.bridges, hasLength(1));
    expect(queries.isLandReachable(const CellCoord(13, 4)), isTrue);
    expect(queries.isRoadConnected(const CellCoord(13, 4)), isTrue);
    expect(
      quoteStructurePlacement(
        world,
        content,
        terrain,
        catalogueId: 'small-home',
        origin: const CellCoord(14, 4),
      ).price,
      3,
    );
    world = purchaseAdjacentParcel(
      world,
      content,
      terrain,
      const ParcelCoord(2, 0),
    );
    expect(
      () => purchaseAdjacentParcel(
        world,
        content,
        terrain,
        const ParcelCoord(3, 0),
      ),
      throwsA(isA<WorldRuleViolation>()),
      reason: 'the ocean-only coast cannot be acquired',
    );
    validateParcelWorldState(world, content, terrain);
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
      style: RoadStyle.dirt,
    );
    final project = world.constructions.single;
    world = fundRoadTile(
      world,
      content,
      terrain,
      projectId: project.id,
      cell: const CellCoord(5, 4),
    );

    final decoded = ParcelWorldState.fromJson(world.toJson());
    validateParcelWorldState(decoded, content, terrain);
    expect(decoded.toJson(), world.toJson());
  });
}

EconomyContent _economyWithProgression(
  ContentBundle content,
  List<BuilderProgressionStep> progression,
) => EconomyContent(
  startingWalletCoins: content.economy.startingWalletCoins,
  startingBuilderCapacity: content.economy.startingBuilderCapacity,
  roadTileCostCoins: content.economy.roadTileCostCoins,
  bridgeBaseCoins: content.economy.bridgeBaseCoins,
  bridgePerWaterTileCoins: content.economy.bridgePerWaterTileCoins,
  parcelBaseCoins: content.economy.parcelBaseCoins,
  parcelDistanceStepCells: content.economy.parcelDistanceStepCells,
  parcelOwnedStepParcels: content.economy.parcelOwnedStepParcels,
  builderProgression: progression,
);

ParcelWorldState _buildCottage(
  ParcelWorldState world,
  ContentBundle content,
  DemoTerrainProvider terrain,
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

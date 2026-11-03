import 'package:accountable/citysim/world/coordinates.dart';
import 'package:accountable/citysim/world/terrain_provider.dart';
import 'package:accountable/citysim/world/world_content.dart';
import 'package:accountable/citysim/world/world_queries.dart';
import 'package:accountable/citysim/world/world_reducer.dart';
import 'package:accountable/citysim/world/world_rules.dart';
import 'package:accountable/citysim/world/world_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const terrain = DemoTerrainProvider();

  ParcelWorldState newWorld() => newParcelWorldState(
    seed: 123456,
    terrainProvider: terrain,
    today: DateTime.utc(2026, 11, 2),
  );

  group('parcel-world bootstrap and clocks', () {
    test('starts empty with one free dirt road in the first parcel', () {
      final world = newWorld();

      expect(world.parcels.single.coord, const ParcelCoord(0, 0));
      expect(world.structures, isEmpty);
      expect(world.coins, 0);
      expect(world.roads.single.cell, const CellCoord(4, 4));
      expect(world.roads.single.style, RoadStyle.dirt);
      expect(world.roads.single.pricePaid, 0);
      expect(world.builderCapacity, 1);
      expect(() => validateParcelWorldState(world, terrain), returnsNormally);
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
            terrain,
            cells: const [CellCoord(6, 4)],
            style: RoadStyle.dirt,
          ),
          throwsA(isA<WorldRuleViolation>()),
          reason: 'a road plan must start at the completed-road frontier',
        );
        expect(
          () => planRoadStretch(
            world,
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
            terrainProvider: terrain,
            projectId: project.id,
            cell: const CellCoord(6, 4),
          ),
          throwsA(isA<WorldRuleViolation>()),
          reason: 'the second planned tile does not touch a completed road yet',
        );

        world = fundRoadTile(
          world,
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
        validateParcelWorldState(world, terrain);
      },
    );

    test(
      'building sites are free plans and complete only when fully funded',
      () {
        var world = newWorld();
        world = startStructureConstruction(
          world,
          terrain,
          catalogueId: 'small-home',
          origin: const CellCoord(3, 4),
        );
        final project = world.constructions.single;
        expect(project.kind, WorldConstructionKind.structure);
        expect(project.totalCostCoins, 3);
        expect(world.coins, 0);
        expect(world.structures, isEmpty);
        expect(
          () => startStructureConstruction(
            world,
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
        world = fundStructureProject(world, projectId: project.id, amount: 1);
        expect(world.coins, 2);
        expect(world.constructions.single.progress, closeTo(1 / 3, 0.001));
        world = advanceWorldDays(world, 7);
        expect(world.structures, isEmpty);
        world = fundStructureProject(world, projectId: project.id, amount: 2);

        expect(world.coins, 0);
        expect(world.structures.single.catalogueId, 'small-home');
        expect(world.constructions, isEmpty);
        validateParcelWorldState(world, terrain);
      },
    );

    test('decorations buy instantly and do not occupy the builder', () {
      var world = grantWorldDebugCoins(newWorld(), 2);
      world = startStructureConstruction(
        world,
        terrain,
        catalogueId: 'flower-garden',
        origin: const CellCoord(2, 2),
      );

      expect(world.coins, 1);
      expect(world.structures.single.kind, StructureKind.decoration);
      expect(world.constructions, isEmpty);
      world = startStructureConstruction(
        world,
        terrain,
        catalogueId: 'small-home',
        origin: const CellCoord(3, 4),
      );
      expect(world.constructions, hasLength(1));
      validateParcelWorldState(world, terrain);
    });
  });

  group('parcel purchase and natural terrain', () {
    test(
      'parcels are neighboring purchases and owning land is not road access',
      () {
        var world = grantWorldDebugCoins(newWorld(), 30);
        world = purchaseAdjacentParcel(world, terrain, const ParcelCoord(1, 0));
        expect(world.parcels, hasLength(2));
        expect(
          WorldQueries(world, terrain).isLandReachable(const CellCoord(11, 4)),
          isTrue,
        );
        expect(
          WorldQueries(world, terrain).isLandReachable(const CellCoord(13, 4)),
          isFalse,
          reason: 'the river blocks land connectivity without a bridge',
        );
        expect(
          WorldQueries(world, terrain).isRoadConnected(const CellCoord(13, 4)),
          isFalse,
          reason: 'land reachability is not road connectivity',
        );
        expect(
          () => purchaseAdjacentParcel(world, terrain, const ParcelCoord(2, 0)),
          throwsA(isA<WorldRuleViolation>()),
        );
      },
    );

    test(
      'lake land is routeable around, but ocean-only parcels cannot be bought',
      () {
        var world = grantWorldDebugCoins(newWorld(), 100);
        world = purchaseAdjacentParcel(
          world,
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
    world = purchaseAdjacentParcel(world, terrain, const ParcelCoord(1, 0));
    world = planRoadStretch(
      world,
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
        terrain,
        projectId: roadProject.id,
        cell: CellCoord(column, 4),
      );
    }
    final quote = quoteRiverBridge(
      world,
      terrain,
      nearBank: const CellCoord(11, 4),
      farBank: const CellCoord(13, 4),
    );
    expect(quote.waterCells, [const CellCoord(12, 4)]);

    world = startRiverBridgeConstruction(
      world,
      terrain,
      nearBank: const CellCoord(11, 4),
      farBank: const CellCoord(13, 4),
    );
    final bridgeProject = world.constructions.single;
    expect(
      world.coins,
      85,
      reason: 'only parcels and completed road tiles were paid',
    );
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
    world = purchaseAdjacentParcel(world, terrain, const ParcelCoord(2, 0));
    expect(
      () => purchaseAdjacentParcel(world, terrain, const ParcelCoord(3, 0)),
      throwsA(isA<WorldRuleViolation>()),
      reason: 'the ocean-only coast cannot be acquired',
    );
    expect(
      quoteStructurePlacement(
        world,
        terrain,
        catalogueId: 'small-home',
        origin: const CellCoord(14, 4),
      ).price,
      3,
    );
    validateParcelWorldState(world, terrain);
  });

  test('active funded road project round-trips through the V2 save', () {
    var world = grantWorldDebugCoins(newWorld(), 20);
    world = purchaseAdjacentParcel(world, terrain, const ParcelCoord(1, 0));
    world = planRoadStretch(
      world,
      terrain,
      cells: const [CellCoord(5, 4), CellCoord(6, 4)],
      style: RoadStyle.dirt,
    );
    final project = world.constructions.single;
    world = fundRoadTile(
      world,
      terrain,
      projectId: project.id,
      cell: const CellCoord(5, 4),
    );

    final decoded = ParcelWorldState.fromJson(world.toJson());
    validateParcelWorldState(decoded, terrain);
    expect(decoded.toJson(), world.toJson());
  });
}

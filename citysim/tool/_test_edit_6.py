"""Third pass on the three stage-2 tests: correct road frontages."""

PATH = 'test/parcel_world_rules_test.dart'


def rep(label, old, new):
    src = open(PATH).read()
    assert old in src, f'missing: {label}'
    open(PATH, 'w').write(src.replace(old, new, 1))
    print(f'applied: {label}')


# 1. Vacant test: 3-tile road so the café's whole north side is lined.
rep(
    'vacant road',
    """      world = planAndSettleRoad(
        world,
        cells: const [CellCoord(5, 4), CellCoord(6, 4)],
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
      expect(world.structures.single.households, 0);""",
    """      world = planAndSettleRoad(
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
      expect(world.structures.single.households, 0);""",
)

rep(
    'vacant upkeep count',
    """      expect(
        report.payload['upkeep'],
        cafe.upkeepCoins + 3,
        reason:
            'full upkeep plus three road tiles — the '
            'anti-shop-farming guard',
      );
      expect(world.coins, before - cafe.upkeepCoins - 3);""",
    """      expect(
        report.payload['upkeep'],
        cafe.upkeepCoins + 4,
        reason:
            'full upkeep plus four road tiles — the '
            'anti-shop-farming guard',
      );
      expect(world.coins, before - cafe.upkeepCoins - 4);""",
)

# 2. Jobs test: same 3-tile road.
rep(
    'jobs road',
    """      world = planAndSettleRoad(
        world,
        cells: const [CellCoord(5, 4), CellCoord(6, 4)],
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
      expect(
        world.structures
            .singleWhere((s) => s.catalogueId == 'cafe')
            .households,""",
    """      world = planAndSettleRoad(
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
      expect(
        world.structures
            .singleWhere((s) => s.catalogueId == 'cafe')
            .households,""",
)

# 3. Service test: cottages clear of the road, fire station frontage.
rep(
    'service cottages',
    """      world = _buildCottage(
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
      expect(world.populationOf(content), 2);""",
    """      world = _buildCottage(
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
        const CellCoord(4, 3),
        nextDay,
      );
      expect(world.populationOf(content), 2);""",
)

print('all applied')

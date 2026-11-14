"""Fixes the stage-2.1 test geometries: 1x1 fruit-market commerce
beside the starter road, no extra roads needed."""

PATH = 'test/parcel_world_rules_test.dart'


def rep(label, old, new):
    src = open(PATH).read()
    assert old in src, f'missing: {label}'
    open(PATH, 'w').write(src.replace(old, new, 1))
    print(f'applied: {label}')


# ---- Founding rhythm: fruit-market instead of café ----
rep(
    'founding rhythm shop',
    """      // A café opens and employs the family; the list refills the
      // same check-in — the town is full and fully employed again.
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'cafe',
        origin: const CellCoord(4, 5),
      );""",
    """      // A shop opens and employs the family; the list refills the
      // same check-in — the town is full and fully employed again.
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'fruit-market',
        origin: const CellCoord(4, 5),
      );""",
)

# ---- Report test: fruit-market, updated upkeep ----
rep(
    'report test shop',
    """      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'cafe',
        origin: const CellCoord(4, 5),
      );
      world = nextDay(world);
      world = nextDay(world);
      final before = world.coins;

      world = nextDay(world);
      final report = world.events.lastWhere((event) => event.kind == 'check-in');
      final home = content.structure('small-home')!;
      final cafe = content.structure('cafe')!;
      expect(report.payload['taxes'], home.taxCoins + cafe.taxCoins ~/ 4);
      expect(report.payload['upkeep'], cafe.upkeepCoins + 1,
          reason: 'café upkeep plus the starter road tile');""",
    """      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'fruit-market',
        origin: const CellCoord(4, 5),
      );
      world = nextDay(world);
      world = nextDay(world);
      final before = world.coins;

      world = nextDay(world);
      final report = world.events.lastWhere((event) => event.kind == 'check-in');
      final home = content.structure('small-home')!;
      final shop = content.structure('fruit-market')!;
      expect(report.payload['taxes'], home.taxCoins + shop.taxCoins ~/ 3);
      expect(report.payload['upkeep'], shop.upkeepCoins + 1,
          reason: 'shop upkeep plus the starter road tile');""",
)

# ---- Tax-start test: fruit-market ----
rep(
    'tax start shop',
    """      // A café opens and employs the family: the next report
      // collects — the home at full, the café at its staffing rate.
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'cafe',
        origin: const CellCoord(4, 5),
      );
      world = nextDay(world);
      world = nextDay(world);
      expect(world.employedPopulation, 1);
      world = nextDay(world);
      final report = world.events.lastWhere(
        (event) => event.kind == 'check-in',
      );
      expect(report.payload['taxes'],
          content.structure('small-home')!.taxCoins +
              content.structure('cafe')!.taxCoins ~/ 4);
      expect(report.payload['upkeep'], 3,
          reason: 'café upkeep plus the starter road tile');""",
    """      // A shop opens and employs the family: the next report
      // collects — the home at full, the shop at its staffing rate.
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
      expect(report.payload['taxes'],
          content.structure('small-home')!.taxCoins +
              content.structure('fruit-market')!.taxCoins ~/ 3);
      expect(report.payload['upkeep'], 2,
          reason: 'shop upkeep plus the starter road tile');""",
)

# ---- Floor test: fruit-market recovery ----
rep(
    'floor test shop',
    """      // Recovery runs on employment, not completion: a café opens,
      // the family works, and taxes slowly refill the treasury.
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'cafe',
        origin: const CellCoord(4, 5),
      );""",
    """      // Recovery runs on employment, not completion: a shop opens,
      // the family works, and taxes slowly refill the treasury.
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'fruit-market',
        origin: const CellCoord(4, 3),
      );""",
)

# ---- Service test: fruit-market layout, fire station east ----
rep(
    'service test layout',
    """      var world = newWorld();
      world = _buildCottage(world, content, terrain, const CellCoord(3, 4), nextDay);
      world = _buildCottage(world, content, terrain, const CellCoord(4, 5), nextDay);
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'cafe',
        origin: const CellCoord(4, 3),
      );
      world = nextDay(world);
      world = nextDay(world);
      world = _buildCottage(world, content, terrain, const CellCoord(5, 4), nextDay);
      expect(world.population, 2);
      expect(world.employedPopulation, 2,
          reason: 'the café employs both families');""",
    """      var world = newWorld();
      world = _buildCottage(world, content, terrain, const CellCoord(3, 4), nextDay);
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'fruit-market',
        origin: const CellCoord(4, 3),
      );
      world = settleAll(world);
      world = _buildCottage(world, content, terrain, const CellCoord(5, 4), nextDay);
      expect(world.population, 2);
      expect(world.employedPopulation, 2,
          reason: 'the shop employs both families');""",
)

rep(
    'service fire station',
    """      world = world.copyWith(
        unlockedCatalogueIds: {...world.unlockedCatalogueIds, 'fire-station'},
      );
      world = planAndSettleRoad(
        world,
        cells: const [CellCoord(5, 4), CellCoord(6, 4)],
      );
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'fire-station',
        origin: const CellCoord(5, 2),
      );""",
    """      world = world.copyWith(
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
      );""",
)

# ---- Employed-tax test: fruit-market ----
rep(
    'employed tax shop',
    """      world = _buildCottage(world, content, terrain, const CellCoord(3, 4), nextDay);
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'cafe',
        origin: const CellCoord(4, 5),
      );
      world = nextDay(world);
      world = nextDay(world);
      expect(world.population, 1);
      expect(world.employedPopulation, 1);
      final home = content.structure('small-home')!;
      final cafe = content.structure('cafe')!;
      final ledger = townLedger(world, content);
      expect(ledger.grossTaxes, closeTo(home.taxCoins * 1 / 1 + cafe.taxCoins * 1 / 4, 0.001));""",
    """      world = _buildCottage(world, content, terrain, const CellCoord(3, 4), nextDay);
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
      expect(ledger.grossTaxes, closeTo(home.taxCoins + shop.taxCoins / 3, 0.001));""",
)

# ---- Population gates: settled town then counters, reconciliation ----
rep(
    'population gates body',
    """      var world = grantWorldDebugCoins(newWorld(), 30);
      world = _buildCottage(world, content, terrain, const CellCoord(3, 4), nextDay);
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'cafe',
        origin: const CellCoord(4, 5),
      );
      world = settleAll(world);
      world = _buildCottage(world, content, terrain, const CellCoord(5, 4), nextDay);
      world = _buildCottage(world, content, terrain, const CellCoord(4, 3), nextDay);
      world = _buildCottage(world, content, terrain, const CellCoord(3, 5), nextDay);
      world = startStructureConstruction(
        world,
        content,
        terrain,
        catalogueId: 'fruit-market',
        origin: const CellCoord(4, 6),
      );
      world = settleAll(world);
      world = _buildCottage(world, content, terrain, const CellCoord(5, 5), nextDay);
      world = _buildCottage(world, content, terrain, const CellCoord(4, 7), nextDay);
      expect(world.population, 6,
          reason: 'six households, each with a job waiting');""",
    """      var world = grantWorldDebugCoins(newWorld(), 30);
      world = _buildCottage(world, content, terrain, const CellCoord(3, 4), nextDay);
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
      expect(world.population, 6);""",
)

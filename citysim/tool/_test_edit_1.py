"""One-shot rewrite of the remaining coin-funding tests in
parcel_world_rules_test.dart to the staged check-in economy."""

PATH = 'test/parcel_world_rules_test.dart'


def rep(src, old, new, label, count=1):
    assert old in src, f'missing: {label}'
    return src.replace(old, new, count)


src = open(PATH).read()

# Population gates test: road funding -> settle.
src = rep(
    src,
    """      // Extend the road south so two more cottages fit beside it.
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
      }""",
    """      // Extend the road south so two more cottages fit beside it.
      world = planAndSettleRoad(
        world,
        cells: const [CellCoord(4, 5), CellCoord(4, 6)],
      );""",
    'population gates road',
)

# _economyWithProgression rename.
src = rep(
    src,
    'startingWalletCoins: content.economy.startingWalletCoins,',
    'startingTreasuryCoins: content.economy.startingTreasuryCoins,',
    'economy helper rename',
)

# _buildCottage: settle via check-ins, takes nextDay.
src = rep(
    src,
    """ParcelWorldState _buildCottage(
  ParcelWorldState world,
  ContentBundle content,
  ContentTerrainProvider terrain,
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
}""",
    """/// Plans a small home and lets the check-ins raise it to completion.
ParcelWorldState _buildCottage(
  ParcelWorldState world,
  ContentBundle content,
  ContentTerrainProvider terrain,
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
}""",
    'build cottage helper',
)

# _buildCottage call sites gain nextDay.
src = src.replace(
    '_buildCottage(world, content, terrain, origin)',
    '_buildCottage(world, content, terrain, origin, nextDay)',
)

open(PATH, 'w').write(src)
print('population gates + helpers done')

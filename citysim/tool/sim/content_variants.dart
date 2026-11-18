// Shared in-memory content variants for the simulation tools and the
// reviewer play CLI: the extended milestone ladder to one million,
// test-only medium- and high-density housing with scaled civic
// buildings, the blend-40 economy, and an enlarged map with lakes
// and scattered nature. Nothing here touches the shipped content
// files; every variant derives from a base bundle in memory, so the
// live game is never at risk and the baseline runs under identical
// code.

import 'dart:math' as math;

import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/world/coordinates.dart';

StructureDefinition _model(Map<String, Object?> json) =>
    StructureDefinition.fromJson(json);

/// Test-only density content, defined at full price scale
/// ($170/resident, $250/job) so an economy multiplier applies
/// uniformly to shipped and test models alike.
const List<Map<String, Object>> densityModels = [
  {
    'id': 'midrise',
    'name': 'Mid-Rise Block',
    'description': 'Test-only medium density housing.',
    'kind': 'building',
    'subcategory': 'apartments',
    'footprint': {'columns': 2, 'rows': 2},
    'assetRoles': ['midrise'],
    'constructionStages': 5,
    'costCoins': 0,
    'population': 100,
    'jobs': 0,
    'serviceCapacity': 0,
    'taxCoins': 17000,
    'upkeepCoins': 2500,
    'enabled': true,
  },
  {
    'id': 'tower',
    'name': 'Residential Tower',
    'description': 'Test-only high density housing.',
    'kind': 'building',
    'subcategory': 'apartments',
    'footprint': {'columns': 2, 'rows': 2},
    'assetRoles': ['tower'],
    'constructionStages': 6,
    'costCoins': 0,
    'population': 400,
    'jobs': 0,
    'serviceCapacity': 0,
    'taxCoins': 68000,
    'upkeepCoins': 10000,
    'enabled': true,
  },
  {
    'id': 'tower-small',
    'name': 'Small Tower',
    'description': 'Test-only high density housing, the grind bracket.',
    'kind': 'building',
    'subcategory': 'apartments',
    'footprint': {'columns': 2, 'rows': 2},
    'assetRoles': ['tower-small'],
    'constructionStages': 5,
    'costCoins': 0,
    'population': 200,
    'jobs': 0,
    'serviceCapacity': 0,
    'taxCoins': 34000,
    'upkeepCoins': 5000,
    'enabled': true,
  },
  {
    'id': 'mega-tower',
    'name': 'Mega Tower',
    'description': 'Test-only very high density housing.',
    'kind': 'building',
    'subcategory': 'apartments',
    'footprint': {'columns': 2, 'rows': 2},
    'assetRoles': ['mega-tower'],
    'constructionStages': 8,
    'costCoins': 0,
    'population': 1200,
    'jobs': 0,
    'serviceCapacity': 0,
    'taxCoins': 204000,
    'upkeepCoins': 30000,
    'enabled': true,
  },
  {
    'id': 'office-plaza',
    'name': 'Office Plaza',
    'description': 'Test-only high density workplaces.',
    'kind': 'building',
    'subcategory': 'offices',
    'footprint': {'columns': 2, 'rows': 2},
    'assetRoles': ['office-plaza'],
    'constructionStages': 6,
    'costCoins': 0,
    'population': 0,
    'jobs': 1200,
    'serviceCapacity': 0,
    'taxCoins': 300000,
    'upkeepCoins': 60000,
    'enabled': true,
  },
  {
    'id': 'regional-hospital',
    'name': 'Regional Hospital',
    'description': 'Test-only scaled health service.',
    'kind': 'building',
    'subcategory': 'civic',
    'footprint': {'columns': 2, 'rows': 2},
    'assetRoles': ['regional-hospital'],
    'constructionStages': 6,
    'costCoins': 0,
    'population': 0,
    'jobs': 0,
    'serviceCategory': 'health',
    'serviceCapacity': 50000,
    'taxCoins': 0,
    'upkeepCoins': 250000,
    'enabled': true,
  },
  {
    'id': 'metro-police',
    'name': 'Metro Police HQ',
    'description': 'Test-only scaled police service.',
    'kind': 'building',
    'subcategory': 'civic',
    'footprint': {'columns': 2, 'rows': 2},
    'assetRoles': ['metro-police'],
    'constructionStages': 6,
    'costCoins': 0,
    'population': 0,
    'jobs': 0,
    'serviceCategory': 'police',
    'serviceCapacity': 100000,
    'taxCoins': 0,
    'upkeepCoins': 250000,
    'enabled': true,
  },
  {
    'id': 'metro-fire',
    'name': 'Metro Fire HQ',
    'description': 'Test-only scaled fire service.',
    'kind': 'building',
    'subcategory': 'civic',
    'footprint': {'columns': 2, 'rows': 2},
    'assetRoles': ['metro-fire'],
    'constructionStages': 6,
    'costCoins': 0,
    'population': 0,
    'jobs': 0,
    'serviceCategory': 'fire',
    'serviceCapacity': 100000,
    'taxCoins': 0,
    'upkeepCoins': 250000,
    'enabled': true,
  },
];

MilestoneDefinition rung(
  String id,
  String name,
  int population,
  List<String> models,
) => MilestoneDefinition(
  id: id,
  name: name,
  population: population,
  models: models,
);

/// The designed extension: rungs every ×3 past the shipped ladder,
/// density content at each new rung, honor rungs at the top.
final List<MilestoneDefinition> designedExtension = [
  rung('district', 'District', 6000, ['midrise']),
  rung('borough', 'Borough', 20000, [
    'tower',
    'regional-hospital',
    'metro-police',
    'metro-fire',
  ]),
  rung('conurbation', 'Conurbation', 60000, ['office-plaza']),
  rung('megacity', 'Megacity', 200000, ['mega-tower']),
  rung('metroplex', 'Metroplex', 600000, []),
  rung('megalopolis', 'Megalopolis', 1000000, []),
];

/// The enlarged map: an 18×18 charted island — room for roughly a
/// million people at tower density — with an east coast, two lakes,
/// and scattered nature at the shipped map's density, so the
/// land-clearing chore and shoreline variety play like the real map.
TerrainContent bigIslandMap() {
  final parcels = <ParcelCoord, TerrainKind>{};
  for (var x = -9; x <= 8; x++) {
    for (var y = -9; y <= 8; y++) {
      parcels[ParcelCoord(x, y)] = TerrainKind.grass;
    }
  }
  // The east coast and two inland lakes. Water never severs the
  // island, so the pilot needs no bridge command.
  for (var y = -9; y <= 8; y++) {
    parcels[ParcelCoord(8, y)] = TerrainKind.water;
  }
  for (final coord in [
    ParcelCoord(3, 4),
    ParcelCoord(4, 4),
    ParcelCoord(3, 5),
    ParcelCoord(4, 5),
    ParcelCoord(-6, -5),
  ]) {
    parcels[coord] = TerrainKind.water;
  }
  // Nature at ~15% of land cells, from the shipped map's palette,
  // rolled deterministically so every run sees the same wilderness.
  final rng = math.Random(20261117);
  const palette = [
    ('pine-tree', 'pine-medium'),
    ('pine-tree', 'pine-small'),
    ('pine-tree', 'pine-tall'),
    ('common-tree', 'tree-common-large'),
    ('common-tree', 'tree-common-medium'),
    ('wild-grass', 'weed-large-a'),
    ('wild-grass', 'weed-medium'),
    ('wild-grass', 'weed-small'),
  ];
  final props = <TerrainProp>[];
  for (final entry in parcels.entries) {
    if (entry.value == TerrainKind.water) continue;
    for (final cell in entry.key.cells(defaultParcelSize)) {
      if (rng.nextDouble() >= 0.15) continue;
      final pick = palette[rng.nextInt(palette.length)];
      props.add(
        TerrainProp(
          catalogueId: pick.$1,
          cell: cell,
          subtileX: rng.nextInt(8),
          subtileY: rng.nextInt(8),
          assetRole: pick.$2,
        ),
      );
    }
  }
  return TerrainContent(
    generatorVersion: 1,
    parcels: parcels,
    tiles: const {},
    props: props,
  );
}

/// The full "road to a million" bundle: the shipped catalogue plus
/// the density models, the designed ladder extension, the blend-40
/// economy (taxes ×0.4, parcels 30,000 + 400/population), and the
/// enlarged map.
ContentBundle ladderABundle(ContentBundle base) {
  final extras = [
    for (final json in densityModels) _model(json.cast<String, Object?>()),
  ];
  return ContentBundle(
    manifest: base.manifest,
    catalogue: [
      for (final model in [...base.catalogue, ...extras])
        model.copyWith(taxCoins: (model.taxCoins * 0.4).round()),
    ],
    sprites: base.sprites,
    economy: base.economy.copyWith(
      parcelBaseCoins: 30000,
      parcelPerPopulationCoins: 400,
    ),
    ambience: base.ambience,
    terrain: bigIslandMap(),
    progression: ProgressionContent(
      milestones: [...base.progression.milestones, ...designedExtension],
    ),
  );
}

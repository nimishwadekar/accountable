import 'coordinates.dart';

enum RoadStyle { dirt, asphalt }

enum StructureKind { building, decoration }

class StructureDefinition {
  const StructureDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.kind,
    required this.assetRole,
    required this.footprintColumns,
    required this.footprintRows,
    required this.costCoins,
    required this.milestoneBuildings,
  });

  final String id;
  final String name;
  final String description;
  final StructureKind kind;
  final String assetRole;
  final int footprintColumns;
  final int footprintRows;
  final int costCoins;
  final int milestoneBuildings;

  String get costLabel => '$costCoins ${costCoins == 1 ? 'coin' : 'coins'}';
}

class SpriteDefinition {
  const SpriteDefinition({
    required this.assetPath,
    this.renderScale = 0.5,
    this.groundAnchorX = 0.5,
    this.groundAnchorY = 1,
    this.baseOffsetY = 0,
    this.sways = false,
  });

  final String assetPath;
  final double renderScale;
  final double groundAnchorX;
  final double groundAnchorY;

  /// Pixels of sprite content that hang below the tile's ground diamond
  /// (for example bridge support posts). The renderer keeps the sprite's
  /// aspect ratio and aligns the diamond's south tip with the cell's south
  /// vertex, letting this overhang extend past it.
  final double baseOffsetY;

  /// Whether the ambient renderer gently rocks this sprite around its
  /// ground anchor to suggest wind. Only vegetation should set this;
  /// buildings and other rigid objects stay still.
  final bool sways;
}

const structureCatalogue = <StructureDefinition>[
  StructureDefinition(
    id: 'small-home',
    name: 'Sunny cottage',
    description: 'A welcoming home beside a connected road.',
    kind: StructureKind.building,
    assetRole: 'home-small-yellow',
    footprintColumns: 1,
    footprintRows: 1,
    costCoins: 3,
    milestoneBuildings: 0,
  ),
  StructureDefinition(
    id: 'cafe',
    name: 'Corner cafe',
    description: 'A neighborhood stop along the road.',
    kind: StructureKind.building,
    assetRole: 'cafe',
    footprintColumns: 1,
    footprintRows: 1,
    costCoins: 3,
    milestoneBuildings: 0,
  ),
  StructureDefinition(
    id: 'flower-garden',
    name: 'Flower garden',
    description: 'A small patch of color for an open corner.',
    kind: StructureKind.decoration,
    assetRole: 'flowers-yellow',
    footprintColumns: 1,
    footprintRows: 1,
    costCoins: 1,
    milestoneBuildings: 0,
  ),
  StructureDefinition(
    id: 'pine-tree',
    name: 'Pine tree',
    description: 'A quiet evergreen on vacant land.',
    kind: StructureKind.decoration,
    assetRole: 'pine-medium',
    footprintColumns: 1,
    footprintRows: 1,
    costCoins: 2,
    milestoneBuildings: 0,
  ),
  StructureDefinition(
    id: 'medium-home',
    name: 'Blue family home',
    description: 'A larger home unlocked by a growing settlement.',
    kind: StructureKind.building,
    assetRole: 'home-medium-blue',
    footprintColumns: 1,
    footprintRows: 1,
    costCoins: 4,
    milestoneBuildings: 5,
  ),
  StructureDefinition(
    id: 'fruit-market',
    name: 'Fruit market',
    description: 'A colorful market for a connected neighborhood.',
    kind: StructureKind.building,
    assetRole: 'fruit-market',
    footprintColumns: 1,
    footprintRows: 1,
    costCoins: 5,
    milestoneBuildings: 5,
  ),
  StructureDefinition(
    id: 'community-clinic',
    name: 'Community clinic',
    description: 'A civic building unlocked as the settlement grows.',
    kind: StructureKind.building,
    assetRole: 'clinic',
    footprintColumns: 1,
    footprintRows: 1,
    costCoins: 6,
    milestoneBuildings: 10,
  ),
  StructureDefinition(
    id: 'apartments',
    name: 'Brick apartments',
    description: 'A denser home for a larger city center.',
    kind: StructureKind.building,
    assetRole: 'apartments-brick-brown',
    footprintColumns: 2,
    footprintRows: 2,
    costCoins: 8,
    milestoneBuildings: 20,
  ),
  StructureDefinition(
    id: 'city-office',
    name: 'Cedar office',
    description: 'A compact workplace for an established city.',
    kind: StructureKind.building,
    assetRole: 'office-medium-green',
    footprintColumns: 2,
    footprintRows: 2,
    costCoins: 8,
    milestoneBuildings: 20,
  ),
];

final structureById = {
  for (final definition in structureCatalogue) definition.id: definition,
};

const spriteManifest = <String, SpriteDefinition>{
  'terrain.grass': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_ground_grass.png',
  ),
  'terrain.grass.puddle': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_ground_grass_puddle_clean.png',
  ),
  'terrain.dirt': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_ground_dirt.png',
  ),
  'terrain.asphalt': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_ground_asphalt.png',
  ),
  'terrain.concrete': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_ground_concrete.png',
  ),
  'terrain.water': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_ground_water.png',
  ),
  'shore.grass.edge.n': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_ground_grass_wateredge_N_clean.png',
  ),
  'shore.grass.edge.e': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_ground_grass_wateredge_E_clean.png',
  ),
  'shore.grass.edge.s': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_ground_grass_wateredge_S_clean.png',
  ),
  'shore.grass.edge.w': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_ground_grass_wateredge_W_clean.png',
  ),
  'shore.grass.corner.n': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_ground_grass_watercorner_N_clean.png',
  ),
  'shore.grass.corner.e': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_ground_grass_watercorner_E_clean.png',
  ),
  'shore.grass.corner.s': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_ground_grass_watercorner_S_clean.png',
  ),
  'shore.grass.corner.w': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_ground_grass_watercorner_W_clean.png',
  ),
  'shore.dirt.edge.n': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_ground_dirt_wateredge_N_clean.png',
  ),
  'shore.dirt.edge.e': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_ground_dirt_wateredge_E_clean.png',
  ),
  'shore.dirt.edge.s': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_ground_dirt_wateredge_S_clean.png',
  ),
  'shore.dirt.edge.w': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_ground_dirt_wateredge_W_clean.png',
  ),
  'shore.dirt.corner.n': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_ground_dirt_watercorner_N_clean.png',
  ),
  'shore.dirt.corner.e': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_ground_dirt_watercorner_E_clean.png',
  ),
  'shore.dirt.corner.s': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_ground_dirt_watercorner_S_clean.png',
  ),
  'shore.dirt.corner.w': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_ground_dirt_watercorner_W_clean.png',
  ),
  'shore.grass.quarter.ne': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_ground_grass_water_NE_clean.png',
  ),
  'shore.grass.quarter.se': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_ground_grass_water_SE_clean.png',
  ),
  'shore.grass.quarter.sw': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_ground_grass_water_SW_clean.png',
  ),
  'shore.grass.quarter.nw': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_ground_grass_water_NW_clean.png',
  ),
  'shore.dirt.quarter.ne': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_ground_dirt_water_NE_clean.png',
  ),
  'shore.dirt.quarter.se': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_ground_dirt_water_SE_clean.png',
  ),
  'shore.dirt.quarter.sw': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_ground_dirt_water_SW_clean.png',
  ),
  'shore.dirt.quarter.nw': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_ground_dirt_water_NW_clean.png',
  ),
  'road.end.ne': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_road_end_NE_normal.png',
  ),
  'road.end.nw': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_road_end_NW_normal.png',
  ),
  'road.end.se': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_road_end_SE_normal.png',
  ),
  'road.end.sw': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_road_end_SW_normal.png',
  ),
  'road.straight.se': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_road_straight_SE_normal.png',
  ),
  'road.straight.sw': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_road_straight_SW_normal.png',
  ),
  'road.corner.n': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_road_corner_N_normal.png',
  ),
  'road.corner.e': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_road_corner_E_normal.png',
  ),
  'road.corner.s': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_road_corner_S_normal.png',
  ),
  'road.corner.w': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_road_corner_W_normal.png',
  ),
  'road.t.ne': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_road_intersection_NE_normal.png',
  ),
  'road.t.nw': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_road_intersection_NW_normal.png',
  ),
  'road.t.se': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_road_intersection_SE_normal.png',
  ),
  'road.t.sw': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_road_intersection_SW_normal.png',
  ),
  'road.cross': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_road_xsing_normal.png',
  ),
  'bridge.body.se': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_road_bridge_body_SE_normal.png',
    baseOffsetY: 12,
  ),
  'bridge.body.sw': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_road_bridge_body_SW_normal.png',
    baseOffsetY: 12,
  ),
  'bridge.ramp.ne': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_road_bridge_ramp_NE_normal.png',
  ),
  'bridge.ramp.nw': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_road_bridge_ramp_NW_normal.png',
  ),
  'bridge.ramp.se': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_road_bridge_ramp_SE_normal.png',
  ),
  'bridge.ramp.sw': SpriteDefinition(
    assetPath: 'Roads and Grounds/tile_road_bridge_ramp_SW_normal.png',
  ),
  'home-small-yellow': SpriteDefinition(
    assetPath: 'Buildings/bld_house_small_yellow_a.png',
  ),
  'home-medium-blue': SpriteDefinition(
    assetPath: 'Buildings/bld_house_medium_blue_a.png',
  ),
  'cafe': SpriteDefinition(assetPath: 'Buildings/bld_cafe_a.png'),
  'fruit-market': SpriteDefinition(assetPath: 'Buildings/bld_fruitstand_a.png'),
  'clinic': SpriteDefinition(assetPath: 'Buildings/bld_clinic_a.png'),
  'apartments-brick-brown': SpriteDefinition(
    assetPath: 'Buildings/bld_apartments_brickbrown_a.png',
  ),
  'office-medium-green': SpriteDefinition(
    assetPath: 'Buildings/bld_office_medium_green_a.png',
  ),
  'flowers-yellow': SpriteDefinition(
    assetPath: 'Props/prop_flowers_yellow.png',
    renderScale: 2,
    groundAnchorY: 0.95,
    sways: true,
  ),
  'pine-medium': SpriteDefinition(
    assetPath: 'Props/prop_tree_pine_medium.png',
    sways: true,
  ),
};

String citysimAssetPath(String role) =>
    'assets/citysim/buggy_studio/${spriteManifest[role]!.assetPath}';

enum WorldMilestone { homes5, homes10, homes20 }

WorldMilestone? milestoneForCompletedBuildings(int count) {
  if (count >= 20) return WorldMilestone.homes20;
  if (count >= 10) return WorldMilestone.homes10;
  if (count >= 5) return WorldMilestone.homes5;
  return null;
}

bool isCatalogueUnlocked(String id, int completedBuildingCount) {
  final definition = structureById[id];
  return definition != null &&
      completedBuildingCount >= definition.milestoneBuildings;
}

int parcelCost(ParcelCoord coord, int ownedCount) {
  // Stable base cost with a modest outward step, avoiding explosive pricing.
  final distance = coord.x.abs() + coord.y.abs();
  return 8 + (distance ~/ 8) + ((ownedCount - 1).clamp(0, 100) ~/ 12);
}

int roadCost(RoadStyle style) => 1;

int bridgeCost(int waterSpanLength) => 4 + waterSpanLength * 2;

CellCoord cellFromFootprintOrigin(
  CellCoord origin,
  int dx,
  int dy,
  int quarterTurns,
) {
  return switch (quarterTurns % 4) {
    0 => origin.offset(dx, dy),
    1 => origin.offset(-dy, dx),
    2 => origin.offset(-dx, -dy),
    _ => origin.offset(dy, -dx),
  };
}

List<CellCoord> structureFootprint(
  StructureDefinition definition,
  CellCoord origin, {
  int quarterTurns = 0,
}) => [
  for (var row = 0; row < definition.footprintRows; row++)
    for (var column = 0; column < definition.footprintColumns; column++)
      cellFromFootprintOrigin(origin, column, row, quarterTurns),
];

Map<String, Object?> worldJsonMap(Object? value) =>
    (value as Map).map((key, value) => MapEntry(key as String, value));

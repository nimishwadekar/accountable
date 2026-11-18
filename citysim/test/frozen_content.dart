/// Frozen, hand-authored content for game-behaviour tests.
///
/// The shipped JSONs under `assets/content/` are *live data* — the
/// editor dashboard and the author retune them daily, and every retune
/// would break a test that loads them. So every suite that tests game
/// *rules* — reducer, codec, economy math, rendering — plays against
/// this frozen bundle instead: a small, self-consistent world whose
/// values nobody retunes. Edit this file only when the content schema
/// or a game rule changes out from under it, never because a shipped
/// value moved.
///
/// The bundle is a curated snapshot of the shipped content as of
/// 2026-11: the models the tests exercise (with their live numbers, so
/// economy arithmetic keeps its meaning), the code-referenced sprite
/// roles with their painted lane and walkable masks, and a compact map
/// that reproduces the shipped map's geography around the origin —
/// water parcels flanking parcel (0,0) east and west, land beyond
/// them, and fog past the authored edge. Sprite paths point at the
/// real art files, so rendering tests draw the actual PNGs.
///
/// Four suites deliberately stay on live data, because live data is
/// their subject: `shipped_content_test` (pins on the shipped JSONs),
/// `parcel_world_content_test` (content validation rules),
/// `live_save_test` (the bundled save sheets loading against the
/// shipped content), and `world_perf_probe_test` (render performance
/// measured on the real town).
library;

import 'package:citysim/content/content_bundle.dart';

/// The frozen category maps, typed like decoded JSON — the same shape
/// `AssetContentSource` produces — so variants can spread, tweak, and
/// re-encode them the way the real content pipeline does.
Map<String, Map<String, Object?>> frozenCategories() => {
  'manifest.json': {'schemaVersion': 3},

  'catalogue.json': {'models': _catalogue},

  'sprites.json': {'sprites': _sprites},

  'economy.json': _economy,

  'ambience.json': _ambience,

  'terrain.json': {
    'generatorVersion': 1,
    // The origin strait: water parcels at (-1,0) and (1,0) flank the
    // founding parcel (0,0) east and west, with grass beyond on both
    // sides — the shipped map's local geography. Everything past the
    // authored rectangle is fog, so (-4,0) and (4,4) sit off the map.
    'parcels': {
      for (var column = -3; column <= 6; column++)
        for (var row = -1; row <= 2; row++)
          '$column,$row': (column == -1 || column == 1) && row == 0
              ? 'water'
              : 'grass',
    },
  },

  'progression.json': {
    'milestones': [
      {
        'id': 'homestead',
        'name': 'Homestead',
        'population': 0,
        'models': [
          'small-home',
          'cafe',
          'flower-garden',
          'pine-tree',
          'common-tree',
          'wild-grass',
          'street-lamp',
          'rocks',
        ],
      },
      {
        'id': 'hamlet',
        'name': 'Hamlet',
        'population': 15,
        'models': ['medium-home', 'fruit-market'],
      },
      {
        'id': 'village',
        'name': 'Village',
        'population': 50,
        'models': ['community-clinic', 'large-home'],
      },
      // The shipped ladder keeps its thresholds; the models the frozen
      // catalogue omits simply unlock nothing here.
      {'id': 'town', 'name': 'Town', 'population': 120, 'models': []},
      {
        'id': 'city',
        'name': 'City',
        'population': 300,
        'models': ['apartments', 'fire-station', 'police-station'],
      },
      {
        'id': 'metropolis',
        'name': 'Metropolis',
        'population': 800,
        'models': ['tall-office'],
      },
      {
        'id': 'regional-capital',
        'name': 'Regional Capital',
        'population': 2000,
        'models': [],
      },
    ],
  },
};

/// The frozen bundle, parsed and validated like shipped content.
/// Synchronous — no asset loading, so pure rule tests need no binding.
ContentBundle frozenContent() {
  final categories = frozenCategories();
  return parseContentBundle(
    manifest: categories['manifest.json']!,
    catalogue: categories['catalogue.json']!,
    sprites: categories['sprites.json']!,
    economy: categories['economy.json']!,
    ambience: categories['ambience.json']!,
    terrain: categories['terrain.json']!,
    progression: categories['progression.json']!,
  );
}

// ---------------------------------------------------------------------------
// Catalogue
// ---------------------------------------------------------------------------

Map<String, Object?> _building(
  String id,
  String name,
  String description,
  String subcategory,
  List<String> assetRoles, {
  required int columns,
  required int rows,
  int population = 0,
  int jobs = 0,
  int taxCoins = 0,
  int upkeepCoins = 0,
  int constructionStages = 1,
  String? serviceCategory,
  int serviceCapacity = 0,
}) => {
  'id': id,
  'name': name,
  'description': description,
  'kind': 'building',
  'assetRoles': assetRoles,
  'subcategory': subcategory,
  'footprint': {'columns': columns, 'rows': rows},
  'costCoins': 0,
  'population': population,
  'taxCoins': taxCoins,
  'upkeepCoins': upkeepCoins,
  'constructionStages': constructionStages,
  'jobs': jobs,
  'serviceCategory': ?serviceCategory,
  'serviceCapacity': serviceCapacity,
  'enabled': true,
};

Map<String, Object?> _prop(
  String id,
  String name,
  String description,
  String subcategory,
  List<String> assetRoles, {
  List<String> legalTerrain = const [],
}) => {
  'id': id,
  'name': name,
  'description': description,
  'kind': 'decoration',
  'assetRoles': assetRoles,
  'subcategory': subcategory,
  'footprint': {'columns': 1, 'rows': 1},
  'costCoins': 0,
  'population': 0,
  'enabled': true,
  if (legalTerrain.isNotEmpty) 'legalTerrain': legalTerrain,
};

final _catalogue = <Map<String, Object?>>[
  _building(
    'small-home',
    'Small House',
    'A welcoming home beside a connected road.',
    'houses',
    [
      'home-small-yellow',
      'home-small-blue',
      'home-small-red',
      'home-small-brickbrown',
      'home-small-brickred',
      'home-small-purple',
    ],
    columns: 1,
    rows: 1,
    population: 3,
    taxCoins: 500,
    upkeepCoins: 100,
    constructionStages: 2,
  ),
  _building(
    'cafe',
    'Café',
    'A neighborhood stop along the road.',
    'commerce',
    ['cafe'],
    columns: 2,
    rows: 1,
    jobs: 8,
    taxCoins: 2000,
    upkeepCoins: 450,
    constructionStages: 2,
  ),
  _prop(
    'flower-garden',
    'Flowers',
    'A small patch of color for an open corner.',
    'flowers',
    ['flowers-yellow', 'flowers-pink', 'flowers-red'],
    legalTerrain: ['land'],
  ),
  _prop(
    'pine-tree',
    'Pine Tree',
    'A quiet evergreen on vacant land.',
    'trees',
    ['pine-medium', 'pine-small', 'pine-tall'],
    legalTerrain: ['land'],
  ),
  _prop(
    'common-tree',
    'Leafy Tree',
    'A round-canopy tree for shade and colour.',
    'trees',
    ['tree-common-large', 'tree-common-medium'],
    legalTerrain: ['land'],
  ),
  _prop(
    'wild-grass',
    'Wild Grass',
    'Let a corner grow a little wild.',
    'flowers',
    ['weed-large-a', 'weed-large-b', 'weed-medium', 'weed-small'],
    legalTerrain: ['land'],
  ),
  _prop(
    'street-lamp',
    'Street Lamp',
    'A lamp to light the pavement come evening.',
    'streetside',
    ['lightpole-a', 'lightpole-b'],
  ),
  _prop(
    'rocks',
    'Rocks',
    'A scattering of stones for rugged corners.',
    'rocks',
    [
      'rocks-brown-a',
      'rocks-brown-b',
      'rocks-brown-c',
      'rocks-gray-a',
      'rocks-gray-b',
      'rocks-gray-c',
    ],
    legalTerrain: ['land'],
  ),
  _building(
    'medium-home',
    'Medium House',
    'A larger home unlocked by a growing settlement.',
    'houses',
    [
      'home-medium-blue',
      'home-medium-brickwhite',
      'home-medium-brown',
      'home-medium-green',
      'home-medium-white',
    ],
    columns: 2,
    rows: 1,
    population: 4,
    taxCoins: 700,
    upkeepCoins: 120,
    constructionStages: 3,
  ),
  _building(
    'fruit-market',
    'Fruit Market',
    'A colorful market for a connected neighborhood.',
    'commerce',
    ['fruit-market'],
    columns: 1,
    rows: 1,
    jobs: 6,
    taxCoins: 1500,
    upkeepCoins: 350,
    constructionStages: 2,
  ),
  _building(
    'community-clinic',
    'Community Clinic',
    'A civic building unlocked as the settlement grows.',
    'civic',
    ['clinic'],
    columns: 2,
    rows: 1,
    jobs: 15,
    upkeepCoins: 1500,
    constructionStages: 3,
    serviceCategory: 'health',
    serviceCapacity: 400,
  ),
  _building(
    'large-home',
    'Large House',
    'A tall family home with room to spare.',
    'houses',
    [
      'home-large-blue',
      'home-large-brickbrown',
      'home-large-brickwhite',
      'home-large-brown',
      'home-large-green',
      'home-large-purple',
    ],
    columns: 2,
    rows: 1,
    population: 5,
    taxCoins: 850,
    upkeepCoins: 140,
    constructionStages: 3,
  ),
  _building(
    'apartments',
    'Brick Apartment Building',
    'A denser home for a larger city center.',
    'apartments',
    ['apartments-brick-brown', 'apartments-brick-white'],
    columns: 2,
    rows: 2,
    population: 40,
    taxCoins: 6800,
    upkeepCoins: 1000,
    constructionStages: 4,
  ),
  _building(
    'fire-station',
    'Fire Station',
    'Ready for any emergency.',
    'civic',
    ['fire-station'],
    columns: 2,
    rows: 2,
    jobs: 20,
    upkeepCoins: 3000,
    constructionStages: 3,
    serviceCategory: 'fire',
    serviceCapacity: 1200,
  ),
  _building(
    'police-station',
    'Police Station',
    'Keeps the streets safe.',
    'civic',
    ['police-station'],
    columns: 2,
    rows: 2,
    jobs: 25,
    upkeepCoins: 2500,
    constructionStages: 3,
    serviceCategory: 'police',
    serviceCapacity: 1000,
  ),
  _building(
    'tall-office',
    'Tall Office',
    'A landmark tower of brick and glass.',
    'offices',
    ['office-tall-blue', 'office-tall-brown', 'office-tall-yellow'],
    columns: 2,
    rows: 2,
    jobs: 300,
    taxCoins: 75000,
    upkeepCoins: 15000,
    constructionStages: 4,
  ),
];

// ---------------------------------------------------------------------------
// Sprites
// ---------------------------------------------------------------------------

/// A single-facing sprite entry. renderScale (0.5) and sways (false)
/// match the shipped defaults.
Map<String, Object?> _sprite(
  String path, {
  required String category,
  required String subcategory,
  bool codeReferenced = false,
  List<double> groundAnchor = const [0.5, 1],
}) => {
  'path': path,
  'category': category,
  'subcategory': subcategory,
  'codeReferenced': codeReferenced,
  'groundAnchor': groundAnchor,
};

/// A left/right door-facing building sprite.
Map<String, Object?> _facingSprite(
  String left,
  String right, {
  required String subcategory,
}) => {
  'facings': {'left': left, 'right': right},
  'category': 'buildings',
  'subcategory': subcategory,
  'groundAnchor': [0.5, 1],
};

final _sprites = <String, Object?>{
  // Houses.
  'home-small-yellow': _facingSprite(
    'sprites/buildings/houses/bld_house_small_yellow_a.png',
    'sprites/buildings/houses/bld_house_small_yellow_b.png',
    subcategory: 'houses',
  ),
  'home-small-blue': _facingSprite(
    'sprites/buildings/houses/bld_house_small_blue_a.png',
    'sprites/buildings/houses/bld_house_small_blue_b.png',
    subcategory: 'houses',
  ),
  'home-small-red': _facingSprite(
    'sprites/buildings/houses/bld_house_small_red_a.png',
    'sprites/buildings/houses/bld_house_small_red_b.png',
    subcategory: 'houses',
  ),
  'home-small-brickbrown': _facingSprite(
    'sprites/buildings/houses/bld_house_small_brickbrown_a.png',
    'sprites/buildings/houses/bld_house_small_brickbrown_b.png',
    subcategory: 'houses',
  ),
  'home-small-brickred': _facingSprite(
    'sprites/buildings/houses/bld_house_small_brickred_a.png',
    'sprites/buildings/houses/bld_house_small_brickred_b.png',
    subcategory: 'houses',
  ),
  'home-small-purple': _facingSprite(
    'sprites/buildings/houses/bld_house_small_purple_a.png',
    'sprites/buildings/houses/bld_house_small_purple_b.png',
    subcategory: 'houses',
  ),
  'home-medium-blue': _facingSprite(
    'sprites/buildings/houses/bld_house_medium_blue_a.png',
    'sprites/buildings/houses/bld_house_medium_blue_b.png',
    subcategory: 'houses',
  ),
  'home-medium-brickwhite': _facingSprite(
    'sprites/buildings/houses/bld_house_medium_brickwhite_a.png',
    'sprites/buildings/houses/bld_house_medium_brickwhite_b.png',
    subcategory: 'houses',
  ),
  'home-medium-brown': _facingSprite(
    'sprites/buildings/houses/bld_house_medium_brown_a.png',
    'sprites/buildings/houses/bld_house_medium_brown_b.png',
    subcategory: 'houses',
  ),
  'home-medium-green': _facingSprite(
    'sprites/buildings/houses/bld_house_medium_green_a.png',
    'sprites/buildings/houses/bld_house_medium_green_b.png',
    subcategory: 'houses',
  ),
  'home-medium-white': _facingSprite(
    'sprites/buildings/houses/bld_house_medium_white_a.png',
    'sprites/buildings/houses/bld_house_medium_white_b.png',
    subcategory: 'houses',
  ),
  'home-large-blue': _facingSprite(
    'sprites/buildings/houses/bld_house_tall_blue_a.png',
    'sprites/buildings/houses/bld_house_tall_blue_b.png',
    subcategory: 'houses',
  ),
  'home-large-brickbrown': _facingSprite(
    'sprites/buildings/houses/bld_house_tall_brickbrown_a.png',
    'sprites/buildings/houses/bld_house_tall_brickbrown_b.png',
    subcategory: 'houses',
  ),
  'home-large-brickwhite': _facingSprite(
    'sprites/buildings/houses/bld_house_tall_brickwhite_a.png',
    'sprites/buildings/houses/bld_house_tall_brickwhite_b.png',
    subcategory: 'houses',
  ),
  'home-large-brown': _facingSprite(
    'sprites/buildings/houses/bld_house_tall_brown_a.png',
    'sprites/buildings/houses/bld_house_tall_brown_b.png',
    subcategory: 'houses',
  ),
  'home-large-green': _facingSprite(
    'sprites/buildings/houses/bld_house_tall_green_a.png',
    'sprites/buildings/houses/bld_house_tall_green_b.png',
    subcategory: 'houses',
  ),
  'home-large-purple': _facingSprite(
    'sprites/buildings/houses/bld_house_tall_purple_a.png',
    'sprites/buildings/houses/bld_house_tall_purple_b.png',
    subcategory: 'houses',
  ),

  // Commerce, civic, offices, apartments.
  'cafe': _facingSprite(
    'sprites/buildings/commerce/bld_cafe_a.png',
    'sprites/buildings/commerce/bld_cafe_b.png',
    subcategory: 'commerce',
  ),
  'fruit-market': _facingSprite(
    'sprites/buildings/commerce/bld_fruitstand_a.png',
    'sprites/buildings/commerce/bld_fruitstand_b.png',
    subcategory: 'commerce',
  ),
  'clinic': _facingSprite(
    'sprites/buildings/civic/bld_clinic_a.png',
    'sprites/buildings/civic/bld_clinic_b.png',
    subcategory: 'civic',
  ),
  'fire-station': _facingSprite(
    'sprites/buildings/civic/bld_firestation_a.png',
    'sprites/buildings/civic/bld_firestation_b.png',
    subcategory: 'civic',
  ),
  'police-station': _facingSprite(
    'sprites/buildings/civic/bld_policestation_a.png',
    'sprites/buildings/civic/bld_policestation_b.png',
    subcategory: 'civic',
  ),
  'office-tall-blue': _facingSprite(
    'sprites/buildings/offices/bld_office_tall_blue_a.png',
    'sprites/buildings/offices/bld_office_tall_blue_b.png',
    subcategory: 'offices',
  ),
  'office-tall-brown': _facingSprite(
    'sprites/buildings/offices/bld_office_tall_brown_a.png',
    'sprites/buildings/offices/bld_office_tall_brown_b.png',
    subcategory: 'offices',
  ),
  'office-tall-yellow': _facingSprite(
    'sprites/buildings/offices/bld_office_tall_yellow_a.png',
    'sprites/buildings/offices/bld_office_tall_yellow_b.png',
    subcategory: 'offices',
  ),
  'apartments-brick-brown': {
    'facings': {
      'left': 'sprites/buildings/apartments/bld_apartments_brickbrown_a.png',
      'right': 'sprites/buildings/apartments/bld_apartments_brickbrown_b.png',
    },
    'category': 'buildings',
    'subcategory': 'apartments',
    'groundAnchor': [0.5, 1],
    // The one shipped building with per-door-side placement shifts.
    'sideShifts': {
      'east': [0.04, -0.02],
      'north': [-0.015, -0.09],
      'south': [-0.02, 0.04],
      'west': [-0.08, -0.02],
    },
  },
  'apartments-brick-white': _facingSprite(
    'sprites/buildings/apartments/bld_apartments_brickwhite_a.png',
    'sprites/buildings/apartments/bld_apartments_brickwhite_b.png',
    subcategory: 'apartments',
  ),

  // Props.
  'flowers-yellow': {
    'path': 'sprites/props/flowers/prop_flowers_yellow.png',
    'category': 'props',
    'subcategory': 'flowers',
    'groundAnchor': [0.5, 0.95],
  },
  'flowers-pink': _sprite(
    'sprites/props/flowers/prop_flowers_pink.png',
    category: 'props',
    subcategory: 'flowers',
  ),
  'flowers-red': _sprite(
    'sprites/props/flowers/prop_flowers_red.png',
    category: 'props',
    subcategory: 'flowers',
  ),
  'weed-large-a': _sprite(
    'sprites/props/flowers/prop_weed_large_a.png',
    category: 'props',
    subcategory: 'flowers',
  ),
  'weed-large-b': _sprite(
    'sprites/props/flowers/prop_weed_large_b.png',
    category: 'props',
    subcategory: 'flowers',
  ),
  'weed-medium': _sprite(
    'sprites/props/flowers/prop_weed_medium.png',
    category: 'props',
    subcategory: 'flowers',
  ),
  'weed-small': _sprite(
    'sprites/props/flowers/prop_weed_small.png',
    category: 'props',
    subcategory: 'flowers',
  ),
  'pine-medium': _sprite(
    'sprites/props/trees/prop_tree_pine_medium.png',
    category: 'props',
    subcategory: 'trees',
  ),
  'pine-small': _sprite(
    'sprites/props/trees/prop_tree_pine_small.png',
    category: 'props',
    subcategory: 'trees',
  ),
  'pine-tall': _sprite(
    'sprites/props/trees/prop_tree_pine_tall.png',
    category: 'props',
    subcategory: 'trees',
  ),
  'tree-common-large': _sprite(
    'sprites/props/trees/prop_tree_common_large.png',
    category: 'props',
    subcategory: 'trees',
  ),
  'tree-common-medium': _sprite(
    'sprites/props/trees/prop_tree_common_medium.png',
    category: 'props',
    subcategory: 'trees',
  ),
  'lightpole-a': _sprite(
    'sprites/props/streetside/prop_lightpole_a.png',
    category: 'props',
    subcategory: 'streetside',
  ),
  'lightpole-b': _sprite(
    'sprites/props/streetside/prop_lightpole_b.png',
    category: 'props',
    subcategory: 'streetside',
  ),
  'rocks-brown-a': _sprite(
    'sprites/props/rocks/prop_rocks_brown_a.png',
    category: 'props',
    subcategory: 'rocks',
  ),
  'rocks-brown-b': _sprite(
    'sprites/props/rocks/prop_rocks_brown_b.png',
    category: 'props',
    subcategory: 'rocks',
  ),
  'rocks-brown-c': _sprite(
    'sprites/props/rocks/prop_rocks_brown_c.png',
    category: 'props',
    subcategory: 'rocks',
  ),
  'rocks-gray-a': _sprite(
    'sprites/props/rocks/prop_rocks_gray_a.png',
    category: 'props',
    subcategory: 'rocks',
  ),
  'rocks-gray-b': _sprite(
    'sprites/props/rocks/prop_rocks_gray_b.png',
    category: 'props',
    subcategory: 'rocks',
  ),
  'rocks-gray-c': _sprite(
    'sprites/props/rocks/prop_rocks_gray_c.png',
    category: 'props',
    subcategory: 'rocks',
  ),

  // Code-referenced ground, fog, and wisps.
  'terrain.grass': _sprite(
    'sprites/ground/grass/tile_ground_grass.png',
    category: 'ground',
    subcategory: 'grass',
    codeReferenced: true,
  ),
  'terrain.grass.puddle': _sprite(
    'sprites/ground/grass/tile_ground_grass_puddle_clean.png',
    category: 'ground',
    subcategory: 'grass',
    codeReferenced: true,
  ),
  'terrain.dirt': _sprite(
    'sprites/ground/dirt/tile_ground_dirt.png',
    category: 'ground',
    subcategory: 'dirt',
    codeReferenced: true,
  ),
  'terrain.asphalt': _sprite(
    'sprites/ground/asphalt/tile_ground_asphalt.png',
    category: 'ground',
    subcategory: 'asphalt',
    codeReferenced: true,
  ),
  'terrain.concrete': _sprite(
    'sprites/ground/concrete/tile_ground_concrete.png',
    category: 'ground',
    subcategory: 'concrete',
    codeReferenced: true,
  ),
  'terrain.water': _sprite(
    'sprites/ground/water/tile_ground_water.png',
    category: 'ground',
    subcategory: 'water',
    codeReferenced: true,
  ),
  'terrain.fog': _sprite(
    'sprites/ground/fog/tile_ground_fog.png',
    category: 'ground',
    subcategory: 'fog',
    codeReferenced: true,
  ),
  'fog.wisp.a': _sprite(
    'sprites/fog/wisp_fog_a.png',
    category: 'fog',
    subcategory: 'wisp',
    codeReferenced: true,
  ),
  'fog.wisp.b': _sprite(
    'sprites/fog/wisp_fog_b.png',
    category: 'fog',
    subcategory: 'wisp',
    codeReferenced: true,
  ),
  'fog.wisp.c': _sprite(
    'sprites/fog/wisp_fog_c.png',
    category: 'fog',
    subcategory: 'wisp',
    codeReferenced: true,
  ),

  // Code-referenced roads, with the painted walkable and lane masks
  // the pedestrian and vehicle lattices read.
  'road.straight.se': {
    'path': 'sprites/roads/straight/tile_road_straight_SE_normal.png',
    'category': 'roads',
    'subcategory': 'straight',
    'codeReferenced': true,
    'groundAnchor': [0.5, 1],
    'walkable': [255, 0, 0, 0, 0, 0, 0, 255],
    'lanes': {
      'east-1': [0, 0, 0, 0, 255, 255, 0, 0],
      'west-1': [0, 0, 255, 255, 0, 0, 0, 0],
    },
  },
  'road.straight.sw': {
    'path': 'sprites/roads/straight/tile_road_straight_SW_normal.png',
    'category': 'roads',
    'subcategory': 'straight',
    'codeReferenced': true,
    'groundAnchor': [0.5, 1],
    'walkable': [129, 129, 129, 129, 129, 129, 129, 129],
    'lanes': {
      'north-1': [48, 48, 48, 48, 48, 48, 48, 48],
      'south-1': [12, 12, 12, 12, 12, 12, 12, 12],
    },
  },
  'road.corner.n': {
    'path': 'sprites/roads/corner/tile_road_corner_N_normal.png',
    'category': 'roads',
    'subcategory': 'corner',
    'codeReferenced': true,
    'groundAnchor': [0.5, 1],
    'walkable': [255, 1, 1, 1, 1, 1, 1, 129],
    'lanes': {
      'east-1': [0, 0, 0, 0, 240, 240, 0, 0],
      'north-1': [0, 0, 0, 0, 48, 48, 48, 48],
      'south-1': [0, 0, 12, 12, 12, 12, 12, 12],
      'west-1': [0, 0, 252, 252, 0, 0, 0, 0],
    },
  },
  'road.corner.e': {
    'path': 'sprites/roads/corner/tile_road_corner_E_normal.png',
    'category': 'roads',
    'subcategory': 'corner',
    'codeReferenced': true,
    'groundAnchor': [0.5, 1],
    'walkable': [255, 128, 128, 128, 128, 128, 128, 129],
    'lanes': {
      'east-1': [0, 0, 0, 0, 15, 15, 0, 0],
      'north-1': [0, 0, 48, 48, 48, 48, 48, 48],
      'south-1': [0, 0, 0, 0, 12, 12, 12, 12],
      'west-1': [0, 0, 63, 63, 0, 0, 0, 0],
    },
  },
  'road.corner.s': {
    'path': 'sprites/roads/corner/tile_road_corner_S_normal.png',
    'category': 'roads',
    'subcategory': 'corner',
    'codeReferenced': true,
    'groundAnchor': [0.5, 1],
    'walkable': [129, 128, 128, 128, 128, 128, 128, 255],
    'lanes': {
      'east-1': [0, 0, 0, 0, 63, 63, 0, 0],
      'north-1': [48, 48, 48, 48, 48, 48, 0, 0],
      'south-1': [12, 12, 12, 12, 0, 0, 0, 0],
      'west-1': [0, 0, 15, 15, 0, 0, 0, 0],
    },
  },
  'road.corner.w': {
    'path': 'sprites/roads/corner/tile_road_corner_W_normal.png',
    'category': 'roads',
    'subcategory': 'corner',
    'codeReferenced': true,
    'groundAnchor': [0.5, 1],
    'walkable': [129, 1, 1, 1, 1, 1, 1, 255],
    'lanes': {
      'east-1': [0, 0, 0, 0, 252, 252, 0, 0],
      'north-1': [48, 48, 48, 48, 0, 0, 0, 0],
      'south-1': [12, 12, 12, 12, 12, 12, 0, 0],
      'west-1': [0, 0, 240, 240, 0, 0, 0, 0],
    },
  },
  'road.t.ne': {
    'path': 'sprites/roads/t/tile_road_intersection_NE_normal.png',
    'category': 'roads',
    'subcategory': 't',
    'codeReferenced': true,
    'groundAnchor': [0.5, 1],
    'walkable': [129, 0, 0, 0, 0, 0, 0, 255],
    'lanes': {
      'east-1': [0, 0, 0, 0, 255, 255, 0, 0],
      'north-1': [48, 48, 48, 48, 48, 48, 0, 0],
      'south-1': [12, 12, 12, 12, 12, 12, 0, 0],
      'west-1': [0, 0, 255, 255, 0, 0, 0, 0],
    },
  },
  'road.t.nw': {
    'path': 'sprites/roads/t/tile_road_intersection_NW_normal.png',
    'category': 'roads',
    'subcategory': 't',
    'codeReferenced': true,
    'groundAnchor': [0.5, 1],
    'walkable': [129, 128, 128, 128, 128, 128, 128, 129],
    'lanes': {
      'east-1': [0, 0, 0, 0, 63, 63, 0, 0],
      'north-1': [48, 48, 48, 48, 48, 48, 48, 48],
      'south-1': [12, 12, 12, 12, 12, 12, 12, 12],
      'west-1': [0, 0, 63, 63, 0, 0, 0, 0],
    },
  },
  'road.t.se': {
    'path': 'sprites/roads/t/tile_road_intersection_SE_normal.png',
    'category': 'roads',
    'subcategory': 't',
    'codeReferenced': true,
    'groundAnchor': [0.5, 1],
    'walkable': [129, 1, 1, 1, 1, 1, 1, 129],
    'lanes': {
      'east-1': [0, 0, 0, 0, 252, 252, 0, 0],
      'north-1': [48, 48, 48, 48, 48, 48, 48, 48],
      'south-1': [12, 12, 12, 12, 12, 12, 12, 12],
      'west-1': [0, 0, 252, 252, 0, 0, 0, 0],
    },
  },
  'road.t.sw': {
    'path': 'sprites/roads/t/tile_road_intersection_SW_normal.png',
    'category': 'roads',
    'subcategory': 't',
    'codeReferenced': true,
    'groundAnchor': [0.5, 1],
    'walkable': [255, 0, 0, 0, 0, 0, 0, 129],
    'lanes': {
      'east-1': [0, 0, 0, 0, 255, 255, 0, 0],
      'north-1': [0, 0, 48, 48, 48, 48, 48, 48],
      'south-1': [0, 0, 12, 12, 12, 12, 12, 12],
      'west-1': [0, 0, 255, 255, 0, 0, 0, 0],
    },
  },
  'road.cross': {
    'path': 'sprites/roads/cross/tile_road_xsing_normal.png',
    'category': 'roads',
    'subcategory': 'cross',
    'codeReferenced': true,
    'groundAnchor': [0.5, 1],
    'walkable': [129, 0, 0, 0, 0, 0, 0, 129],
    'lanes': {
      'east-1': [0, 0, 0, 0, 255, 255, 0, 0],
      'north-1': [48, 48, 48, 48, 48, 48, 48, 48],
      'south-1': [12, 12, 12, 12, 12, 12, 12, 12],
      'west-1': [0, 0, 255, 255, 0, 0, 0, 0],
    },
  },
  'road.end.ne': {
    'path': 'sprites/roads/end/tile_road_end_NE_normal.png',
    'category': 'roads',
    'subcategory': 'end',
    'codeReferenced': true,
    'groundAnchor': [0.5, 1],
    'walkable': [255, 129, 129, 129, 129, 129, 129, 129],
    'lanes': {
      'north-1': [0, 0, 48, 48, 48, 48, 48, 48],
      'south-1': [0, 0, 12, 12, 12, 12, 12, 12],
    },
  },
  'road.end.nw': {
    'path': 'sprites/roads/end/tile_road_end_NW_normal.png',
    'category': 'roads',
    'subcategory': 'end',
    'codeReferenced': true,
    'groundAnchor': [0.5, 1],
    'walkable': [255, 1, 1, 1, 1, 1, 1, 255],
    'lanes': {
      'east-1': [0, 0, 0, 0, 252, 252, 0, 0],
      'west-1': [0, 0, 252, 252, 0, 0, 0, 0],
    },
  },
  'road.end.se': {
    'path': 'sprites/roads/end/tile_road_end_SE_normal.png',
    'category': 'roads',
    'subcategory': 'end',
    'codeReferenced': true,
    'groundAnchor': [0.5, 1],
    'walkable': [255, 128, 128, 128, 128, 128, 128, 255],
    'lanes': {
      'east-1': [0, 0, 0, 0, 63, 63, 0, 0],
      'west-1': [0, 0, 63, 63, 0, 0, 0, 0],
    },
  },
  'road.end.sw': {
    'path': 'sprites/roads/end/tile_road_end_SW_normal.png',
    'category': 'roads',
    'subcategory': 'end',
    'codeReferenced': true,
    'groundAnchor': [0.5, 1],
    'walkable': [129, 129, 129, 129, 129, 129, 129, 255],
    'lanes': {
      'north-1': [48, 48, 48, 48, 48, 48, 0, 0],
      'south-1': [12, 12, 12, 12, 12, 12, 0, 0],
    },
  },
  'road.pelican.ne': {
    'path': 'sprites/roads/pelican/tile_road_pelican_NE_normal.png',
    'category': 'roads',
    'subcategory': 'pelican',
    'codeReferenced': true,
    'groundAnchor': [0.5, 1],
    'walkable': [129, 255, 129, 129, 129, 129, 129, 129],
    'lanes': {
      'north-1': [48, 48, 48, 48, 48, 48, 48, 48],
      'south-1': [12, 12, 12, 12, 12, 12, 12, 12],
    },
  },
  'road.pelican.nw': {
    'path': 'sprites/roads/pelican/tile_road_pelican_NW_normal.png',
    'category': 'roads',
    'subcategory': 'pelican',
    'codeReferenced': true,
    'groundAnchor': [0.5, 1],
    'walkable': [255, 2, 2, 2, 2, 2, 2, 255],
    'lanes': {
      'east-1': [0, 0, 0, 0, 255, 255, 0, 0],
      'west-1': [0, 0, 255, 255, 0, 0, 0, 0],
    },
  },
  'road.pelican.se': {
    'path': 'sprites/roads/pelican/tile_road_pelican_SE_normal.png',
    'category': 'roads',
    'subcategory': 'pelican',
    'codeReferenced': true,
    'groundAnchor': [0.5, 1],
    'walkable': [255, 64, 64, 64, 64, 64, 64, 255],
    'lanes': {
      'east-1': [0, 0, 0, 0, 255, 255, 0, 0],
      'west-1': [0, 0, 255, 255, 0, 0, 0, 0],
    },
  },
  'road.pelican.sw': {
    'path': 'sprites/roads/pelican/tile_road_pelican_SW_normal.png',
    'category': 'roads',
    'subcategory': 'pelican',
    'codeReferenced': true,
    'groundAnchor': [0.5, 1],
    'walkable': [129, 129, 129, 129, 129, 129, 255, 129],
    'lanes': {
      'north-1': [48, 48, 48, 48, 48, 48, 48, 48],
      'south-1': [12, 12, 12, 12, 12, 12, 12, 12],
    },
  },

  // Code-referenced bridges — decks lift their surface by 12 world px.
  'bridge.body.se': {
    'path': 'sprites/bridges/body/tile_road_bridge_body_SE_normal.png',
    'category': 'bridges',
    'subcategory': 'body',
    'codeReferenced': true,
    'groundAnchor': [0.5, 1],
    'baseOffsetY': -12,
    'surfaceLift': 12,
    'walkable': [255, 0, 0, 0, 0, 0, 0, 255],
    'lanes': {
      'east-1': [0, 0, 0, 0, 255, 255, 0, 0],
      'west-1': [0, 0, 255, 255, 0, 0, 0, 0],
    },
  },
  'bridge.body.sw': {
    'path': 'sprites/bridges/body/tile_road_bridge_body_SW_normal.png',
    'category': 'bridges',
    'subcategory': 'body',
    'codeReferenced': true,
    'groundAnchor': [0.5, 1],
    'baseOffsetY': -12,
    'surfaceLift': 12,
    'walkable': [129, 129, 129, 129, 129, 129, 129, 129],
    'lanes': {
      'north-1': [48, 48, 48, 48, 48, 48, 48, 48],
      'south-1': [12, 12, 12, 12, 12, 12, 12, 12],
    },
  },
  'bridge.ramp.ne': {
    'path': 'sprites/bridges/ramp/tile_road_bridge_ramp_NE_normal.png',
    'category': 'bridges',
    'subcategory': 'ramp',
    'codeReferenced': true,
    'groundAnchor': [0.5, 1],
    'walkable': [129, 129, 129, 129, 129, 129, 129, 129],
    'lanes': {
      'north-1': [48, 48, 48, 48, 48, 48, 48, 48],
      'south-1': [12, 12, 12, 12, 12, 12, 12, 12],
    },
  },
  'bridge.ramp.nw': {
    'path': 'sprites/bridges/ramp/tile_road_bridge_ramp_NW_normal.png',
    'category': 'bridges',
    'subcategory': 'ramp',
    'codeReferenced': true,
    'groundAnchor': [0.5, 1],
    'walkable': [255, 0, 0, 0, 0, 0, 0, 255],
    'lanes': {
      'east-1': [0, 0, 0, 0, 255, 255, 0, 0],
      'west-1': [0, 0, 255, 255, 0, 0, 0, 0],
    },
  },
  'bridge.ramp.se': {
    'path': 'sprites/bridges/ramp/tile_road_bridge_ramp_SE_normal.png',
    'category': 'bridges',
    'subcategory': 'ramp',
    'codeReferenced': true,
    'groundAnchor': [0.5, 1],
    'walkable': [255, 0, 0, 0, 0, 0, 0, 255],
    'lanes': {
      'east-1': [0, 0, 0, 0, 255, 255, 0, 0],
      'west-1': [0, 0, 255, 255, 0, 0, 0, 0],
    },
  },
  'bridge.ramp.sw': {
    'path': 'sprites/bridges/ramp/tile_road_bridge_ramp_SW_normal.png',
    'category': 'bridges',
    'subcategory': 'ramp',
    'codeReferenced': true,
    'groundAnchor': [0.5, 1],
    'walkable': [129, 129, 129, 129, 129, 129, 129, 129],
    'lanes': {
      'north-1': [48, 48, 48, 48, 48, 48, 48, 48],
      'south-1': [12, 12, 12, 12, 12, 12, 12, 12],
    },
  },
};

// ---------------------------------------------------------------------------
// Economy — the shipped dials, frozen.
// ---------------------------------------------------------------------------

const _economy = <String, Object?>{
  'startingTreasuryCoins': 20000,
  'roadTileCostCoins': 2500,
  'bridgeCost': {'bridgeTileCostCoins': 50000},
  'roadTaxCoinsPerTile': 0,
  'roadUpkeepCoinsPerTile': 10,
  'bridgeTaxCoinsPerTile': 0,
  'bridgeUpkeepCoinsPerTile': 300,
  'parcelBaseCoins': 15000,
  'parcelPerPopulationCoins': 150,
  'migrationPercentPerCheckIn': 2,
  'employmentPercentPerCheckIn': 5,
  'waitingPopulationCapPercent': 10,
  'unemploymentTolerancePercent': 10,
  'jobPullPercentPerCheckIn': 10,
  'contentmentFloorPercent': 30,
  'homeTaxUnemploymentFloorPercent': 30,
  'serviceRequirementPopulation': 300,
  'requiredServiceCategories': ['fire', 'police', 'health'],
};

// ---------------------------------------------------------------------------
// Ambience — the shipped tuning, frozen. Car render anchors are kept
// for the sedan only (the dominant type); the other types fall back
// to computed default anchors, which no test reads.
// ---------------------------------------------------------------------------

const _ambience = <String, Object?>{
  'ambientTimeScale': 1,
  'vegetationSway': {
    'maxAngleRadians': 0.045,
    'baseFrequency': 1.1,
    'frequencySteps': 7,
    'frequencyStep': 0.13,
    'minScale': 0.75,
  },
  'pedestrians': {
    'spriteScale': 0.6,
    'walkFrameRate': 7,
    'speedMin': 0.2,
    'speedRange': 0.1,
    'populationPercent': 20,
    'lateralWanderX': 3,
    'lateralWanderY': 2,
  },
  'cars': {
    'populationPercent': 2,
    'speedMin': 0.9,
    'speedRange': 0.3,
    'spriteScale': 0.9,
    'dwellSeconds': 2.5,
    'respawnDelaySeconds': 4,
    'minTripCells': 10,
    'types': {
      'bus_school': {'percent': 7},
      'firetruck': {'percent': 7},
      'garbage': {'percent': 6},
      'pickup': {
        'percent': 20,
        'variants': ['orange', 'black', 'red'],
      },
      'police': {'percent': 5},
      'sedan': {
        'percent': 24,
        'variants': ['blue', 'white', 'red'],
      },
      'swat': {'percent': 2},
      'truck': {
        'percent': 12,
        'variants': ['red', 'green', 'yellow'],
      },
      'van': {
        'percent': 17,
        'variants': ['white', 'black', 'purple'],
      },
    },
    'render': {
      'sedan': {
        'anchor': {
          'NE': [0.5, 0.7452380952380953],
          'NW': [0.297270955165692, 0.7769607843137256],
          'SE': [0.37524366471734893, 0.6944444444444444],
          'SW': [0.5155945419103314, 0.8087301587301587],
        },
      },
    },
  },
  'unownedLandWash': {
    'alpha': 79,
    'colorRgb': [181, 220, 207],
  },
  'claimedLandWash': {
    'alpha': 64,
    'colorRgb': [130, 130, 145],
  },
  'tileGrid': {
    'enabled': false,
    'alpha': 55,
    'colorRgb': [30, 101, 82],
  },
};

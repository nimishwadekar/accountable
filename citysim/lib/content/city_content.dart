import '../domain/city_state.dart';

const cityAssetRoot = 'assets/buggy_studio';

enum CityItemKind { decoration, building }

class CityCatalogueItem {
  const CityCatalogueItem({
    required this.id,
    required this.name,
    required this.description,
    required this.kind,
    required this.costCoins,
    required this.durationSeconds,
    required this.minimumDistrictRank,
  });

  final String id;
  final String name;
  final String description;
  final CityItemKind kind;
  final int costCoins;
  final int durationSeconds;
  final int minimumDistrictRank;

  String get costLabel => '$costCoins ${costCoins == 1 ? 'coin' : 'coins'}';
}

/// Maps stable catalogue roles to replaceable sprite files and logical layout.
class CitySpriteDefinition {
  const CitySpriteDefinition({
    required this.assetPath,
    this.footprintColumns = 1,
    this.footprintRows = 1,
    this.renderScale = 0.5,
    this.groundAnchorX = 0.5,
    this.groundAnchorY = 1,
  });

  final String assetPath;
  final int footprintColumns;
  final int footprintRows;
  final double renderScale;
  final double groundAnchorX;
  final double groundAnchorY;
}

class CityDistrict {
  const CityDistrict({
    required this.id,
    required this.name,
    required this.unlockCost,
    required this.unlockDurationSeconds,
  });

  final String id;
  final String name;
  final int unlockCost;
  final int unlockDurationSeconds;
}

class CityLot {
  const CityLot({
    required this.id,
    required this.districtId,
    required this.cell,
    this.footprintColumns = 1,
    this.footprintRows = 1,
  });

  final String id;
  final String districtId;
  final CityCell cell;
  final int footprintColumns;
  final int footprintRows;
}

class CityRoad {
  const CityRoad({required this.cell, required this.assetName});

  final CityCell cell;
  final String assetName;
}

class CityScenery {
  const CityScenery({required this.cell, required this.assetName});

  final CityCell cell;
  final String assetName;
}

const cityMapColumns = 20;
const cityMapRows = 16;

const cityDistricts = <CityDistrict>[
  CityDistrict(
    id: 'village',
    name: 'Willow Village',
    unlockCost: 0,
    unlockDurationSeconds: 0,
  ),
  CityDistrict(
    id: 'town',
    name: 'Market Town',
    unlockCost: 8,
    unlockDurationSeconds: 300,
  ),
  CityDistrict(
    id: 'city',
    name: 'Cedar Heights',
    unlockCost: 8,
    unlockDurationSeconds: 300,
  ),
];

const cityCatalogue = <CityCatalogueItem>[
  CityCatalogueItem(
    id: 'flower-garden',
    name: 'Flower garden',
    description: 'A bright little patch for a quiet corner.',
    kind: CityItemKind.decoration,
    costCoins: 1,
    durationSeconds: 30,
    minimumDistrictRank: 1,
  ),
  CityCatalogueItem(
    id: 'pine-tree',
    name: 'Pine tree',
    description: 'A small evergreen for the village green.',
    kind: CityItemKind.decoration,
    costCoins: 1,
    durationSeconds: 30,
    minimumDistrictRank: 1,
  ),
  CityCatalogueItem(
    id: 'small-home',
    name: 'Sunny cottage',
    description: 'A welcoming home on a new village lane.',
    kind: CityItemKind.building,
    costCoins: 3,
    durationSeconds: 120,
    minimumDistrictRank: 1,
  ),
  CityCatalogueItem(
    id: 'brick-cottage',
    name: 'Brick cottage',
    description: 'A sturdy little home in a warm brick finish.',
    kind: CityItemKind.building,
    costCoins: 3,
    durationSeconds: 120,
    minimumDistrictRank: 1,
  ),
  CityCatalogueItem(
    id: 'cafe',
    name: 'Corner cafe',
    description: 'A neighbourhood stop beside the main road.',
    kind: CityItemKind.building,
    costCoins: 3,
    durationSeconds: 120,
    minimumDistrictRank: 1,
  ),
  CityCatalogueItem(
    id: 'fruit-market',
    name: 'Fruit market',
    description: 'A colourful market stall for the town centre.',
    kind: CityItemKind.building,
    costCoins: 3,
    durationSeconds: 120,
    minimumDistrictRank: 2,
  ),
  CityCatalogueItem(
    id: 'community-clinic',
    name: 'Community clinic',
    description: 'A small civic landmark for a growing town.',
    kind: CityItemKind.building,
    costCoins: 5,
    durationSeconds: 180,
    minimumDistrictRank: 2,
  ),
  CityCatalogueItem(
    id: 'apartments',
    name: 'Brick apartments',
    description: 'A taller home for the city district.',
    kind: CityItemKind.building,
    costCoins: 5,
    durationSeconds: 180,
    minimumDistrictRank: 3,
  ),
  CityCatalogueItem(
    id: 'city-office',
    name: 'Cedar office',
    description: 'A compact city workplace in warm brick.',
    kind: CityItemKind.building,
    costCoins: 5,
    durationSeconds: 180,
    minimumDistrictRank: 3,
  ),
];

final cityCatalogueById = {for (final item in cityCatalogue) item.id: item};

const citySpriteManifest = <String, CitySpriteDefinition>{
  'flower-garden': CitySpriteDefinition(
    assetPath: 'Props/prop_flowers_yellow.png',
    groundAnchorY: 0.95,
  ),
  'pine-tree': CitySpriteDefinition(
    assetPath: 'Props/prop_tree_pine_medium.png',
  ),
  'small-home': CitySpriteDefinition(
    assetPath: 'Buildings/bld_house_small_yellow_a.png',
  ),
  'brick-cottage': CitySpriteDefinition(
    assetPath: 'Buildings/bld_house_small_brickred_a.png',
  ),
  'cafe': CitySpriteDefinition(assetPath: 'Buildings/bld_cafe_a.png'),
  'fruit-market': CitySpriteDefinition(
    assetPath: 'Buildings/bld_fruitstand_a.png',
  ),
  'community-clinic': CitySpriteDefinition(
    assetPath: 'Buildings/bld_clinic_a.png',
  ),
  'apartments': CitySpriteDefinition(
    assetPath: 'Buildings/bld_apartments_brickbrown_a.png',
    renderScale: 0.5,
    footprintColumns: 1,
    footprintRows: 1,
    groundAnchorY: 0.98,
  ),
  'city-office': CitySpriteDefinition(
    assetPath: 'Buildings/bld_office_medium_green_a.png',
  ),
};

const cityLots = <CityLot>[
  CityLot(id: 'village-01', districtId: 'village', cell: CityCell(4, 5)),
  CityLot(id: 'village-02', districtId: 'village', cell: CityCell(6, 4)),
  CityLot(id: 'village-03', districtId: 'village', cell: CityCell(7, 6)),
  CityLot(id: 'village-04', districtId: 'village', cell: CityCell(4, 10)),
  CityLot(id: 'village-05', districtId: 'village', cell: CityCell(6, 11)),
  CityLot(id: 'village-06', districtId: 'village', cell: CityCell(11, 5)),
  CityLot(id: 'village-07', districtId: 'village', cell: CityCell(11, 10)),
  CityLot(id: 'village-08', districtId: 'village', cell: CityCell(7, 9)),
  CityLot(id: 'town-01', districtId: 'town', cell: CityCell(12, 3)),
  CityLot(id: 'town-02', districtId: 'town', cell: CityCell(14, 5)),
  CityLot(id: 'town-03', districtId: 'town', cell: CityCell(16, 5)),
  CityLot(id: 'town-04', districtId: 'town', cell: CityCell(12, 6)),
  CityLot(id: 'town-05', districtId: 'town', cell: CityCell(15, 7)),
  CityLot(id: 'town-06', districtId: 'town', cell: CityCell(17, 9)),
  CityLot(id: 'city-01', districtId: 'city', cell: CityCell(4, 13)),
  CityLot(id: 'city-02', districtId: 'city', cell: CityCell(6, 14)),
  CityLot(id: 'city-03', districtId: 'city', cell: CityCell(11, 13)),
  CityLot(id: 'city-04', districtId: 'city', cell: CityCell(13, 11)),
  CityLot(id: 'city-05', districtId: 'city', cell: CityCell(16, 13)),
  CityLot(id: 'city-06', districtId: 'city', cell: CityCell(14, 14)),
];

final cityLotById = {for (final lot in cityLots) lot.id: lot};

final cityRoads = <CityRoad>[
  for (var column = 2; column <= 17; column++)
    CityRoad(
      cell: CityCell(column, 8),
      assetName: column == 9
          ? 'tile_road_xsing_normal.png'
          : 'tile_road_straight_SE_normal.png',
    ),
  for (var row = 2; row <= 14; row++)
    if (row != 8 && row != 4)
      CityRoad(
        cell: CityCell(9, row),
        assetName: 'tile_road_straight_SW_normal.png',
      ),
  const CityRoad(cell: CityCell(9, 4), assetName: 'tile_road_xsing_normal.png'),
  for (var column = 9; column <= 15; column++)
    if (column != 9)
      CityRoad(
        cell: CityCell(column, 4),
        assetName: 'tile_road_straight_SE_normal.png',
      ),
];

const cityScenery = <CityScenery>[
  CityScenery(cell: CityCell(2, 2), assetName: 'prop_tree_pine_tall.png'),
  CityScenery(cell: CityCell(16, 2), assetName: 'prop_tree_common_large.png'),
  CityScenery(cell: CityCell(2, 13), assetName: 'prop_tree_pine_medium.png'),
  CityScenery(cell: CityCell(18, 12), assetName: 'prop_tree_common_medium.png'),
  CityScenery(cell: CityCell(3, 7), assetName: 'prop_rocks_gray_b.png'),
  CityScenery(cell: CityCell(17, 6), assetName: 'prop_rocks_brown_a.png'),
];

const cityStartingBuildings = <CityBuilding>[
  CityBuilding(
    id: 'starter-home-brickred',
    lotId: 'village-01',
    catalogueId: 'brick-cottage',
    completedAtSeconds: 0,
  ),
  CityBuilding(
    id: 'starter-home-yellow',
    lotId: 'village-02',
    catalogueId: 'small-home',
    completedAtSeconds: 0,
  ),
  CityBuilding(
    id: 'starter-cafe',
    lotId: 'village-03',
    catalogueId: 'cafe',
    completedAtSeconds: 0,
  ),
];

String cityArtPath(String relativePath) => '$cityAssetRoot/$relativePath';

String citySpriteAsset(String spriteId) =>
    cityArtPath(citySpriteManifest[spriteId]!.assetPath);

String cityCatalogueAsset(String catalogueId) => citySpriteAsset(catalogueId);

int cityDistrictRank(String districtId) =>
    cityDistricts.indexWhere((district) => district.id == districtId) + 1;

void validateCityContentState(CityState state) {
  final knownDistricts = cityDistricts.map((district) => district.id).toSet();
  if (state.unlockedDistrictIds.isEmpty ||
      !state.unlockedDistrictIds.contains(cityDistricts.first.id) ||
      !knownDistricts.containsAll(state.unlockedDistrictIds)) {
    throw const FormatException(
      'The saved city references an unknown district.',
    );
  }

  for (final building in state.buildings) {
    final lot = cityLotById[building.lotId];
    final item = cityCatalogueById[building.catalogueId];
    final sprite = citySpriteManifest[building.catalogueId];
    if (lot == null || item == null || sprite == null) {
      throw const FormatException(
        'The saved city references an unknown lot or building type.',
      );
    }
    if (!state.unlockedDistrictIds.contains(lot.districtId) ||
        item.minimumDistrictRank > cityDistrictRank(lot.districtId) ||
        sprite.footprintColumns > lot.footprintColumns ||
        sprite.footprintRows > lot.footprintRows) {
      throw const FormatException(
        'The saved city contains an addition that does not fit its district.',
      );
    }
  }

  var expansionCount = 0;
  for (final construction in state.constructions) {
    if (construction.lotId case final lotId?) {
      final lot = cityLotById[lotId];
      final item = cityCatalogueById[construction.catalogueId];
      final sprite = citySpriteManifest[construction.catalogueId];
      if (lot == null || item == null || sprite == null) {
        throw const FormatException(
          'The saved city has a construction for unknown content.',
        );
      }
      if (!state.unlockedDistrictIds.contains(lot.districtId) ||
          item.minimumDistrictRank > cityDistrictRank(lot.districtId) ||
          sprite.footprintColumns > lot.footprintColumns ||
          sprite.footprintRows > lot.footprintRows) {
        throw const FormatException(
          'The saved construction is not eligible for its district.',
        );
      }
    } else if (construction.districtId case final districtId?) {
      expansionCount++;
      final targetIndex = cityDistricts.indexWhere(
        (district) => district.id == districtId,
      );
      if (targetIndex <= 0 ||
          state.unlockedDistrictIds.contains(districtId) ||
          !state.unlockedDistrictIds.contains(
            cityDistricts[targetIndex - 1].id,
          ) ||
          construction.catalogueId != 'district-expansion:$districtId') {
        throw const FormatException(
          'The saved city has an invalid district expansion.',
        );
      }
    }
  }
  if (expansionCount > 1) {
    throw const FormatException(
      'The saved city has multiple district expansions in progress.',
    );
  }
}

CityState newCityState({DateTime? today}) {
  final date = today ?? DateTime.now();
  return CityState(
    calendarDate: DateTime.utc(date.year, date.month, date.day),
    simulationSeconds: 0,
    coins: 0,
    totalCoinsEarned: 0,
    totalCoinsSpent: 0,
    nextConstructionNumber: 1,
    creditedDates: <String>{},
    unlockedDistrictIds: <String>{'village'},
    buildings: cityStartingBuildings,
    constructions: const [],
    events: const [],
  );
}

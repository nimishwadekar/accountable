import 'coordinates.dart';
import 'terrain_provider.dart';
import 'world_content.dart';
import 'world_queries.dart';
import 'world_state.dart';

class WorldRuleViolation implements Exception {
  const WorldRuleViolation(this.message);

  final String message;

  @override
  String toString() => message;
}

class WorldRules {
  const WorldRules({
    this.maximumBridgeSpan = 4,
    this.maximumCoordinate = 1000000,
  });

  final int maximumBridgeSpan;
  final int maximumCoordinate;
}

class ParcelPurchaseQuote {
  const ParcelPurchaseQuote({
    required this.coord,
    required this.price,
    required this.cells,
  });

  final ParcelCoord coord;
  final int price;
  final List<TerrainCell> cells;
  int get landCellCount => cells.where((cell) => cell.isLand).length;
}

class RoadProjectQuote {
  const RoadProjectQuote({
    required this.cells,
    required this.style,
    required this.totalCost,
    required this.builderSlot,
  });

  final List<CellCoord> cells;
  final RoadStyle style;
  final int totalCost;
  final int builderSlot;
}

class StructurePlacementQuote {
  const StructurePlacementQuote({
    required this.catalogueId,
    required this.origin,
    required this.quarterTurns,
    required this.footprint,
    required this.price,
    this.builderSlot,
  });

  final String catalogueId;
  final CellCoord origin;
  final int quarterTurns;
  final List<CellCoord> footprint;
  final int price;
  final int? builderSlot;
}

class StructureFundingQuote {
  const StructureFundingQuote({
    required this.jobId,
    required this.amount,
    required this.totalCost,
    required this.coinsFunded,
  });

  final String jobId;
  final int amount;
  final int totalCost;
  final int coinsFunded;
}

class RoadTileFundingQuote {
  const RoadTileFundingQuote({
    required this.jobId,
    required this.cell,
    required this.price,
  });

  final String jobId;
  final CellCoord cell;
  final int price;
}

class BridgeQuote {
  const BridgeQuote({
    required this.nearBank,
    required this.farBank,
    required this.waterCells,
    required this.riverBodyId,
    required this.parcelsToAcquire,
    required this.bridgeCost,
    required this.builderSlot,
  });

  final CellCoord nearBank;
  final CellCoord farBank;
  final List<CellCoord> waterCells;
  final String riverBodyId;
  final List<ParcelPurchaseQuote> parcelsToAcquire;
  final int bridgeCost;
  final int builderSlot;

  int get parcelCost =>
      parcelsToAcquire.fold<int>(0, (sum, parcel) => sum + parcel.price);
  int get totalPrice => bridgeCost + parcelCost;
}

ParcelPurchaseQuote quoteParcelPurchase(
  ParcelWorldState state,
  TerrainProvider terrainProvider,
  ParcelCoord candidate, {
  WorldRules rules = const WorldRules(),
}) {
  if (candidate.x.abs() > rules.maximumCoordinate ||
      candidate.y.abs() > rules.maximumCoordinate) {
    throw const WorldRuleViolation('That parcel is outside the supported map.');
  }
  final queries = WorldQueries(state, terrainProvider);
  if (queries.ownsParcel(candidate)) {
    throw const WorldRuleViolation('You already own that parcel.');
  }
  if (!candidate.neighbors.any(queries.ownsParcel)) {
    throw const WorldRuleViolation('Buy a neighboring parcel to expand there.');
  }
  if (!queries.parcelTouchesAccessibleLand(candidate)) {
    throw const WorldRuleViolation(
      'That parcel has no land connection from your accessible territory.',
    );
  }
  final cells = candidate
      .cells(state.parcelSize)
      .map((cell) => terrainProvider.sample(cell, state.seed))
      .toList();
  if (cells.every((cell) => !cell.isLand)) {
    throw const WorldRuleViolation('An all-water parcel cannot be purchased.');
  }
  return ParcelPurchaseQuote(
    coord: candidate,
    price: parcelCost(candidate, state.parcels.length),
    cells: cells,
  );
}

RoadProjectQuote quoteRoadStretch(
  ParcelWorldState state,
  TerrainProvider terrainProvider, {
  required List<CellCoord> cells,
  required RoadStyle style,
}) {
  if (cells.isEmpty) {
    throw const WorldRuleViolation('A road stretch needs at least one tile.');
  }
  if (!_unique(cells.map((cell) => cell.key))) {
    throw const WorldRuleViolation('A road stretch cannot revisit a tile.');
  }
  final builderSlot = _freeBuilderSlot(state);
  final queries = WorldQueries(state, terrainProvider);
  final completedRoads = queries.connectedRoadCells;
  if (!cells.first.neighbors.any(completedRoads.contains)) {
    throw const WorldRuleViolation(
      'Start the stretch beside a completed connected road.',
    );
  }
  for (var index = 0; index < cells.length; index++) {
    final cell = cells[index];
    if (!queries.ownsCell(cell) ||
        !queries.terrainAt(cell).isLand ||
        !queries.isLandReachable(cell)) {
      throw const WorldRuleViolation('Roads need owned, reachable dry land.');
    }
    if (queries.roadsByCell.containsKey(cell) ||
        queries.structuresByCell.containsKey(cell) ||
        queries.reservedCells.contains(cell)) {
      throw const WorldRuleViolation(
        'That road stretch overlaps an occupied tile.',
      );
    }
    if (index > 0 && !cells[index - 1].neighbors.contains(cell)) {
      throw const WorldRuleViolation('Road strokes must be four-connected.');
    }
  }
  return RoadProjectQuote(
    cells: List.unmodifiable(cells),
    style: style,
    totalCost: cells.length * roadCost(style),
    builderSlot: builderSlot,
  );
}

RoadTileFundingQuote quoteRoadTileFunding(
  ParcelWorldState state, {
  required TerrainProvider terrainProvider,
  required String projectId,
  required CellCoord cell,
}) {
  final project = _roadProject(state, projectId);
  if (!project.roadCells.contains(cell) ||
      state.roadsByCell.containsKey(cell)) {
    throw const WorldRuleViolation(
      'Select an unfinished tile in the road plan.',
    );
  }
  final completed = WorldQueries(state, terrainProvider).connectedRoadCells;
  if (!cell.neighbors.any(completed.contains)) {
    throw const WorldRuleViolation(
      'Fund only the next road tile touching a completed road tile.',
    );
  }
  return RoadTileFundingQuote(jobId: projectId, cell: cell, price: 1);
}

StructureFundingQuote quoteStructureFunding(
  ParcelWorldState state, {
  required String projectId,
  required int amount,
}) {
  final job = _structureProject(state, projectId);
  if (amount <= 0 || amount > state.coins || amount > job.coinsRemaining) {
    throw const WorldRuleViolation(
      'Choose a positive contribution no larger than your wallet or remaining cost.',
    );
  }
  return StructureFundingQuote(
    jobId: job.id,
    amount: amount,
    totalCost: job.totalCostCoins,
    coinsFunded: job.coinsFunded,
  );
}

StructurePlacementQuote quoteStructurePlacement(
  ParcelWorldState state,
  TerrainProvider terrainProvider, {
  required String catalogueId,
  required CellCoord origin,
  int quarterTurns = 0,
}) {
  final definition = structureById[catalogueId];
  if (definition == null || !state.unlockedCatalogueIds.contains(catalogueId)) {
    throw const WorldRuleViolation('That model has not been unlocked.');
  }
  final builderSlot = definition.kind == StructureKind.building
      ? _freeBuilderSlot(state)
      : null;
  final footprint = structureFootprint(
    definition,
    origin,
    quarterTurns: quarterTurns,
  );
  final queries = WorldQueries(state, terrainProvider);
  if (footprint.any((cell) => !queries.ownsCell(cell))) {
    throw const WorldRuleViolation('Every footprint cell needs owned land.');
  }
  if (footprint.any(
    (cell) => !queries.terrainAt(cell).isLand || !queries.isLandReachable(cell),
  )) {
    throw const WorldRuleViolation('Buildings need accessible dry land.');
  }
  if (!queries.footprintIsVacant(footprint)) {
    throw const WorldRuleViolation(
      'That footprint overlaps a road, structure, or construction site.',
    );
  }
  if (definition.kind == StructureKind.building &&
      !queries.buildingHasRoadAccess(footprint)) {
    throw const WorldRuleViolation(
      'Place the building beside a connected road first.',
    );
  }
  return StructurePlacementQuote(
    catalogueId: catalogueId,
    origin: origin,
    quarterTurns: quarterTurns % 4,
    footprint: footprint,
    price: definition.costCoins,
    builderSlot: builderSlot,
  );
}

BridgeQuote quoteRiverBridge(
  ParcelWorldState state,
  TerrainProvider terrainProvider, {
  required CellCoord nearBank,
  required CellCoord farBank,
  WorldRules rules = const WorldRules(),
}) {
  final queries = WorldQueries(state, terrainProvider);
  final builderSlot = _freeBuilderSlot(state);
  if (nearBank.column.abs() > rules.maximumCoordinate ||
      nearBank.row.abs() > rules.maximumCoordinate ||
      farBank.column.abs() > rules.maximumCoordinate ||
      farBank.row.abs() > rules.maximumCoordinate) {
    throw const WorldRuleViolation('That bridge is outside the supported map.');
  }
  if (!queries.isRoadConnected(nearBank)) {
    throw const WorldRuleViolation(
      'Start the bridge from a connected road on the near bank.',
    );
  }
  final dx = farBank.column - nearBank.column;
  final dy = farBank.row - nearBank.row;
  if ((dx == 0) == (dy == 0)) {
    throw const WorldRuleViolation(
      'Bridges must be straight and aligned to the tile grid.',
    );
  }
  final distance = dx.abs() + dy.abs();
  final spanLength = distance - 1;
  if (spanLength < 1 || spanLength > rules.maximumBridgeSpan) {
    throw WorldRuleViolation(
      'This bridge must span between 1 and ${rules.maximumBridgeSpan} water tiles.',
    );
  }
  if (!queries.terrainAt(nearBank).isLand ||
      !terrainProvider.sample(farBank, state.seed).isLand) {
    throw const WorldRuleViolation(
      'A bridge must land on dry ground at both ends.',
    );
  }
  if (queries.roadsByCell.containsKey(farBank) ||
      queries.structuresByCell.containsKey(farBank) ||
      queries.reservedCells.contains(farBank)) {
    throw const WorldRuleViolation('The far-bank landing cell is occupied.');
  }

  final step = CellCoord(dx.sign, dy.sign);
  final waterCells = <CellCoord>[];
  String? bodyId;
  for (var index = 1; index < distance; index++) {
    final cell = nearBank.offset(step.column * index, step.row * index);
    final terrain = terrainProvider.sample(cell, state.seed);
    if (terrain.kind != TerrainKind.river || terrain.waterBodyId == null) {
      throw const WorldRuleViolation(
        'Bridges may span one continuous river only—not lakes or oceans.',
      );
    }
    bodyId ??= terrain.waterBodyId;
    if (bodyId != terrain.waterBodyId) {
      throw const WorldRuleViolation(
        'A bridge cannot join separate water bodies.',
      );
    }
    if (queries.reservedCells.contains(cell) ||
        queries.roadsByCell.containsKey(cell) ||
        queries.structuresByCell.containsKey(cell)) {
      throw const WorldRuleViolation(
        'Part of that bridge span is already reserved.',
      );
    }
    waterCells.add(cell);
  }

  if (bodyId == null) {
    throw const WorldRuleViolation('No river was found between those banks.');
  }
  final requiredParcels =
      <ParcelCoord>{
        ...waterCells.map(
          (cell) => parcelForCell(cell, parcelSize: state.parcelSize),
        ),
        parcelForCell(farBank, parcelSize: state.parcelSize),
      }.where((parcel) => !queries.ownsParcel(parcel)).toList()..sort((a, b) {
        final aDistance =
            (a.x - parcelForCell(nearBank, parcelSize: state.parcelSize).x)
                .abs() +
            (a.y - parcelForCell(nearBank, parcelSize: state.parcelSize).y)
                .abs();
        final bDistance =
            (b.x - parcelForCell(nearBank, parcelSize: state.parcelSize).x)
                .abs() +
            (b.y - parcelForCell(nearBank, parcelSize: state.parcelSize).y)
                .abs();
        return aDistance.compareTo(bDistance);
      });

  final parcelQuotes = <ParcelPurchaseQuote>[];
  var ownedCount = state.parcels.length;
  for (final parcel in requiredParcels) {
    final terrain = parcel
        .cells(state.parcelSize)
        .map((cell) => terrainProvider.sample(cell, state.seed))
        .toList();
    parcelQuotes.add(
      ParcelPurchaseQuote(
        coord: parcel,
        price: parcelCost(parcel, ownedCount),
        cells: terrain,
      ),
    );
    ownedCount++;
  }
  return BridgeQuote(
    nearBank: nearBank,
    farBank: farBank,
    waterCells: waterCells,
    riverBodyId: bodyId,
    parcelsToAcquire: parcelQuotes,
    bridgeCost: bridgeCost(spanLength),
    builderSlot: builderSlot,
  );
}

int _freeBuilderSlot(ParcelWorldState state) {
  final occupied = state.constructions.map((job) => job.builderSlot).toSet();
  for (var slot = 0; slot < state.builderCapacity; slot++) {
    if (!occupied.contains(slot)) return slot;
  }
  throw const WorldRuleViolation(
    'All builders are assigned. Finish a project before planning another.',
  );
}

WorldConstruction _roadProject(ParcelWorldState state, String projectId) {
  for (final job in state.constructions) {
    if (job.id == projectId && job.kind == WorldConstructionKind.road) {
      return job;
    }
  }
  throw const WorldRuleViolation('That road project is no longer active.');
}

WorldConstruction _structureProject(ParcelWorldState state, String projectId) {
  for (final job in state.constructions) {
    if (job.id == projectId &&
        job.kind == WorldConstructionKind.structure &&
        job.catalogueId != null) {
      return job;
    }
  }
  throw const WorldRuleViolation('That building project is no longer active.');
}

void validateParcelWorldState(
  ParcelWorldState state,
  TerrainProvider terrainProvider,
) {
  if (state.parcelSize != defaultParcelSize ||
      state.generatorVersion != terrainProvider.generatorVersion ||
      state.rulesVersion != parcelWorldRulesVersion ||
      state.contentVersion != parcelWorldContentVersion ||
      state.worldId.isEmpty ||
      state.builderCapacity < 1 ||
      state.constructions.length > state.builderCapacity ||
      state.constructionDay < 0 ||
      worldDateKey(state.checkInHighWaterDate).compareTo(state.dateKey) < 0 ||
      state.coins < 0 ||
      state.totalCoinsEarned < 0 ||
      state.totalCoinsSpent < 0 ||
      state.totalCoinsEarned - state.totalCoinsSpent != state.coins ||
      state.nextEntityNumber < 1 ||
      state.nextEventNumber < 1) {
    throw const FormatException('The parcel-world save has invalid counters.');
  }
  if (!state.parcelsByCoord.containsKey(const ParcelCoord(0, 0))) {
    throw const FormatException('The starting parcel is missing.');
  }
  final ownedCellSet = <CellCoord>{};
  for (final parcel in state.parcels) {
    if (parcel.pricePaid < 0 ||
        parcel.purchasedAtDay < 0 ||
        parcel.purchasedAtDay > state.constructionDay ||
        parcel.terrain.length != state.parcelSize * state.parcelSize) {
      throw const FormatException('A saved parcel is incomplete.');
    }
    for (final cell in parcel.terrain) {
      if (!parcel.coord.cells(state.parcelSize).contains(cell.coord) ||
          !ownedCellSet.add(cell.coord) ||
          !_sameTerrain(cell, terrainProvider.sample(cell.coord, state.seed))) {
        throw const FormatException('Saved parcel terrain is inconsistent.');
      }
    }
  }

  final startCell = CellCoord(state.parcelSize ~/ 2, state.parcelSize ~/ 2);
  if (!state.roads.any(
    (road) =>
        road.id == 'road-start' &&
        road.cell == startCell &&
        road.style == RoadStyle.dirt &&
        road.pricePaid == 0,
  )) {
    throw const FormatException('The free starting dirt road is missing.');
  }
  if (!_unique(state.parcels.map((parcel) => parcel.coord.key)) ||
      !_unique(state.roads.map((road) => road.cell.key)) ||
      !_unique(state.roads.map((road) => road.id)) ||
      !_unique(state.structures.map((structure) => structure.id)) ||
      !_unique(state.bridges.map((bridge) => bridge.id)) ||
      !_unique(state.constructions.map((job) => job.id)) ||
      !_unique(state.constructions.map((job) => '${job.builderSlot}')) ||
      !_unique(state.events.map((event) => event.id))) {
    throw const FormatException('The parcel-world save has duplicate IDs.');
  }

  final queries = WorldQueries(state, terrainProvider);
  final occupied = <CellCoord>{};
  for (final road in state.roads) {
    if (road.pricePaid < 0 ||
        road.completedAtDay < 0 ||
        road.completedAtDay > state.constructionDay ||
        !queries.ownsCell(road.cell) ||
        !queries.terrainAt(road.cell).isLand ||
        !queries.isRoadConnected(road.cell) ||
        !occupied.add(road.cell)) {
      throw const FormatException(
        'The parcel-world save contains an invalid road.',
      );
    }
  }
  for (final structure in state.structures) {
    final definition = structureById[structure.catalogueId];
    final expected = definition == null
        ? const <CellCoord>[]
        : structureFootprint(
            definition,
            structure.origin,
            quarterTurns: structure.quarterTurns,
          );
    if (definition == null ||
        definition.kind != structure.kind ||
        structure.pricePaid < 0 ||
        structure.completedAtDay < 0 ||
        structure.completedAtDay > state.constructionDay ||
        structure.quarterTurns < 0 ||
        structure.quarterTurns > 3 ||
        !state.unlockedCatalogueIds.contains(structure.catalogueId) ||
        !_sameCells(expected, structure.footprint) ||
        structure.footprint.any(
          (cell) =>
              !queries.ownsCell(cell) ||
              !queries.terrainAt(cell).isLand ||
              !queries.isLandReachable(cell) ||
              !occupied.add(cell),
        )) {
      throw const FormatException(
        'The parcel-world save contains an invalid structure.',
      );
    }
    if (definition.kind == StructureKind.building &&
        !queries.buildingHasRoadAccess(structure.footprint)) {
      throw const FormatException(
        'The parcel-world save has a building without connected road access.',
      );
    }
  }
  for (final bridge in state.bridges) {
    if (bridge.waterCells.isEmpty ||
        bridge.waterCells.length > const WorldRules().maximumBridgeSpan ||
        bridge.pricePaid < 0 ||
        bridge.completedAtDay < 0 ||
        bridge.completedAtDay > state.constructionDay ||
        !_validBridgeGeometry(
          bridge.nearBank,
          bridge.farBank,
          bridge.waterCells,
          queries,
        ) ||
        !queries.isRoadConnected(bridge.nearBank) ||
        !queries.roadsByCell.containsKey(bridge.farBank)) {
      throw const FormatException(
        'The parcel-world save contains an invalid bridge.',
      );
    }
  }
  final reserved = <CellCoord>{};
  for (final bridge in state.bridges) {
    if (bridge.waterCells.any(
      (cell) => occupied.contains(cell) || !reserved.add(cell),
    )) {
      throw const FormatException('A bridge overlaps another world object.');
    }
  }
  for (final job in state.constructions) {
    if (job.totalCostCoins <= 0 ||
        job.coinsFunded < 0 ||
        job.coinsFunded >= job.totalCostCoins ||
        job.builderSlot < 0 ||
        job.builderSlot >= state.builderCapacity ||
        job.startedAtDay < 0 ||
        job.startedAtDay > state.constructionDay) {
      throw const FormatException(
        'The parcel-world save has an invalid project.',
      );
    }

    if (job.kind == WorldConstructionKind.structure) {
      final definition = job.catalogueId == null
          ? null
          : structureById[job.catalogueId];
      if (definition == null ||
          definition.kind != StructureKind.building ||
          job.totalCostCoins != definition.costCoins ||
          job.structureKind != definition.kind ||
          job.origin == null ||
          job.roadStyle != null ||
          job.roadCells.isNotEmpty ||
          job.nearBank != null ||
          job.farBank != null ||
          job.quarterTurns < 0 ||
          job.quarterTurns > 3 ||
          !_sameCells(
            structureFootprint(
              definition,
              job.origin!,
              quarterTurns: job.quarterTurns,
            ),
            job.footprint,
          ) ||
          !state.unlockedCatalogueIds.contains(definition.id) ||
          job.footprint.any(
            (cell) =>
                !queries.ownsCell(cell) ||
                !queries.terrainAt(cell).isLand ||
                !queries.isLandReachable(cell) ||
                occupied.contains(cell) ||
                !reserved.add(cell),
          ) ||
          !queries.buildingHasRoadAccess(job.footprint)) {
        throw const FormatException(
          'The parcel-world save has an invalid structure reservation.',
        );
      }
    } else if (job.kind == WorldConstructionKind.road) {
      final projectRoads = state.roads
          .where((road) => road.projectId == job.id)
          .toList();
      final projectRoadCells = projectRoads.map((road) => road.cell).toSet();
      final completedBeforeProject = queries.completedRoadCells.difference(
        projectRoadCells,
      );
      if (job.catalogueId != null ||
          job.structureKind != null ||
          job.origin != null ||
          job.roadStyle == null ||
          job.footprint.isNotEmpty ||
          job.waterCells.isNotEmpty ||
          job.nearBank != null ||
          job.farBank != null ||
          job.roadCells.isEmpty ||
          !_unique(job.roadCells.map((cell) => cell.key)) ||
          job.totalCostCoins != job.roadCells.length ||
          job.coinsFunded != projectRoads.length ||
          projectRoads.any((road) => !job.roadCells.contains(road.cell)) ||
          !job.roadCells.first.neighbors.any(completedBeforeProject.contains)) {
        throw const FormatException(
          'The parcel-world save has an invalid road plan.',
        );
      }
      for (var index = 0; index < job.roadCells.length; index++) {
        final cell = job.roadCells[index];
        final fundedRoad = queries.roadsByCell[cell];
        final fundedByThisProject = fundedRoad?.projectId == job.id;
        if (!queries.ownsCell(cell) ||
            !queries.terrainAt(cell).isLand ||
            !queries.isLandReachable(cell) ||
            (fundedRoad != null && !fundedByThisProject) ||
            (fundedByThisProject &&
                (fundedRoad!.style != job.roadStyle ||
                    fundedRoad.pricePaid != 1)) ||
            (!fundedByThisProject && occupied.contains(cell)) ||
            !reserved.add(cell) ||
            (index > 0 && !job.roadCells[index - 1].neighbors.contains(cell))) {
          throw const FormatException(
            'The parcel-world save has an invalid road tile.',
          );
        }
      }
    } else if (job.kind == WorldConstructionKind.bridge) {
      if (job.catalogueId != null ||
          job.structureKind != null ||
          job.origin != null ||
          job.quarterTurns != 0 ||
          job.footprint.isNotEmpty ||
          job.roadStyle != null ||
          job.roadCells.isNotEmpty ||
          job.nearBank == null ||
          job.farBank == null ||
          job.totalCostCoins != bridgeCost(job.waterCells.length) ||
          !_validBridgeGeometry(
            job.nearBank!,
            job.farBank!,
            job.waterCells,
            queries,
          ) ||
          !queries.isRoadConnected(job.nearBank!) ||
          queries.roadsByCell.containsKey(job.farBank) ||
          occupied.contains(job.farBank) ||
          job.waterCells.any((cell) => !reserved.add(cell)) ||
          !reserved.add(job.farBank!)) {
        throw const FormatException(
          'The parcel-world save has an invalid bridge reservation.',
        );
      }
    }
  }
  for (final date in state.creditedDates) {
    final parsed = DateTime.tryParse(date);
    if (parsed == null ||
        worldDateKey(parsed) != date ||
        date.compareTo(worldDateKey(state.checkInHighWaterDate)) > 0) {
      throw const FormatException(
        'The parcel-world save has an invalid check-in.',
      );
    }
  }

  final expectedUnlocks = structureCatalogue
      .where(
        (definition) =>
            state.completedBuildingCount >= definition.milestoneBuildings,
      )
      .map((definition) => definition.id)
      .toSet();
  if (!state.unlockedCatalogueIds.containsAll(expectedUnlocks) ||
      state.unlockedCatalogueIds.any((id) => !structureById.containsKey(id))) {
    throw const FormatException('The parcel-world model unlocks are invalid.');
  }

  final recordedSpending =
      state.parcels.fold<int>(0, (sum, parcel) => sum + parcel.pricePaid) +
      state.roads.fold<int>(0, (sum, road) => sum + road.pricePaid) +
      state.structures.fold<int>(
        0,
        (sum, structure) => sum + structure.pricePaid,
      ) +
      state.bridges.fold<int>(0, (sum, bridge) => sum + bridge.pricePaid) +
      state.constructions
          .where((job) => job.kind != WorldConstructionKind.road)
          .fold<int>(0, (sum, job) => sum + job.coinsFunded);
  if (recordedSpending != state.totalCoinsSpent) {
    throw const FormatException(
      'The parcel-world save has incomplete purchase receipts.',
    );
  }
}

bool _validBridgeGeometry(
  CellCoord nearBank,
  CellCoord farBank,
  List<CellCoord> waterCells,
  WorldQueries queries,
) {
  if (waterCells.isEmpty) return false;
  final dx = farBank.column - nearBank.column;
  final dy = farBank.row - nearBank.row;
  if ((dx == 0) == (dy == 0)) return false;
  final distance = dx.abs() + dy.abs();
  if (waterCells.length != distance - 1) return false;
  final step = CellCoord(dx.sign, dy.sign);
  String? bodyId;
  for (var index = 1; index < distance; index++) {
    final expected = nearBank.offset(step.column * index, step.row * index);
    final cell = waterCells[index - 1];
    final terrain = queries.terrainAt(cell);
    if (cell != expected ||
        terrain.kind != TerrainKind.river ||
        terrain.waterBodyId == null) {
      return false;
    }
    bodyId ??= terrain.waterBodyId;
    if (bodyId != terrain.waterBodyId || !queries.ownsCell(cell)) return false;
  }
  return queries.ownsCell(nearBank) &&
      queries.ownsCell(farBank) &&
      queries.terrainAt(nearBank).isLand &&
      queries.terrainAt(farBank).isLand;
}

bool _sameTerrain(TerrainCell a, TerrainCell b) =>
    a.coord == b.coord &&
    a.kind == b.kind &&
    a.groundStyle == b.groundStyle &&
    a.waterBodyId == b.waterBodyId;

bool _sameCells(List<CellCoord> a, List<CellCoord> b) {
  if (a.length != b.length) return false;
  return a.toSet().length == b.toSet().length && a.toSet().containsAll(b);
}

bool _unique(Iterable<String> ids) {
  final values = ids.toList();
  return values.toSet().length == values.length;
}

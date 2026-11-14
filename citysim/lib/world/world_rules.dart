import 'coordinates.dart';
import 'terrain_provider.dart';
import 'world_content.dart';
import 'world_queries.dart';
import 'world_state.dart';

import '../content/content_bundle.dart';

class WorldRuleViolation implements Exception {
  const WorldRuleViolation(this.message);

  final String message;

  @override
  String toString() => message;
}

class WorldRules {
  const WorldRules({this.maximumCoordinate = 1000000});

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
    required this.price,
  });

  final List<CellCoord> cells;
  final RoadStyle style;

  /// Upfront treasury price of the whole stretch, paid at planning;
  /// the tiles then creep in one per check-in.
  final int price;
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

class BridgeQuote {
  const BridgeQuote({
    required this.nearBank,
    required this.farBank,
    required this.spanCells,
    required this.bridgeCost,
  });

  final CellCoord nearBank;
  final CellCoord farBank;

  /// The cells between the banks — water or land alike.
  final List<CellCoord> spanCells;

  /// Upfront treasury price of the whole crossing, paid at planning.
  final int bridgeCost;
}

/// The town's per-check-in ledger: taxes collected and upkeep owed
/// from every completed building and every infrastructure tile that
/// exists — delivered bridge spans included, since upkeep counts per
/// tile as it appears. Pure projection; the check-in reducer and the
/// HUD's next-report projection share it.
class TownLedger {
  const TownLedger({required this.taxes, required this.upkeep});

  final int taxes;
  final int upkeep;
  int get net => taxes - upkeep;
}

TownLedger townLedger(ParcelWorldState state, ContentBundle content) {
  var taxes = 0;
  var upkeep = 0;
  for (final structure in state.structures) {
    final definition = content.structure(structure.catalogueId);
    taxes += definition?.taxCoins ?? 0;
    upkeep += definition?.upkeepCoins ?? 0;
  }
  var bridgeTiles = 0;
  for (final bridge in state.bridges) {
    bridgeTiles += bridge.waterCells.length;
  }
  for (final job in state.constructions) {
    if (job.kind != WorldConstructionKind.bridge) continue;
    bridgeTiles += (job.stagesDone - 1).clamp(0, job.waterCells.length);
  }
  taxes += state.roads.length * content.economy.roadTaxCoinsPerTile;
  upkeep += state.roads.length * content.economy.roadUpkeepCoinsPerTile;
  taxes += bridgeTiles * content.economy.bridgeTaxCoinsPerTile;
  upkeep += bridgeTiles * content.economy.bridgeUpkeepCoinsPerTile;
  return TownLedger(taxes: taxes, upkeep: upkeep);
}

/// Projects a two-click road or bridge line onto the closer axis: the
/// line runs straight from [start] along the axis with the larger
/// delta (ties go horizontal), ending at [end]'s coordinate on that
/// axis. Includes both endpoints; start == end yields a single tile.
List<CellCoord> straightLineBetween(CellCoord start, CellCoord end) {
  final dx = end.column - start.column;
  final dy = end.row - start.row;
  final last = dx.abs() >= dy.abs()
      ? CellCoord(end.column, start.row)
      : CellCoord(start.column, end.row);
  final stepX = last.column.compareTo(start.column);
  final stepY = last.row.compareTo(start.row);
  final length =
      (last.column - start.column).abs() + (last.row - start.row).abs();
  return [
    for (var index = 0; index <= length; index++)
      CellCoord(start.column + stepX * index, start.row + stepY * index),
  ];
}

ParcelPurchaseQuote quoteParcelPurchase(
  ParcelWorldState state,
  ContentBundle content,
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
  // Buyable means charted terrain — grass or water alike. Fog is the
  // uncharted default beyond the authored map, and authored fog
  // parcels stay hidden too: you cannot buy what you cannot see.
  // Owning a parcel and being able to build on it are different
  // things: building stays gated by land reachability, which bridges
  // grant.
  final origin = candidate.origin(state.parcelSize);
  if (terrainProvider.sample(origin, state.seed).kind == TerrainKind.fog) {
    throw const WorldRuleViolation('That parcel is hidden in the fog.');
  }
  final cells = candidate
      .cells(state.parcelSize)
      .map((cell) => terrainProvider.sample(cell, state.seed))
      .toList();
  return ParcelPurchaseQuote(
    coord: candidate,
    price: content.economy.parcelBaseCoins,
    cells: cells,
  );
}

RoadProjectQuote quoteRoadStretch(
  ParcelWorldState state,
  ContentBundle content,
  TerrainProvider terrainProvider, {
  required List<CellCoord> cells,
}) {
  if (cells.isEmpty) {
    throw const WorldRuleViolation('A road stretch needs at least one tile.');
  }
  if (!_unique(cells.map((cell) => cell.key))) {
    throw const WorldRuleViolation('A road stretch cannot revisit a tile.');
  }
  final queries = WorldQueries(state, terrainProvider);
  for (var index = 0; index < cells.length; index++) {
    final cell = cells[index];
    if (!queries.ownsCell(cell) || !queries.terrainAt(cell).isLand) {
      throw const WorldRuleViolation('Roads need owned dry land.');
    }
    if (queries.roadsByCell.containsKey(cell) ||
        queries.structuresByCell.containsKey(cell) ||
        queries.propsByCell.containsKey(cell) ||
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
    style: RoadStyle.asphalt,
    price: cells.length * content.roadTileCost(),
  );
}

/// The prop placement check, shared by the placement quote and the
/// renderer's live preview (which passes its prebuilt queries, so the
/// preview never rebuilds indexes): throws [WorldRuleViolation] when
/// [cell] at the subtile cannot hold a prop of [definition].
void checkPropPlacement(
  ParcelWorldState state,
  WorldQueries queries, {
  required StructureDefinition definition,
  required CellCoord cell,
  required int subtileX,
  required int subtileY,
}) {
  if (!definition.enabled ||
      !state.unlockedCatalogueIds.contains(definition.id)) {
    throw const WorldRuleViolation('That model has not been unlocked.');
  }
  if (!queries.ownsCell(cell)) {
    throw const WorldRuleViolation('Every footprint cell needs owned land.');
  }
  if (queries.structuresByCell.containsKey(cell) ||
      queries.constructionReservedCells.contains(cell) ||
      !queries.cellAcceptsProps(cell)) {
    throw const WorldRuleViolation('Props need vacant ground or road.');
  }
  if (queries.propAt(cell, subtileX, subtileY) != null) {
    throw const WorldRuleViolation('That subtile already holds a prop.');
  }
}

StructurePlacementQuote quoteStructurePlacement(
  ParcelWorldState state,
  ContentBundle content,
  TerrainProvider terrainProvider, {
  required String catalogueId,
  required CellCoord origin,
  int quarterTurns = 0,
  String? preferredFacing,
  int subtileX = propFrontSubtile,
  int subtileY = propFrontSubtile,
}) {
  final definition = content.structure(catalogueId);
  if (definition == null ||
      !definition.enabled ||
      !state.unlockedCatalogueIds.contains(catalogueId)) {
    throw const WorldRuleViolation('That model has not been unlocked.');
  }
  final builderSlot = definition.kind == StructureKind.building
      ? _freeBuilderSlot(state)
      : null;
  final queries = WorldQueries(state, terrainProvider);
  if (definition.kind == StructureKind.decoration) {
    // Decorations place as props on the subtile lattice; the surface
    // rules live in [checkPropPlacement], shared with the preview.
    checkPropPlacement(
      state,
      queries,
      definition: definition,
      cell: origin,
      subtileX: subtileX,
      subtileY: subtileY,
    );
    return StructurePlacementQuote(
      catalogueId: catalogueId,
      origin: origin,
      quarterTurns: 0,
      footprint: [origin],
      price: definition.costCoins,
    );
  }
  // Non-square footprints turn with their door side: the road beside
  // the tapped origin picks the side, and the footprint transposes so
  // its street edge lands on that road. Square footprints keep the
  // passed turn — every turn maps to the same cells.
  final turns = definition.footprintColumns == definition.footprintRows
      ? quarterTurns
      : footprintTurnsFor(
          definition,
          facingForPlacement(queries, [origin], preferredFacing),
        );
  final footprint = structureFootprint(definition, origin, quarterTurns: turns);
  if (footprint.any((cell) => !queries.ownsCell(cell))) {
    throw const WorldRuleViolation('Every footprint cell needs owned land.');
  }
  if (footprint.any((cell) => !queries.terrainAt(cell).isLand)) {
    throw const WorldRuleViolation('Buildings need dry land.');
  }
  if (!queries.footprintIsVacant(footprint)) {
    throw const WorldRuleViolation(
      'That footprint overlaps a road, structure, or construction site.',
    );
  }
  if (definition.kind == StructureKind.building &&
      !queries.buildingHasRoadAccess(footprint)) {
    throw const WorldRuleViolation('Place the building beside a road first.');
  }
  return StructurePlacementQuote(
    catalogueId: catalogueId,
    origin: origin,
    quarterTurns: turns % 4,
    footprint: footprint,
    price: definition.costCoins,
    builderSlot: builderSlot,
  );
}

BridgeQuote quoteBridge(
  ParcelWorldState state,
  ContentBundle content,
  TerrainProvider terrainProvider, {
  required CellCoord nearBank,
  required CellCoord farBank,
  WorldRules rules = const WorldRules(),
}) {
  final queries = WorldQueries(state, terrainProvider);
  if (nearBank.column.abs() > rules.maximumCoordinate ||
      nearBank.row.abs() > rules.maximumCoordinate ||
      farBank.column.abs() > rules.maximumCoordinate ||
      farBank.row.abs() > rules.maximumCoordinate) {
    throw const WorldRuleViolation('That bridge is outside the supported map.');
  }
  final dx = farBank.column - nearBank.column;
  final dy = farBank.row - nearBank.row;
  if ((dx == 0) == (dy == 0)) {
    throw const WorldRuleViolation(
      'Bridges must be straight and aligned to the tile grid.',
    );
  }
  final distance = dx.abs() + dy.abs();
  if (distance < 2) {
    throw const WorldRuleViolation(
      'A bridge needs at least one tile between its banks.',
    );
  }
  bool occupied(CellCoord cell) =>
      queries.roadsByCell.containsKey(cell) ||
      queries.structuresByCell.containsKey(cell) ||
      queries.propsByCell.containsKey(cell) ||
      queries.reservedCells.contains(cell);
  for (final bank in [nearBank, farBank]) {
    if (!queries.terrainAt(bank).isLand || !queries.ownsCell(bank)) {
      throw const WorldRuleViolation('Bridge banks need owned dry land.');
    }
    if (occupied(bank)) {
      throw const WorldRuleViolation('A bridge bank landing cell is occupied.');
    }
  }

  // The span may cross water and land alike, but everything under the
  // bridge must already be owned — nothing is auto-acquired.
  final step = CellCoord(dx.sign, dy.sign);
  final spanCells = <CellCoord>[];
  for (var index = 1; index < distance; index++) {
    final cell = nearBank.offset(step.column * index, step.row * index);
    if (!queries.ownsCell(cell)) {
      throw const WorldRuleViolation(
        'Everything under a bridge must be owned — buy the crossing '
        'parcels first.',
      );
    }
    if (occupied(cell)) {
      throw const WorldRuleViolation(
        'Part of that bridge span is already occupied.',
      );
    }
    spanCells.add(cell);
  }
  final roadTileCost = content.economy.roadTileCostCoins;
  final bridgeTileCost = content.economy.bridgeTileCostCoins;
  return BridgeQuote(
    nearBank: nearBank,
    farBank: farBank,
    spanCells: spanCells,
    bridgeCost: spanCells.length * bridgeTileCost + 2 * roadTileCost,
  );
}

/// Building crews are the concurrency limit — road and bridge creep
/// consumes no builder — so slots count structure jobs only.
int _freeBuilderSlot(ParcelWorldState state) {
  final occupied = state.constructions
      .where((job) => job.kind == WorldConstructionKind.structure)
      .map((job) => job.builderSlot)
      .toSet();
  for (var slot = 0; slot < state.builderCapacity; slot++) {
    if (!occupied.contains(slot)) return slot;
  }
  throw const WorldRuleViolation(
    'All builders are assigned. Finish a project before planning another.',
  );
}

void validateParcelWorldState(
  ParcelWorldState state,
  ContentBundle content,
  TerrainProvider terrainProvider,
) {
  if (state.parcelSize != defaultParcelSize ||
      state.generatorVersion != terrainProvider.generatorVersion ||
      state.rulesVersion != parcelWorldRulesVersion ||
      state.contentVersion != parcelWorldContentVersion ||
      state.worldId.isEmpty ||
      state.builderCapacity < 1 ||
      // Progression grants reconcile upward on load; a capacity below the
      // progression floor means the save was never reconciled.
      state.builderCapacity <
          content.economy.builderCapacityForPopulation(state.population) ||
      state.constructions
              .where((job) => job.kind == WorldConstructionKind.structure)
              .length >
          state.builderCapacity ||
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
        road.pricePaid == 0,
  )) {
    throw const FormatException('The free starting road is missing.');
  }
  if (!_unique(state.parcels.map((parcel) => parcel.coord.key)) ||
      !_unique(state.roads.map((road) => road.cell.key)) ||
      !_unique(state.roads.map((road) => road.id)) ||
      !_unique(state.structures.map((structure) => structure.id)) ||
      !_unique(state.bridges.map((bridge) => bridge.id)) ||
      !_unique(state.constructions.map((job) => job.id)) ||
      !_unique(
        state.constructions
            .where((job) => job.kind == WorldConstructionKind.structure)
            .map((job) => '${job.builderSlot}'),
      ) ||
      !_unique(state.events.map((event) => event.id))) {
    throw const FormatException('The parcel-world save has duplicate IDs.');
  }

  final queries = WorldQueries(state, terrainProvider);
  // Door sides must match the sprite they render: a left/right facing is
  // only valid on a sprite that has facings, and facings sprites must
  // carry one.
  bool facingMatchesSprite(String? facing, String? role) {
    if (facing != null &&
        facing != 'north' &&
        facing != 'east' &&
        facing != 'south' &&
        facing != 'west') {
      return false;
    }
    final sprite = role == null ? null : content.sprite(role);
    final hasFacings = sprite != null && sprite.hasFacings;
    return hasFacings ? facing != null : facing == null;
  }

  final occupied = <CellCoord>{};
  for (final road in state.roads) {
    if (road.pricePaid < 0 ||
        road.completedAtDay < 0 ||
        road.completedAtDay > state.constructionDay ||
        !queries.ownsCell(road.cell) ||
        !queries.terrainAt(road.cell).isLand ||
        !occupied.add(road.cell)) {
      throw const FormatException(
        'The parcel-world save contains an invalid road.',
      );
    }
  }
  for (final structure in state.structures) {
    final definition = content.structure(structure.catalogueId);
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
        !facingMatchesSprite(
          structure.facing,
          structure.assetRole ?? definition.assetRoles.first,
        ) ||
        !_sameCells(expected, structure.footprint) ||
        structure.footprint.any(
          (cell) =>
              !queries.ownsCell(cell) ||
              !queries.terrainAt(cell).isLand ||
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
  // Props: one per subtile, on the placement surface (ground, road,
  // or completed deck) and never under a building or a pending
  // project. Roads and completed decks may carry props, so — unlike
  // buildings — props are not checked against the occupied set.
  final propAnchors = <String>{};
  for (final prop in state.props) {
    final definition = content.structure(prop.catalogueId);
    if (definition == null ||
        definition.kind != StructureKind.decoration ||
        prop.pricePaid < 0 ||
        prop.placedAtDay < 0 ||
        prop.placedAtDay > state.constructionDay ||
        prop.subtileX < 0 ||
        prop.subtileX >= propSubtilesPerAxis ||
        prop.subtileY < 0 ||
        prop.subtileY >= propSubtilesPerAxis ||
        !state.unlockedCatalogueIds.contains(prop.catalogueId) ||
        (prop.assetRole != null &&
            !definition.assetRoles.contains(prop.assetRole)) ||
        !facingMatchesSprite(
          prop.facing,
          prop.assetRole ?? definition.assetRoles.first,
        ) ||
        !queries.ownsCell(prop.cell) ||
        !queries.cellAcceptsProps(prop.cell) ||
        queries.structuresByCell.containsKey(prop.cell) ||
        queries.constructionReservedCells.contains(prop.cell) ||
        !propAnchors.add(
          '${prop.cell.key}:${prop.subtileX}.${prop.subtileY}',
        )) {
      throw const FormatException(
        'The parcel-world save contains an invalid prop.',
      );
    }
  }
  for (final bridge in state.bridges) {
    // Bridges may stand anywhere — disconnected crossings included —
    // so the only bank requirement is that both landings are road
    // tiles once the bridge opens. Connectivity to the starter road
    // stopped being a rule with free road placement.
    if (bridge.waterCells.isEmpty ||
        bridge.pricePaid < 0 ||
        bridge.completedAtDay < 0 ||
        bridge.completedAtDay > state.constructionDay ||
        !_validBridgeGeometry(
          bridge.nearBank,
          bridge.farBank,
          bridge.waterCells,
          queries,
        ) ||
        !queries.roadsByCell.containsKey(bridge.nearBank) ||
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
    if (job.stagesDone < 0 ||
        job.startedAtDay < 0 ||
        job.startedAtDay > state.constructionDay) {
      throw const FormatException(
        'The parcel-world save has an invalid project.',
      );
    }

    if (job.kind == WorldConstructionKind.structure) {
      final definition = job.catalogueId == null
          ? null
          : content.structure(job.catalogueId!);
      if (definition == null ||
          definition.kind != StructureKind.building ||
          job.structureKind != definition.kind ||
          job.stagesDone >= definition.constructionStages ||
          job.builderSlot == null ||
          job.builderSlot! < 0 ||
          job.builderSlot! >= state.builderCapacity ||
          job.origin == null ||
          job.roadStyle != null ||
          job.roadCells.isNotEmpty ||
          job.nearBank != null ||
          job.farBank != null ||
          job.quarterTurns < 0 ||
          job.quarterTurns > 3 ||
          !facingMatchesSprite(
            job.facing,
            job.assetRole ?? definition.assetRoles.first,
          ) ||
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
      // Delivery completes tiles in order from the start: the
      // delivered roads are exactly the first delivered tiles of the
      // plan, and the count itself comes from those rows.
      final deliveredPrefix = job.roadCells.take(projectRoads.length).toList();
      if (job.catalogueId != null ||
          job.structureKind != null ||
          job.origin != null ||
          job.builderSlot != null ||
          job.roadStyle == null ||
          job.footprint.isNotEmpty ||
          job.waterCells.isNotEmpty ||
          job.nearBank != null ||
          job.farBank != null ||
          job.roadCells.isEmpty ||
          !_unique(job.roadCells.map((cell) => cell.key)) ||
          projectRoads.length != deliveredPrefix.length ||
          !deliveredPrefix.every(
            (cell) => projectRoads.any((road) => road.cell == cell),
          )) {
        throw const FormatException(
          'The parcel-world save contains an invalid road plan.',
        );
      }
      for (var index = 0; index < job.roadCells.length; index++) {
        final cell = job.roadCells[index];
        final fundedRoad = queries.roadsByCell[cell];
        final fundedByThisProject = fundedRoad?.projectId == job.id;
        if (!queries.ownsCell(cell) ||
            !queries.terrainAt(cell).isLand ||
            (fundedRoad != null && !fundedByThisProject) ||
            (fundedByThisProject &&
                (fundedRoad!.pricePaid != content.economy.roadTileCostCoins ||
                    index >= projectRoads.length)) ||
            (!fundedByThisProject && occupied.contains(cell)) ||
            !reserved.add(cell) ||
            (index > 0 && !job.roadCells[index - 1].neighbors.contains(cell))) {
          throw const FormatException(
            'The parcel-world save contains an invalid road tile.',
          );
        }
      }
    } else if (job.kind == WorldConstructionKind.bridge) {
      final nearBankRoad = queries.roadsByCell[job.nearBank!];
      // Delivery order is near bank, span tiles, far bank: the near
      // bank completes as a road tile once the first cell is
      // delivered; the far bank only completes with the project
      // itself. The delivered count and the bank road must agree.
      final nearBankFunded =
          nearBankRoad != null && nearBankRoad.projectId == job.id;
      final nearBankDue = job.stagesDone >= 1;
      if (job.catalogueId != null ||
          job.structureKind != null ||
          job.origin != null ||
          job.builderSlot != null ||
          job.quarterTurns != 0 ||
          job.footprint.isNotEmpty ||
          job.roadStyle != null ||
          job.roadCells.isNotEmpty ||
          job.nearBank == null ||
          job.farBank == null ||
          job.stagesDone >= job.waterCells.length + 2 ||
          !_validBridgeGeometry(
            job.nearBank!,
            job.farBank!,
            job.waterCells,
            queries,
          ) ||
          (nearBankRoad != null && !nearBankFunded) ||
          nearBankFunded != nearBankDue ||
          queries.roadsByCell.containsKey(job.farBank) ||
          occupied.contains(job.farBank) ||
          job.waterCells.any((cell) => !reserved.add(cell)) ||
          !reserved.add(job.farBank!)) {
        throw const FormatException(
          'The parcel-world save contains an invalid bridge reservation.',
        );
      }
    }
  }
  // Population gates: enabled models whose unlock threshold the settlement's
  // derived population has reached must be unlocked. Disabled models stay
  // valid in the unlock set (disable-not-delete keeps old saves loadable).
  final expectedUnlocks = content.purchaseableModels
      .where((model) => state.population >= model.unlockAtPopulation)
      .map((model) => model.id)
      .toSet();
  if (!state.unlockedCatalogueIds.containsAll(expectedUnlocks) ||
      state.unlockedCatalogueIds.any((id) => content.structure(id) == null)) {
    throw const FormatException('The parcel-world model unlocks are invalid.');
  }

  // Purchase receipts are not reconstructible from the sheet storage;
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
  for (var index = 1; index < distance; index++) {
    final expected = nearBank.offset(step.column * index, step.row * index);
    final cell = waterCells[index - 1];
    // Spans may cross water and land alike; ownership is the rule.
    if (cell != expected || !queries.ownsCell(cell)) {
      return false;
    }
  }
  return queries.ownsCell(nearBank) &&
      queries.ownsCell(farBank) &&
      queries.terrainAt(nearBank).isLand &&
      queries.terrainAt(farBank).isLand;
}

bool _sameTerrain(TerrainCell a, TerrainCell b) =>
    a.coord == b.coord && a.kind == b.kind && a.groundStyle == b.groundStyle;

bool _sameCells(List<CellCoord> a, List<CellCoord> b) {
  if (a.length != b.length) return false;
  return a.toSet().length == b.toSet().length && a.toSet().containsAll(b);
}

bool _unique(Iterable<String> ids) {
  final values = ids.toList();
  return values.toSet().length == values.length;
}

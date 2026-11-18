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
    required this.basePrice,
    required this.perPopulationCoins,
  });

  final ParcelCoord coord;

  /// Total price: [basePrice] plus [perPopulationCoins] for every
  /// point of the settlement's population — expanding a town gets
  /// pricier as it grows.
  final int price;

  /// The flat part of the price, before the population surcharge.
  final int basePrice;
  final int perPopulationCoins;
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
  /// the whole stretch then lands on the next check-in.
  final int price;
}

class StructurePlacementQuote {
  const StructurePlacementQuote({
    required this.catalogueId,
    required this.origin,
    required this.quarterTurns,
    required this.footprint,
    required this.price,
  });

  final String catalogueId;
  final CellCoord origin;
  final int quarterTurns;
  final List<CellCoord> footprint;
  final int price;
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

/// What demolishing a completed building does: no refund, the
/// footprint frees, and the town absorbs the occupancy loss. The
/// eviction cascade in numbers — population only falls when the
/// remaining beds cannot house everyone; of those who lose their
/// homes, the waiting list takes what its cap allows and the rest
/// leave town for good.
class StructureDemolitionQuote {
  const StructureDemolitionQuote({
    required this.structure,
    required this.model,
    required this.bedsAfter,
    required this.jobsAfter,
    required this.stayers,
    required this.evicted,
    required this.joinDemand,
    required this.leftTown,
  });

  final PlacedStructure structure;
  final StructureDefinition model;

  /// Remaining beds and jobs, counted the way the ledger counts
  /// them: live content over the surviving buildings.
  final int bedsAfter;
  final int jobsAfter;

  /// Residents that keep their homes — the whole population when
  /// the beds still fit everyone.
  final int stayers;

  /// Residents that lose their homes; [joinDemand] of them join the
  /// waiting list and [leftTown] leave the city for good.
  final int evicted;
  final int joinDemand;
  final int leftTown;
}

/// The town's per-check-in ledger and vitality. Taxes are collected
/// from occupied buildings only — occupancy scales each building's
/// flat tax — and multiplied by contentment; upkeep is owed in full,
/// vacant or not (the anti-shop-farming guard: an unpatronized shop
/// is a pure upkeep drain). Infrastructure counts per tile that
/// exists, delivered bridge spans included. Demand and coverage are
/// the same projection the Town card shows. Pure and shared: the
/// check-in reducer, the HUD projection, and the bars all read it.
class TownLedger {
  const TownLedger({
    required this.grossTaxes,
    required this.taxes,
    required this.upkeep,
    required this.contentment,
    required this.residentialDemand,
    required this.employmentDemand,
    required this.residentialVacancy,
    required this.jobVacancy,
    required this.coverage,
  });

  /// Taxes before contentment: home taxes scaled by the employment
  /// rate over residential capacity, commerce taxes by the staffing
  /// rate over job capacity. Only employed people pay.
  final double grossTaxes;

  /// Taxes after contentment, rounded once on the total.
  final int taxes;
  final int upkeep;
  int get net => taxes - upkeep;

  /// Contentment as a percentage — average service coverage above
  /// the requirement population, 100 below it, never under the
  /// floor.
  final int contentment;

  /// The residential waiting list: population that wants in but
  /// cannot (no housing).
  final int residentialDemand;

  /// Unemployed citizens: people living in town without a job.
  final int employmentDemand;

  /// Vacant home capacity and vacant job positions. Negative
  /// residential vacancy grandfathers a population above capacity.
  final int residentialVacancy;
  final int jobVacancy;

  /// Coverage per required service category (0..1). Empty below the
  /// requirement population — nothing is demanded yet.
  final Map<String, double> coverage;
}

TownLedger townLedger(ParcelWorldState state, ContentBundle content) {
  final economy = content.economy;
  final population = state.population;
  final employed = state.employedPopulation;

  // Capacities and taxes are content; occupancy is the stored
  // aggregate. Only employed people pay: home taxes scale by the
  // employment rate over residential capacity, commerce taxes by
  // the staffing rate over job capacity — every home pays the
  // average rate, so unemployment reads as a town condition, not a
  // named citizen's. Service buildings are civic, never commerce:
  // their jobs are the town's employer appeal (the arrival pull),
  // never part of the commerce levy — a staffed clinic must not
  // dilute what the shops pay. Civic buildings are always active.
  // Upkeep is always owed in full, vacant or not.
  var residentialCapacity = 0;
  var jobCapacity = 0;
  var homeTax = 0;
  var commerceTax = 0;
  var civicTax = 0;
  var upkeep = 0;
  for (final structure in state.structures) {
    final model = content.structure(structure.catalogueId);
    if (model == null) continue;
    if (model.isResidential) {
      residentialCapacity += model.population;
      homeTax += model.taxCoins;
    } else if (model.isService) {
      civicTax += model.taxCoins;
    } else if (model.isCommerce) {
      jobCapacity += model.jobs;
      commerceTax += model.taxCoins;
    } else {
      civicTax += model.taxCoins;
    }
    upkeep += model.upkeepCoins;
  }
  var gross = 0.0;
  if (residentialCapacity > 0) {
    // Homes pay their levy whether or not everyone holds a job: at
    // least the unemployment floor, topped back up to the full rate
    // by employment. The floor is the soft-lock fix — without it a
    // homes-only town earns literally nothing (only employed people
    // paid), so it could never afford the roads or land a café
    // needed to recover. Realistic too: unemployed people still pay
    // rent and sales taxes; employment raises a town's base rather
    // than creating it from nothing.
    final employmentRate = employed / residentialCapacity;
    final floor = economy.homeTaxUnemploymentFloorPercent / 100;
    final homeLevyRate = employmentRate < floor ? floor : employmentRate;
    gross += homeTax * homeLevyRate;
  }
  if (jobCapacity > 0) {
    // Clamped at full staffing: a save whose employed count outruns
    // the commerce pool (saves from before service buildings left
    // the levy) must not pay above the catalogue rate.
    gross += commerceTax * (employed / jobCapacity).clamp(0.0, 1.0);
  }
  gross += civicTax;
  var bridgeTiles = 0;
  for (final bridge in state.bridges) {
    bridgeTiles += bridge.waterCells.length;
  }
  for (final job in state.constructions) {
    if (job.kind != WorldConstructionKind.bridge) continue;
    bridgeTiles += (job.stagesDone - 1).clamp(0, job.waterCells.length);
  }
  gross += state.roads.length * economy.roadTaxCoinsPerTile;
  upkeep += state.roads.length * economy.roadUpkeepCoinsPerTile;
  gross += bridgeTiles * economy.bridgeTaxCoinsPerTile;
  upkeep += bridgeTiles * economy.bridgeUpkeepCoinsPerTile;

  // Contentment: average coverage across the required service
  // categories once the town is big enough to be demanding; full
  // contentment below that; the floor applies always. Contentment
  // is the town's appeal to newcomers, never its tax collector —
  // it scales the migration pipeline (see the check-in's demand
  // pass), so an unhappy town stagnates rather than going broke.
  final coverage = <String, double>{};
  var contentment = 100;
  if (population >= economy.serviceRequirementPopulation) {
    var sum = 0.0;
    for (final category in economy.requiredServiceCategories) {
      var capacity = 0;
      for (final structure in state.structures) {
        final model = content.structure(structure.catalogueId);
        if (model?.serviceCategory == category) {
          capacity += model?.serviceCapacity ?? 0;
        }
      }
      final ratio = population <= 0
          ? 1.0
          : (capacity / population).clamp(0.0, 1.0);
      coverage[category] = ratio;
      sum += ratio;
    }
    final average = economy.requiredServiceCategories.isEmpty
        ? 1.0
        : sum / economy.requiredServiceCategories.length;
    contentment = (average * 100).round();
  }
  if (contentment < economy.contentmentFloorPercent) {
    contentment = economy.contentmentFloorPercent;
  }

  // Taxes are the levy, unmultiplied: nothing may push income below
  // the levy floor, so the homes-only guarantee (floored levy ≥
  // upkeep) holds unconditionally.
  final taxes = gross.round();
  return TownLedger(
    grossTaxes: gross,
    taxes: taxes,
    upkeep: upkeep,
    contentment: contentment,
    residentialDemand: state.waitingPopulation,
    employmentDemand: state.unemployment,
    residentialVacancy: residentialCapacity - population,
    jobVacancy: jobCapacity - employed,
    coverage: coverage,
  );
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
  Set<ParcelCoord> claimedParcels = const {},
}) {
  if (candidate.x.abs() > rules.maximumCoordinate ||
      candidate.y.abs() > rules.maximumCoordinate) {
    throw const WorldRuleViolation('That parcel is outside the supported map.');
  }
  final queries = WorldQueries(state, terrainProvider);
  if (queries.ownsParcel(candidate)) {
    throw const WorldRuleViolation('You already own that parcel.');
  }
  // One map, exclusive parcels: another city's claim is as final as
  // this city's ownership. The session passes the union of every
  // other city's parcels.
  if (claimedParcels.contains(candidate)) {
    throw const WorldRuleViolation('Another city has claimed that parcel.');
  }
  // The founding purchase — a new game's first — is free and needs
  // no neighbour, because nothing is owned yet. It still needs
  // buildable ground: five or more land cells for the first road and
  // home, so the opening can never dead-end on water. Every later
  // purchase is normal: adjacent, and priced by the settlement's
  // size.
  final founding = state.parcels.isEmpty;
  if (!founding && !candidate.neighbors.any(queries.ownsParcel)) {
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
  if (founding &&
      cells.where((cell) => cell.isLand).length < foundingLandCells) {
    throw const WorldRuleViolation(
      'Your founding parcel needs at least $foundingLandCells land '
      'cells — pick somewhere you can build.',
    );
  }
  final base = content.economy.parcelBaseCoins;
  final perPopulation = content.economy.parcelPerPopulationCoins;
  return ParcelPurchaseQuote(
    coord: candidate,
    price: founding ? 0 : base + perPopulation * state.population,
    cells: cells,
    basePrice: base,
    perPopulationCoins: perPopulation,
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
        'That road stretch overlaps an occupied tile — a road, '
        'structure, prop, or construction site. Clear the land first.',
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

/// Quotes demolishing a completed building: the occupancy cascade
/// computed without touching the state, so the confirm dialog and
/// the CLI can show exactly what the town loses before anything
/// goes. In-flight construction sites are not buildings — they are
/// not demolishable and this quote refuses them.
StructureDemolitionQuote quoteStructureDemolition(
  ParcelWorldState state,
  ContentBundle content, {
  required String structureId,
}) {
  PlacedStructure? target;
  for (final structure in state.structures) {
    if (structure.id == structureId) {
      target = structure;
      break;
    }
  }
  if (target == null) {
    throw const WorldRuleViolation('That building is no longer standing.');
  }
  final model = content.structure(target.catalogueId);
  if (model == null) {
    throw WorldRuleViolation(
      'Unknown building "${target.catalogueId}" — it cannot be demolished.',
    );
  }
  // The town's remaining capacities, counted the way the ledger
  // counts them: live content over the surviving buildings.
  var bedsAfter = 0;
  var jobsAfter = 0;
  for (final structure in state.structures) {
    if (structure.id == structureId) continue;
    final other = content.structure(structure.catalogueId);
    if (other == null) continue;
    if (other.isResidential) bedsAfter += other.population;
    if (other.isCommerce) jobsAfter += other.jobs;
  }
  final stayers = state.population < bedsAfter ? state.population : bedsAfter;
  final evicted = state.population - stayers;
  // The waiting list's cap, exactly as the check-in refill caps it:
  // a percentage of the surviving population, floored at one.
  final cap = ((stayers * content.economy.waitingPopulationCapPercent) ~/ 100)
      .clamp(1, 1 << 30);
  final room = (cap - state.waitingPopulation).clamp(0, 1 << 30);
  final joinDemand = room < evicted ? room : evicted;
  return StructureDemolitionQuote(
    structure: target,
    model: model,
    bedsAfter: bedsAfter,
    jobsAfter: jobsAfter,
    stayers: stayers,
    evicted: evicted,
    joinDemand: joinDemand,
    leftTown: evicted - joinDemand,
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
      'That footprint overlaps a road, structure, prop, or '
      'construction site. Clear the land first.',
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

void validateParcelWorldState(
  ParcelWorldState state,
  ContentBundle content,
  TerrainProvider terrainProvider,
) {
  if (state.parcelSize != defaultParcelSize ||
      state.generatorVersion != terrainProvider.generatorVersion ||
      state.constructionDay < 0 ||
      worldDateKey(state.checkInHighWaterDate).compareTo(state.dateKey) < 0 ||
      state.coins < 0 ||
      state.totalCoinsEarned < 0 ||
      state.totalCoinsSpent < 0 ||
      state.waitingPopulation < 0 ||
      state.population < 0 ||
      state.employedPopulation < 0 ||
      state.employedPopulation > state.population ||
      state.totalCoinsEarned - state.totalCoinsSpent != state.coins ||
      state.nextEntityNumber < 1 ||
      state.nextEventNumber < 1) {
    throw const FormatException('The parcel-world save has invalid counters.');
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

  if (!_unique(state.parcels.map((parcel) => parcel.coord.key)) ||
      !_unique(state.roads.map((road) => road.cell.key)) ||
      !_unique(state.roads.map((road) => road.id)) ||
      !_unique(state.structures.map((structure) => structure.id)) ||
      !_unique(state.bridges.map((bridge) => bridge.id)) ||
      !_unique(state.constructions.map((job) => job.id)) ||
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
  // The ownership invariant first: nothing exists anywhere without
  // an explicitly purchased parcel — a prop outside owned parcels
  // can only come from a hand-edited save.
  for (final prop in state.props) {
    if (!queries.ownsCell(prop.cell)) {
      throw FormatException(
        'A prop stands outside owned parcels at ${prop.cell.key} — '
        'nothing exists without a purchased parcel.',
      );
    }
  }
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
  // The unlock set gates *placement*, never possession: saves may
  // legally hold items above the reached milestone (nature exotics,
  // re-tiered content), so only garbage ids are invalid here.
  // Disabled models stay valid in the set (disable-not-delete keeps
  // old saves loadable).
  if (state.unlockedCatalogueIds.any((id) => content.structure(id) == null)) {
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

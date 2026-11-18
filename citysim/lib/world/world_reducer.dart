import 'coordinates.dart';
import 'terrain_provider.dart';
import 'world_content.dart';
import 'world_queries.dart';
import 'world_rules.dart';
import 'world_state.dart';

import '../content/content_bundle.dart';

/// The check-in is the town report and the only heartbeat, in a
/// fixed order: taxes are collected, upkeep is netted (the treasury
/// floors at zero — the shortfall is reported but never blocks
/// anything), and then every in-flight project advances one stage.
/// Nothing progresses in real time or on simulated days.
ParcelWorldState checkInWorldForToday(
  ParcelWorldState state,
  ContentBundle content,
) {
  if (!canCheckInWorldToday(state)) return state;

  // The town ledger — taxes then upkeep, from [townLedger]: completed
  // buildings plus per-tile infrastructure (seeded at zero — paving
  // never mints coins). Sites under construction pay nothing; tax
  // starts on completion. Upkeep is paid down to the floor; money
  // gates expansion, never growth: an unpaid shortfall pauses
  // saving, not building.
  final ledger = townLedger(state, content);
  final taxes = ledger.taxes;
  final upkeep = ledger.upkeep;
  final available = state.coins + taxes;
  final paid = upkeep > available ? available : upkeep;
  final shortfall = upkeep - paid;

  // Every in-flight project advances one stage — structures gain a
  // stage, roads lay their next planned tile, bridges deliver their
  // next cell (near bank, span, far bank).
  var structures = [...state.structures];
  var roads = [...state.roads];
  var bridges = [...state.bridges];
  var constructions = <WorldConstruction>[];
  var nextEntity = state.nextEntityNumber;
  final completions = <String>[];
  final events = <WorldEvent>[];
  var nextEvent = state.nextEventNumber + 1;
  var advanced = 0;
  for (final job in state.constructions) {
    switch (job.kind) {
      case WorldConstructionKind.structure:
        final definition = content.structure(job.catalogueId!)!;
        final done = job.stagesDone + 1;
        advanced++;
        if (done < definition.constructionStages) {
          constructions.add(_copyConstruction(job, stagesDone: done));
          break;
        }
        structures.add(
          PlacedStructure(
            id: 'structure:${job.id}',
            catalogueId: definition.id,
            kind: definition.kind,
            origin: job.origin!,
            quarterTurns: job.quarterTurns,
            footprint: job.footprint,
            pricePaid: 0,
            completedAtDay: state.constructionDay,
            population: job.population,
            assetRole: job.assetRole,
            facing: job.facing,
          ),
        );
        nextEntity++;
        completions.add(definition.name);
        events.add(
          _event(
            state,
            kind: 'construction-complete',
            description: '${definition.name} is complete',
            payload: {
              'projectId': job.id,
              'catalogueId': definition.id,
              'populationAdded': job.population,
            },
            eventNumber: nextEvent,
          ),
        );
        nextEvent++;
      case WorldConstructionKind.road:
        // Delivery is the road rows themselves: the whole stretch
        // lands on the first check-in after its plan is bought —
        // one day of waiting, whatever the length. Tiles once crept
        // in one per check-in per plan, which let a stack of
        // single-tile plans deliver far faster than one long street:
        // a knowledge gate on the opening that whole-stretch
        // delivery removes.
        advanced++;
        for (final cell in job.roadCells) {
          roads.add(
            RoadSegment(
              id: 'road-${job.id}-${cell.key}',
              cell: cell,
              style: RoadStyle.asphalt,
              pricePaid: content.economy.roadTileCostCoins,
              completedAtDay: state.constructionDay,
              projectId: job.id,
            ),
          );
        }
        roads = [
          for (final road in roads)
            road.projectId == job.id ? _detachProject(road) : road,
        ];
        completions.add('a ${job.roadCells.length}-tile road stretch');
        events.add(
          _event(
            state,
            kind: 'road-project-complete',
            description: 'Road stretch completed',
            payload: {'projectId': job.id, 'cells': job.roadCells.length},
            eventNumber: nextEvent,
          ),
        );
        nextEvent++;
      case WorldConstructionKind.bridge:
        final cells = job.bridgeDeliveryCells;
        final done = job.stagesDone + 1;
        advanced++;
        // Banks land as road tiles as they deliver; the far bank
        // arrives with the completion itself.
        final cell = cells[job.stagesDone];
        if (cell == job.nearBank || cell == job.farBank) {
          roads.add(
            RoadSegment(
              id: 'bridge-approach:${job.id}-${cell.key}',
              cell: cell,
              style: RoadStyle.asphalt,
              pricePaid: content.economy.roadTileCostCoins,
              completedAtDay: state.constructionDay,
              projectId: job.id,
            ),
          );
        }
        if (done >= cells.length) {
          bridges.add(
            CompletedBridge(
              id: 'bridge:${job.id}',
              waterCells: job.waterCells,
              nearBank: job.nearBank!,
              farBank: job.farBank!,
              pricePaid:
                  job.waterCells.length * content.economy.bridgeTileCostCoins +
                  2 * content.economy.roadTileCostCoins,
              completedAtDay: state.constructionDay,
            ),
          );
          roads = [
            for (final road in roads)
              road.projectId == job.id ? _detachProject(road) : road,
          ];
          nextEntity++;
          completions.add('a bridge');
          events.add(
            _event(
              state,
              kind: 'construction-complete',
              description: 'Bridge is open',
              payload: {'projectId': job.id},
              eventNumber: nextEvent,
            ),
          );
          nextEvent++;
        } else {
          constructions.add(_copyConstruction(job, stagesDone: done));
        }
    }
  }

  // Arrivals, staffing, and list growth — counter increments with
  // percentage budgets of population, floored at one. A home
  // completing this very check-in counts as capacity today.
  var population = state.population;
  var employed = state.employedPopulation;
  var waiting = state.waitingPopulation;
  final economy = content.economy;
  var residentialCapacity = 0;
  var jobCapacity = 0;
  for (final structure in structures) {
    final model = content.structure(structure.catalogueId);
    if (model == null) continue;
    if (model.isResidential) {
      residentialCapacity += model.population;
    } else if (model.isCommerce) {
      jobCapacity += model.jobs;
    }
  }
  int budget(int percent) {
    if (percent <= 0) return 0;
    return (population * percent / 100).floor().clamp(1, 1 << 30);
  }

  // Surplus jobs pull: each open position beyond the employed
  // population adds pull jobs to the migration budget — commerce
  // built ahead visibly accelerates migration. The pull only feeds
  // the budget; the waiting list's cap still bounds every burst.
  final surplusJobs = (jobCapacity - employed).clamp(0, 1 << 30);
  final pullJobs = (surplusJobs * economy.jobPullPercentPerCheckIn / 100)
      .floor();
  final migrationBudget = budget(economy.migrationPercentPerCheckIn) + pullJobs;

  // Citizens move in while the waiting list and vacant housing both
  // exist — regardless of unemployment.
  final vacantHousing = residentialCapacity - population;
  final populationArrived =
      (waiting < migrationBudget ? waiting : migrationBudget).clamp(
        0,
        vacantHousing < 0 ? 0 : vacantHousing,
      );
  population += populationArrived;
  waiting -= populationArrived;

  // Positions staff while citizens are unemployed and jobs vacant.
  final employmentBudget = budget(economy.employmentPercentPerCheckIn);
  final unemployed = population - employed;
  final vacantJobs = jobCapacity - employed;
  final positionsStaffed =
      (unemployed < employmentBudget ? unemployed : employmentBudget).clamp(
        0,
        vacantJobs < 0 ? 0 : vacantJobs,
      );
  employed += positionsStaffed;

  // The list refills while unemployment sits within tolerance —
  // a prosperous town attracts, and some joblessness is tolerated
  // the way real frontier towns tolerated it. Vacant homes no
  // longer freeze the list: they drain it, and demand reads as a
  // lower bar instead of a stuck one. Population zero is within
  // tolerance vacuously, kickstarting a fresh town.
  final tolerated = (population * economy.unemploymentTolerancePercent / 100)
      .floor()
      .clamp(1, 1 << 30);
  if (population - employed <= tolerated) {
    final cap = budget(economy.waitingPopulationCapPercent);
    waiting = (waiting + migrationBudget).clamp(0, cap);
  }

  // The population milestone crossing, once, after every population
  // change of the day (completions and arrivals both): the high-water
  // advances to whatever the settlement now reaches — one named
  // event per newly reached milestone. A population dip
  // crosses nothing; the unlock set follows the high-water, never
  // the current population.
  final progression = _advanceProgression(
    state,
    content,
    population,
    nextEvent,
  );

  final report = _event(
    state,
    kind: 'check-in',
    description: 'Daily check-in · town report',
    payload: {
      'creditedDate': state.dateKey,
      'taxes': taxes,
      'upkeep': upkeep,
      'upkeepPaid': paid,
      'upkeepShortfall': shortfall,
      'net': taxes - paid,
      'contentment': ledger.contentment,
      // The unemployment that produced today's taxes — the report
      // explains income with it.
      'unemployed': state.unemployment,
      'stagesAdvanced': advanced,
      'completions': completions,
      'populationArrived': populationArrived,
      'positionsStaffed': positionsStaffed,
    },
  );
  return state.copyWith(
    coins: available - paid,
    totalCoinsEarned: state.totalCoinsEarned + taxes,
    totalCoinsSpent: state.totalCoinsSpent + paid,
    lastCheckInDate: state.simulatedDate,
    checkInCount: state.checkInCount + 1,
    waitingPopulation: waiting,
    population: population,
    employedPopulation: employed,
    nextEntityNumber: nextEntity,
    unlockedCatalogueIds: progression.unlockedCatalogueIds,
    progressionMilestoneId: progression.milestoneId,
    progressionMilestonePopulation: progression.milestonePopulation,
    structures: structures,
    roads: roads,
    bridges: bridges,
    constructions: constructions,
    events: [...state.events, report, ...events, ...progression.events],
    nextEventNumber: progression.nextEventNumber,
  );
}

bool canCheckInWorldToday(ParcelWorldState state) =>
    state.dateKey == worldDateKey(state.checkInHighWaterDate) &&
    (state.lastCheckInDate == null ||
        worldDateKey(state.lastCheckInDate!) != state.dateKey);

ParcelWorldState setWorldCalendarDate(ParcelWorldState state, DateTime date) {
  final normalized = DateTime.utc(date.year, date.month, date.day);
  if (normalized == state.simulatedDate) return state;
  final highWaterDate =
      worldDateKey(normalized)
              .compareTo(worldDateKey(state.checkInHighWaterDate)) >
          0
      ? normalized
      : state.checkInHighWaterDate;
  return state.copyWith(
    simulatedDate: normalized,
    checkInHighWaterDate: highWaterDate,
  );
}

/// Buys a neighboring parcel from the town treasury.
/// Claims a parcel. The first purchase of a new game is the founding
/// — free, unbounded by adjacency, needing five or more land cells —
/// and everything after is a normal adjacent purchase at the
/// settlement-scaled price (see [quoteParcelPurchase]).
ParcelWorldState purchaseParcel(
  ParcelWorldState state,
  ContentBundle content,
  TerrainProvider terrainProvider,
  ParcelCoord coord, {
  Set<ParcelCoord> claimedParcels = const {},
}) {
  final quote = quoteParcelPurchase(
    state,
    content,
    terrainProvider,
    coord,
    claimedParcels: claimedParcels,
  );
  _requireWallet(state, quote.price);
  final parcel = OwnedParcel(
    coord: quote.coord,
    pricePaid: quote.price,
    purchasedAtDay: state.constructionDay,
    terrain: quote.cells,
  );
  // Nature materializes with the land: the parcel's terrain rows
  // copy verbatim into the Props table — the same sprites the
  // frontier drew, now the settlement's to clear before building.
  // Purchase is the only ownership path, so this is the one copy.
  // The rows' models do NOT unlock with them: possession is never
  // gated, but placing new ones stays behind their milestone — an
  // exotic grove is a strategic purchase, not a catalogue grant.
  final nature = [
    for (final row in terrainProvider.natureProps)
      if (parcelForCell(row.cell, parcelSize: state.parcelSize) == coord)
        placedPropFromTerrain(row),
  ];
  return state.copyWith(
    coins: state.coins - quote.price,
    totalCoinsSpent: state.totalCoinsSpent + quote.price,
    parcels: [...state.parcels, parcel],
    props: [...state.props, ...nature],
    events: [
      ...state.events,
      _event(
        state,
        kind: 'parcel-purchase',
        description: quote.price == 0
            ? 'Parcel ${coord.key} claimed · the founding parcel, free'
            : 'Parcel ${coord.key} purchased · −${quote.price} coins',
        payload: {
          'parcelX': coord.x,
          'parcelY': coord.y,
          'pricePaid': quote.price,
        },
      ),
    ],
    nextEventNumber: state.nextEventNumber + 1,
  );
}

/// Buys a road stretch plan: the whole price is paid upfront from
/// the treasury, then the whole stretch lands on the next check-in.
/// Delivery is automatic.
ParcelWorldState planRoadStretch(
  ParcelWorldState state,
  ContentBundle content,
  TerrainProvider terrainProvider, {
  required List<CellCoord> cells,
}) {
  final quote = quoteRoadStretch(state, content, terrainProvider, cells: cells);
  _requireWallet(state, quote.price);
  final job = WorldConstruction(
    id: 'construction-${state.nextEntityNumber}',
    kind: WorldConstructionKind.road,
    startedAtDay: state.constructionDay,
    roadStyle: RoadStyle.asphalt,
    roadCells: quote.cells,
  );
  return state.copyWith(
    coins: state.coins - quote.price,
    totalCoinsSpent: state.totalCoinsSpent + quote.price,
    nextEntityNumber: state.nextEntityNumber + 1,
    constructions: [...state.constructions, job],
    events: [
      ...state.events,
      _event(
        state,
        kind: 'road-project-planned',
        description:
            '${cells.length}-tile road plan bought · −${quote.price} coins',
        payload: {
          'projectId': job.id,
          'cells': cells.map((cell) => cell.toJson()).toList(),
          'pricePaid': quote.price,
        },
      ),
    ],
    nextEventNumber: state.nextEventNumber + 1,
  );
}

/// A road whose project has finished: the same segment with no project
/// reference, so the save never stores a link to a deleted project row.
RoadSegment _detachProject(RoadSegment road) => RoadSegment(
  id: road.id,
  cell: road.cell,
  style: road.style,
  pricePaid: road.pricePaid,
  completedAtDay: road.completedAtDay,
);

/// Places a free construction plan that starts work immediately.
/// Decorations complete as an instant coin purchase.
ParcelWorldState startStructureConstruction(
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
  final quote = quoteStructurePlacement(
    state,
    content,
    terrainProvider,
    catalogueId: catalogueId,
    origin: origin,
    quarterTurns: quarterTurns,
    preferredFacing: preferredFacing,
    subtileX: subtileX,
    subtileY: subtileY,
  );
  final definition = content.structure(catalogueId)!;
  // Deterministic variant roll: unique per placement, stable across
  // reloads, and varied without an RNG.
  final chosenRole =
      definition.assetRoles[(state.seed + state.nextEntityNumber) %
          definition.assetRoles.length];
  // Door side: buildings face the adjacent road — the saved cardinal is
  // one of the bordering road sides, and the art follows its street
  // axis (north/south roads the left variant, east/west the right).
  // The player's preview choice wins while roads border both
  // variants. Non-square footprints snapshot the same origin probe
  // the quote turned them by, so door side and lot orientation stay
  // one fact. Decorations with facings roll deterministically like
  // the variant itself, between the two visible facade sides.
  final sprite = content.sprite(chosenRole);
  String? facing;
  if (sprite != null && sprite.hasFacings) {
    if (definition.kind == StructureKind.building) {
      if (definition.footprintColumns != definition.footprintRows) {
        facing = facingForPlacement(WorldQueries(state, terrainProvider), [
          origin,
        ], preferredFacing);
      } else {
        final sides = WorldQueries(
          state,
          terrainProvider,
        ).adjacentRoadSides(quote.footprint);
        facing = facingForRoadSides(sides);
        if (preferredFacing != null &&
            sides.map(facingArtKey).toSet().length > 1 &&
            sides.contains(preferredFacing)) {
          facing = preferredFacing;
        }
      }
    } else {
      facing = (state.seed + state.nextEntityNumber) % 2 == 0
          ? 'south'
          : 'east';
    }
  }
  if (definition.kind == StructureKind.decoration) {
    _requireWallet(state, quote.price);
    final prop = PlacedProp(
      id: 'prop:${origin.key}:$subtileX.$subtileY',
      catalogueId: catalogueId,
      cell: origin,
      subtileX: subtileX,
      subtileY: subtileY,
      pricePaid: quote.price,
      placedAtDay: state.constructionDay,
      assetRole: chosenRole,
      facing: facing,
    );
    return state.copyWith(
      coins: state.coins - quote.price,
      totalCoinsSpent: state.totalCoinsSpent + quote.price,
      nextEntityNumber: state.nextEntityNumber + 1,
      props: [...state.props, prop],
      events: [
        ...state.events,
        _event(
          state,
          kind: 'decoration-purchase',
          description:
              '${definition.name} placed instantly · −${quote.price} coins',
          payload: {
            'catalogueId': catalogueId,
            'cell': origin.toJson(),
            'subtile': [subtileX, subtileY],
            'pricePaid': quote.price,
          },
        ),
      ],
      nextEventNumber: state.nextEventNumber + 1,
    );
  }

  final job = WorldConstruction(
    id: 'construction-${state.nextEntityNumber}',
    kind: WorldConstructionKind.structure,
    catalogueId: catalogueId,
    structureKind: definition.kind,
    origin: origin,
    quarterTurns: quote.quarterTurns,
    footprint: quote.footprint,
    stagesDone: 0,
    startedAtDay: state.constructionDay,
    population: definition.population,
    assetRole: chosenRole,
    facing: facing,
  );
  return state.copyWith(
    coins: state.coins - quote.price,
    totalCoinsSpent: state.totalCoinsSpent + quote.price,
    nextEntityNumber: state.nextEntityNumber + 1,
    constructions: [...state.constructions, job],
    events: [
      ...state.events,
      _event(
        state,
        kind: 'structure-project-planned',
        description:
            '${definition.name} site planned · '
            '${definition.constructionStages} stages of work',
        payload: {
          'projectId': job.id,
          'catalogueId': catalogueId,
          'origin': origin.toJson(),
          'footprint': quote.footprint.map((cell) => cell.toJson()).toList(),
          'planningFeeCoins': quote.price,
          'stages': definition.constructionStages,
          'facing': facing,
        },
      ),
    ],
    nextEventNumber: state.nextEventNumber + 1,
  );
}

/// Removes a placed prop: free, no refund, and the tile and
/// subtile become placeable again. Prop removal lives in the
/// Demolish tool only — there is no separate pick-up action.
/// Buildings have their own removal — [demolishStructure] — with
/// the eviction cascade; infrastructure (roads, bridges) stays
/// permanent for now.
ParcelWorldState demolishProp(
  ParcelWorldState state,
  ContentBundle content, {
  required String propId,
}) {
  PlacedProp? target;
  for (final prop in state.props) {
    if (prop.id == propId) {
      target = prop;
      break;
    }
  }
  if (target == null) {
    throw const WorldRuleViolation('That prop is no longer placed.');
  }
  final definition = content.structure(target.catalogueId)!;
  return state.copyWith(
    props: [
      for (final prop in state.props)
        if (prop.id != propId) prop,
    ],
    events: [
      ...state.events,
      _event(
        state,
        kind: 'prop-demolished',
        description: '${definition.name} removed',
        payload: {
          'catalogueId': target.catalogueId,
          'cell': target.cell.toJson(),
          'subtile': [target.subtileX, target.subtileY],
        },
      ),
    ],
    nextEventNumber: state.nextEventNumber + 1,
  );
}

/// Demolishes a completed building: the footprint frees instantly,
/// nothing refunds, and the town absorbs the occupancy loss through
/// the eviction cascade — everyone the remaining beds can house
/// stays (moved into other buildings), the overflow joins the
/// residential demand, and demand beyond the waiting list's cap
/// leaves town for good. Employment re-clamps to the survivors and
/// the remaining jobs; demolition of a staffed workplace unemploys
/// its workers. Milestone unlocks keep their high-water — a dip
/// demotes nothing.
ParcelWorldState demolishStructure(
  ParcelWorldState state,
  ContentBundle content, {
  required String structureId,
}) {
  final quote = quoteStructureDemolition(
    state,
    content,
    structureId: structureId,
  );
  final target = quote.structure;
  var employed = state.employedPopulation;
  if (employed > quote.stayers) employed = quote.stayers;
  if (employed > quote.jobsAfter) employed = quote.jobsAfter;
  return state.copyWith(
    structures: [
      for (final structure in state.structures)
        if (structure.id != structureId) structure,
    ],
    population: quote.stayers,
    waitingPopulation: state.waitingPopulation + quote.joinDemand,
    employedPopulation: employed,
    events: [
      ...state.events,
      _event(
        state,
        kind: 'structure-demolished',
        description: '${quote.model.name} demolished',
        payload: {
          'catalogueId': target.catalogueId,
          'origin': target.origin.toJson(),
          'evicted': quote.evicted,
          'leftTown': quote.leftTown,
          'beds': quote.bedsAfter,
          'jobs': quote.jobsAfter,
        },
      ),
    ],
    nextEventNumber: state.nextEventNumber + 1,
  );
}

/// Flips the planned door side of an unfinished building. Offered only
/// while finished roads touch both screen halves of the footprint — a
/// single-side frontage locks the door toward that side, matching how the
/// placement rule would have chosen it.
ParcelWorldState swapStructureFacing(
  ParcelWorldState state,
  ContentBundle content,
  TerrainProvider terrainProvider, {
  required String projectId,
}) {
  final project = _structureProject(state, projectId);
  final definition = content.structure(project.catalogueId!)!;
  final sprite = content.sprite(
    project.assetRole ?? definition.assetRoles.first,
  );
  if (definition.kind != StructureKind.building ||
      sprite == null ||
      !sprite.hasFacings) {
    throw const WorldRuleViolation('That building has a fixed door side.');
  }
  final sides = WorldQueries(
    state,
    terrainProvider,
  ).adjacentRoadSides(project.footprint);
  if (sides.map(facingArtKey).toSet().length < 2) {
    throw const WorldRuleViolation(
      'The road touches only one side, so the door side is fixed.',
    );
  }
  // A null facing (saves predating the snapshot) reads as the planning
  // default variant, so the flip still lands on a real side.
  final flipped = flipFacing(project.facing ?? 'east', sides);
  var swapped = _copyConstruction(project, facing: flipped);
  if (definition.footprintColumns != definition.footprintRows) {
    // A turned lot follows its door side, so the flip may transpose
    // the footprint: re-derive the cells and re-check the room — the
    // site keeps its own current cells, everything else must be free
    // and roaded along a whole edge.
    final turns = footprintTurnsFor(definition, flipped);
    final footprint = structureFootprint(
      definition,
      project.origin!,
      quarterTurns: turns,
    );
    final queries = WorldQueries(state, terrainProvider);
    final ownCells = project.footprint.toSet();
    if (footprint.any(
          (cell) =>
              !ownCells.contains(cell) &&
              (!queries.ownsCell(cell) ||
                  !queries.terrainAt(cell).isLand ||
                  !queries.footprintIsVacant([cell])),
        ) ||
        !queries.buildingHasRoadAccess(footprint)) {
      throw const WorldRuleViolation(
        'There is no room to turn that building onto the other road.',
      );
    }
    swapped = _copyConstruction(
      project,
      facing: flipped,
      quarterTurns: turns,
      footprint: footprint,
    );
  }
  return state.copyWith(
    constructions: state.constructions
        .map((job) => job.id == project.id ? swapped : job)
        .toList(),
    events: [
      ...state.events,
      _event(
        state,
        kind: 'facing-swapped',
        description: '${definition.name} will face the road on the $flipped',
        payload: {'projectId': project.id, 'facing': flipped},
      ),
    ],
    nextEventNumber: state.nextEventNumber + 1,
  );
}

/// Load-time reconciliation: advances the progression high-water to
/// whatever the save's population already reaches under the *current*
/// content (thresholds lowered in the editor, saves from older
/// rules) and re-derives the placement-unlock set through it —
/// never shrinking anything. A no-op (same instance) for
/// already-consistent saves.
ParcelWorldState reconcileWorldProgression(
  ParcelWorldState state,
  ContentBundle content,
) {
  final pass = _advanceProgression(
    state,
    content,
    state.population,
    state.nextEventNumber,
  );
  final settled =
      pass.events.isEmpty &&
      pass.unlockedCatalogueIds.length == state.unlockedCatalogueIds.length &&
      pass.unlockedCatalogueIds.containsAll(state.unlockedCatalogueIds) &&
      pass.milestoneId == state.progressionMilestoneId &&
      pass.milestonePopulation == state.progressionMilestonePopulation;
  if (settled) return state;
  return state.copyWith(
    unlockedCatalogueIds: pass.unlockedCatalogueIds,
    progressionMilestoneId: pass.milestoneId,
    progressionMilestonePopulation: pass.milestonePopulation,
    events: [...state.events, ...pass.events],
    nextEventNumber: pass.nextEventNumber,
  );
}

/// What a progression pass changed: the placement-unlock set, the
/// high-water milestone, and the events it earned.
class _ProgressionPass {
  const _ProgressionPass({
    required this.unlockedCatalogueIds,
    required this.milestoneId,
    required this.milestonePopulation,
    required this.events,
    required this.nextEventNumber,
  });

  final Set<String> unlockedCatalogueIds;
  final String? milestoneId;
  final int milestonePopulation;
  final List<WorldEvent> events;
  final int nextEventNumber;
}

/// Advances the progression high-water to whatever [population]
/// reaches and extends the placement-unlock set with everything
/// through it (newly crossed milestones and models newly added to
/// already-reached ones alike). Monotonic by construction: a
/// population dip crosses nothing, and the set only ever grows, so
/// unlocks cannot re-lock. Each newly reached milestone reports as
/// one named event.
_ProgressionPass _advanceProgression(
  ParcelWorldState state,
  ContentBundle content,
  int population,
  int nextEvent,
) {
  final order = content.progression.sorted;
  // Where the high-water sits now: the stored milestone if it still
  // exists in content, else the furthest milestone the shadow
  // threshold covers (deleted-milestone fallback).
  var reachedIndex = -1;
  final stored = state.progressionMilestoneId == null
      ? null
      : content.progression.byId(state.progressionMilestoneId!);
  if (stored != null) {
    reachedIndex = order.indexOf(stored);
  } else {
    for (var index = 0; index < order.length; index++) {
      if (state.progressionMilestonePopulation >= order[index].population) {
        reachedIndex = index;
      }
    }
  }
  // Cross every milestone the population reaches beyond the
  // high-water — never backward.
  var furthest = reachedIndex;
  for (var index = reachedIndex + 1; index < order.length; index++) {
    if (population < order[index].population) break;
    furthest = index;
  }
  final reached = furthest < 0 ? null : order[furthest];
  final events = <WorldEvent>[];
  for (var index = reachedIndex + 1; index <= furthest; index++) {
    final milestone = order[index];
    final newlyUnlocked = [
      for (final model in milestone.models)
        if (!state.unlockedCatalogueIds.contains(model)) model,
    ];
    events.add(
      _event(
        state,
        kind: 'milestone-reached',
        description: newlyUnlocked.isEmpty
            ? '${milestone.name} reached'
            : '${milestone.name} reached · '
                  '${newlyUnlocked.length} new model(s) placeable',
        payload: {
          'milestoneId': milestone.id,
          'milestoneName': milestone.name,
          'population': milestone.population,
          'models': milestone.models,
          'newlyUnlocked': newlyUnlocked,
        },
        eventNumber: nextEvent,
      ),
    );
    nextEvent++;
  }
  return _ProgressionPass(
    // Union, never replacement: unlocks only ever grow. The
    // high-water decides what joins; nothing already granted leaves.
    unlockedCatalogueIds: reached == null
        ? {...state.unlockedCatalogueIds}
        : {
            ...state.unlockedCatalogueIds,
            ...content.progression.modelsUnlockedThrough(reached),
          },
    milestoneId: reached?.id ?? state.progressionMilestoneId,
    milestonePopulation:
        reached?.population ?? state.progressionMilestonePopulation,
    events: events,
    nextEventNumber: nextEvent,
  );
}

/// Buys a bridge plan: the whole crossing is paid upfront from the
/// treasury, then the deck creeps one tile per check-in — near bank,
/// span tiles, far bank. The span may cross water and land alike;
/// everything under it must already be owned — bridges acquire
/// nothing.
ParcelWorldState startBridgeConstruction(
  ParcelWorldState state,
  ContentBundle content,
  TerrainProvider terrainProvider, {
  required CellCoord nearBank,
  required CellCoord farBank,
}) {
  final quote = quoteBridge(
    state,
    content,
    terrainProvider,
    nearBank: nearBank,
    farBank: farBank,
  );
  _requireWallet(state, quote.bridgeCost);
  final job = WorldConstruction(
    id: 'construction-${state.nextEntityNumber}',
    kind: WorldConstructionKind.bridge,
    nearBank: nearBank,
    farBank: farBank,
    waterCells: quote.spanCells,
    startedAtDay: state.constructionDay,
  );
  return state.copyWith(
    coins: state.coins - quote.bridgeCost,
    totalCoinsSpent: state.totalCoinsSpent + quote.bridgeCost,
    nextEntityNumber: state.nextEntityNumber + 1,
    constructions: [...state.constructions, job],
    events: [
      ...state.events,
      _event(
        state,
        kind: 'bridge-project-planned',
        description:
            'Bridge plan bought · −${quote.bridgeCost} coins · '
            'the deck builds one tile per check-in',
        payload: {
          'projectId': job.id,
          'nearBank': nearBank.toJson(),
          'farBank': farBank.toJson(),
          'spanCells': quote.spanCells.map((cell) => cell.toJson()).toList(),
          'pricePaid': quote.bridgeCost,
        },
      ),
    ],
    nextEventNumber: state.nextEventNumber + 1,
  );
}

/// Simulated day advancement only moves the world/calendar clocks. It never
/// funds or completes a project; construction only advances through coins.
ParcelWorldState advanceWorldDays(ParcelWorldState state, int days) {
  if (days < 0) {
    throw const WorldRuleViolation(
      'Advance the calendar forward by whole days.',
    );
  }
  if (days == 0) return state;
  final targetDate = state.simulatedDate.add(Duration(days: days));
  final highWaterDate =
      worldDateKey(targetDate)
              .compareTo(worldDateKey(state.checkInHighWaterDate)) >
          0
      ? DateTime.utc(targetDate.year, targetDate.month, targetDate.day)
      : state.checkInHighWaterDate;
  return state.copyWith(
    simulatedDate: DateTime.utc(
      targetDate.year,
      targetDate.month,
      targetDate.day,
    ),
    checkInHighWaterDate: highWaterDate,
    constructionDay: state.constructionDay + days,
  );
}

ParcelWorldState grantWorldDebugCoins(ParcelWorldState state, int amount) {
  if (amount <= 0) {
    throw const WorldRuleViolation('A debug grant must be a positive amount.');
  }
  return state.copyWith(
    coins: state.coins + amount,
    totalCoinsEarned: state.totalCoinsEarned + amount,
    events: [
      ...state.events,
      _event(
        state,
        kind: 'debug-grant',
        description: 'Test-only coin grant · +$amount coins',
        payload: {'amount': amount, 'testOnly': true},
      ),
    ],
    nextEventNumber: state.nextEventNumber + 1,
  );
}

WorldConstruction _project(ParcelWorldState state, String id) {
  for (final job in state.constructions) {
    if (job.id == id) return job;
  }
  throw const WorldRuleViolation(
    'That construction project is no longer active.',
  );
}

WorldConstruction _structureProject(ParcelWorldState state, String id) {
  final job = _project(state, id);
  if (job.kind != WorldConstructionKind.structure) {
    throw const WorldRuleViolation('That is not a building project.');
  }
  return job;
}

WorldConstruction _copyConstruction(
  WorldConstruction job, {
  int? stagesDone,
  String? facing,
  int? quarterTurns,
  List<CellCoord>? footprint,
}) => WorldConstruction(
  id: job.id,
  kind: job.kind,
  catalogueId: job.catalogueId,
  structureKind: job.structureKind,
  origin: job.origin,
  quarterTurns: quarterTurns ?? job.quarterTurns,
  footprint: footprint ?? job.footprint,
  roadStyle: job.roadStyle,
  roadCells: job.roadCells,
  waterCells: job.waterCells,
  nearBank: job.nearBank,
  farBank: job.farBank,
  stagesDone: stagesDone ?? job.stagesDone,
  startedAtDay: job.startedAtDay,
  population: job.population,
  assetRole: job.assetRole,
  facing: facing ?? job.facing,
);

WorldEvent _event(
  ParcelWorldState state, {
  required String kind,
  required String description,
  String? dateKey,
  Map<String, Object?> payload = const {},
  int? eventNumber,
}) => WorldEvent(
  id: 'event-${eventNumber ?? state.nextEventNumber}',
  kind: kind,
  dateKey: dateKey ?? state.dateKey,
  constructionDay: state.constructionDay,
  description: description,
  payload: payload,
);

void _requireWallet(ParcelWorldState state, int price) {
  if (price < 0) throw const WorldRuleViolation('Invalid purchase price.');
  if (state.coins < price) {
    throw WorldRuleViolation('You need $price coins for this purchase.');
  }
}

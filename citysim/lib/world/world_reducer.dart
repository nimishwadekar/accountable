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
  var unlocked = {...state.unlockedCatalogueIds};
  var capacity = state.builderCapacity;
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
        // Population gates: unlock models whose threshold the
        // settlement now reaches, then reconcile builder capacity
        // with the progression table.
        final population = structures.fold<int>(
          0,
          (sum, structure) => sum + structure.population,
        );
        for (final candidate in content.purchaseableModels) {
          if (population >= candidate.unlockAtPopulation &&
              unlocked.add(candidate.id)) {
            events.add(
              _event(
                state,
                kind: 'model-unlocked',
                description: '${candidate.name} model unlocked',
                payload: {
                  'catalogueId': candidate.id,
                  'population': population,
                },
                eventNumber: nextEvent,
              ),
            );
            nextEvent++;
          }
        }
        final expectedCapacity = content.economy.builderCapacityForPopulation(
          population,
        );
        if (expectedCapacity > capacity) {
          capacity = expectedCapacity;
          events.add(
            _event(
              state,
              kind: 'builder-granted',
              description: 'Builder capacity grew to $capacity',
              payload: {'capacity': capacity, 'population': population},
              eventNumber: nextEvent,
            ),
          );
          nextEvent++;
        }
      case WorldConstructionKind.road:
        // Delivery is the road rows themselves: the next planned
        // tile without a row is the one this check-in lays.
        final delivered = roads
            .where((road) => road.projectId == job.id)
            .length;
        advanced++;
        if (delivered >= job.roadCells.length) {
          constructions.add(job);
          break;
        }
        final cell = job.roadCells[delivered];
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
        if (delivered + 1 == job.roadCells.length) {
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
        } else {
          // Unfinished: the plan stays in flight — its delivery is
          // the road rows, so the job itself carries over unchanged.
          constructions.add(job);
        }
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
      'stagesAdvanced': advanced,
      'completions': completions,
    },
  );
  return state.copyWith(
    coins: available - paid,
    totalCoinsEarned: state.totalCoinsEarned + taxes,
    totalCoinsSpent: state.totalCoinsSpent + paid,
    lastCheckInDate: state.simulatedDate,
    checkInCount: state.checkInCount + 1,
    nextEntityNumber: nextEntity,
    unlockedCatalogueIds: unlocked,
    builderCapacity: capacity,
    structures: structures,
    roads: roads,
    bridges: bridges,
    constructions: constructions,
    events: [...state.events, report, ...events],
    nextEventNumber: nextEvent,
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
ParcelWorldState purchaseAdjacentParcel(
  ParcelWorldState state,
  ContentBundle content,
  TerrainProvider terrainProvider,
  ParcelCoord coord,
) {
  final quote = quoteParcelPurchase(state, content, terrainProvider, coord);
  _requireWallet(state, quote.price);
  final parcel = OwnedParcel(
    coord: quote.coord,
    pricePaid: quote.price,
    purchasedAtDay: state.constructionDay,
    terrain: quote.cells,
  );
  return state.copyWith(
    coins: state.coins - quote.price,
    totalCoinsSpent: state.totalCoinsSpent + quote.price,
    parcels: [...state.parcels, parcel],
    events: [
      ...state.events,
      _event(
        state,
        kind: 'parcel-purchase',
        description: 'Parcel ${coord.key} purchased · −${quote.price} coins',
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
/// the treasury, then the tiles creep in one per check-in. No
/// builder is assigned — road creep is automatic.
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

/// Places a free construction plan and assigns a builder immediately.
/// Decorations bypass builders and complete as an instant coin purchase.
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

  final builderSlot = quote.builderSlot!;
  final job = WorldConstruction(
    id: 'construction-${state.nextEntityNumber}',
    kind: WorldConstructionKind.structure,
    catalogueId: catalogueId,
    structureKind: definition.kind,
    origin: origin,
    quarterTurns: quote.quarterTurns,
    footprint: quote.footprint,
    stagesDone: 0,
    builderSlot: builderSlot,
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
          'builderSlot': builderSlot,
          'facing': facing,
        },
      ),
    ],
    nextEventNumber: state.nextEventNumber + 1,
  );
}

/// Picks a placed prop back up: free, no refund, and the tile and
/// subtile become placeable again. Buildings keep the permanence
/// rule — this is the game's one removal action, scoped to
/// decorations.
ParcelWorldState pickUpProp(
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
        kind: 'prop-picked-up',
        description: '${definition.name} picked up',
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

/// Load-time reconciliation: grants any population-gated model unlocks and
/// builder-capacity steps an existing save already qualifies for under the
/// *current* content — for example after thresholds were lowered in the
/// editor. Only ever moves upward, records each grant as an event exactly
/// once, and is a no-op for already-consistent saves.
ParcelWorldState reconcileWorldProgression(
  ParcelWorldState state,
  ContentBundle content,
) {
  var unlocked = {...state.unlockedCatalogueIds};
  var capacity = state.builderCapacity;
  final population = state.population;
  final events = <WorldEvent>[];
  var nextEvent = state.nextEventNumber;
  for (final candidate in content.purchaseableModels) {
    if (population >= candidate.unlockAtPopulation &&
        unlocked.add(candidate.id)) {
      events.add(
        _event(
          state,
          kind: 'model-unlocked',
          description: '${candidate.name} model unlocked',
          payload: {
            'catalogueId': candidate.id,
            'population': population,
            'reconciled': true,
          },
          eventNumber: nextEvent,
        ),
      );
      nextEvent++;
    }
  }
  final expectedCapacity = content.economy.builderCapacityForPopulation(
    population,
  );
  if (expectedCapacity > capacity) {
    capacity = expectedCapacity;
    events.add(
      _event(
        state,
        kind: 'builder-granted',
        description: 'Builder capacity grew to $capacity',
        payload: {
          'capacity': capacity,
          'population': population,
          'reconciled': true,
        },
        eventNumber: nextEvent,
      ),
    );
    nextEvent++;
  }
  if (events.isEmpty) return state;
  return state.copyWith(
    unlockedCatalogueIds: unlocked,
    builderCapacity: capacity,
    events: [...state.events, ...events],
    nextEventNumber: nextEvent,
  );
}

/// Buys a bridge plan: the whole crossing is paid upfront from the
/// treasury, then the deck creeps one tile per check-in — near bank,
/// span tiles, far bank. The span may cross water and land alike;
/// everything under it must already be owned — bridges acquire
/// nothing. No builder is assigned.
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
  builderSlot: job.builderSlot,
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

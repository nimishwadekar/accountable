import 'coordinates.dart';
import 'terrain_provider.dart';
import 'world_queries.dart';
import 'world_rules.dart';
import 'world_state.dart';

import '../content/content_bundle.dart';

ParcelWorldState checkInWorldForToday(ParcelWorldState state) {
  if (!canCheckInWorldToday(state)) return state;
  return state.copyWith(
    coins: state.coins + 1,
    totalCoinsEarned: state.totalCoinsEarned + 1,
    lastCheckInDate: state.simulatedDate,
    checkInCount: state.checkInCount + 1,
    events: [
      ...state.events,
      _event(
        state,
        kind: 'check-in',
        description: 'Daily check-in · +1 coin',
        payload: {'creditedDate': state.dateKey, 'coins': 1},
      ),
    ],
    nextEventNumber: state.nextEventNumber + 1,
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

ParcelWorldState planRoadStretch(
  ParcelWorldState state,
  ContentBundle content,
  TerrainProvider terrainProvider, {
  required List<CellCoord> cells,
  required RoadStyle style,
}) {
  final quote = quoteRoadStretch(
    state,
    content,
    terrainProvider,
    cells: cells,
    style: style,
  );
  final job = WorldConstruction(
    id: 'construction-${state.nextEntityNumber}',
    kind: WorldConstructionKind.road,
    totalCostCoins: quote.totalCost,
    coinsFunded: 0,
    builderSlot: quote.builderSlot,
    startedAtDay: state.constructionDay,
    roadStyle: style,
    roadCells: quote.cells,
  );
  return state.copyWith(
    nextEntityNumber: state.nextEntityNumber + 1,
    constructions: [...state.constructions, job],
    events: [
      ...state.events,
      _event(
        state,
        kind: 'road-project-planned',
        description:
            '${cells.length}-tile ${style.name} road planned · '
            '${quote.totalCost} coins to fund',
        payload: {
          'projectId': job.id,
          'style': style.name,
          'cells': cells.map((cell) => cell.toJson()).toList(),
          'totalCostCoins': quote.totalCost,
          'builderSlot': quote.builderSlot,
        },
      ),
    ],
    nextEventNumber: state.nextEventNumber + 1,
  );
}

ParcelWorldState fundRoadTile(
  ParcelWorldState state,
  ContentBundle content,
  TerrainProvider terrainProvider, {
  required String projectId,
  required CellCoord cell,
}) {
  final quote = quoteRoadTileFunding(
    state,
    content,
    terrainProvider: terrainProvider,
    projectId: projectId,
    cell: cell,
  );
  _requireWallet(state, quote.price);
  final project = _roadProject(state, projectId);
  final road = RoadSegment(
    id: 'road-${project.id}-${cell.key}',
    cell: cell,
    style: project.roadStyle!,
    pricePaid: quote.price,
    completedAtDay: state.constructionDay,
    projectId: project.id,
  );
  final roads = [...state.roads, road];
  final funded = project.coinsFunded + quote.price;
  final completed = project.roadCells.every(
    (plannedCell) => roads.any((entry) => entry.cell == plannedCell),
  );
  final events = [
    ...state.events,
    _event(
      state,
      kind: 'road-tile-funded',
      description:
          'Road tile ${cell.key} completed · $funded/${project.totalCostCoins} coins',
      payload: {
        'projectId': project.id,
        'cell': cell.toJson(),
        'pricePaid': quote.price,
        'fundedCoins': funded,
        'totalCostCoins': project.totalCostCoins,
      },
    ),
  ];
  var nextEvent = state.nextEventNumber + 1;
  if (completed) {
    events.add(
      _event(
        state,
        kind: 'road-project-complete',
        description: 'Road stretch completed',
        payload: {'projectId': project.id, 'cells': project.roadCells.length},
        eventNumber: nextEvent,
      ),
    );
    nextEvent++;
  }
  return state.copyWith(
    coins: state.coins - quote.price,
    totalCoinsSpent: state.totalCoinsSpent + quote.price,
    roads: roads,
    constructions: completed
        ? state.constructions.where((job) => job.id != project.id).toList()
        : state.constructions
              .map(
                (job) =>
                    job.id == project.id ? _withFundedCoins(job, funded) : job,
              )
              .toList(),
    events: events,
    nextEventNumber: nextEvent,
  );
}

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
}) {
  final quote = quoteStructurePlacement(
    state,
    content,
    terrainProvider,
    catalogueId: catalogueId,
    origin: origin,
    quarterTurns: quarterTurns,
  );
  final definition = content.structure(catalogueId)!;
  // Deterministic variant roll: unique per placement, stable across
  // reloads, and varied without an RNG.
  final chosenRole =
      definition.assetRoles[(state.seed + state.nextEntityNumber) %
          definition.assetRoles.length];
  // Door side: buildings face the adjacent road (any frontage on the
  // footprint's screen-right half faces right, the left half faces left,
  // and both halves honour the player's preview choice). Decorations
  // with facings roll deterministically like the variant itself.
  final sprite = content.sprite(chosenRole);
  String? facing;
  if (sprite != null && sprite.hasFacings) {
    if (definition.kind == StructureKind.building) {
      final sides = WorldQueries(
        state,
        terrainProvider,
      ).adjacentDoorSides(quote.footprint);
      facing = sides.length < 2
          ? doorFacingForSides(sides)
          : (preferredFacing == 'left' || preferredFacing == 'right'
                ? preferredFacing
                : 'right');
    } else {
      facing = (state.seed + state.nextEntityNumber) % 2 == 0
          ? 'left'
          : 'right';
    }
  }
  if (definition.kind == StructureKind.decoration) {
    _requireWallet(state, quote.price);
    final decor = PlacedStructure(
      id: 'structure-${state.nextEntityNumber}',
      catalogueId: catalogueId,
      kind: definition.kind,
      origin: origin,
      quarterTurns: quote.quarterTurns,
      footprint: quote.footprint,
      pricePaid: quote.price,
      completedAtDay: state.constructionDay,
      population: definition.population,
      assetRole: chosenRole,
      facing: facing,
    );
    return state.copyWith(
      coins: state.coins - quote.price,
      totalCoinsSpent: state.totalCoinsSpent + quote.price,
      nextEntityNumber: state.nextEntityNumber + 1,
      structures: [...state.structures, decor],
      events: [
        ...state.events,
        _event(
          state,
          kind: 'decoration-purchase',
          description:
              '${definition.name} placed instantly · −${quote.price} coins',
          payload: {
            'catalogueId': catalogueId,
            'origin': origin.toJson(),
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
    totalCostCoins: quote.price,
    coinsFunded: 0,
    builderSlot: builderSlot,
    startedAtDay: state.constructionDay,
    population: definition.population,
    assetRole: chosenRole,
    facing: facing,
  );
  return state.copyWith(
    nextEntityNumber: state.nextEntityNumber + 1,
    constructions: [...state.constructions, job],
    events: [
      ...state.events,
      _event(
        state,
        kind: 'structure-project-planned',
        description:
            '${definition.name} site planned · ${quote.price} coins to fund',
        payload: {
          'projectId': job.id,
          'catalogueId': catalogueId,
          'origin': origin.toJson(),
          'footprint': quote.footprint.map((cell) => cell.toJson()).toList(),
          'totalCostCoins': quote.price,
          'builderSlot': builderSlot,
          'facing': facing,
        },
      ),
    ],
    nextEventNumber: state.nextEventNumber + 1,
  );
}

ParcelWorldState fundStructureProject(
  ParcelWorldState state,
  ContentBundle content, {
  required String projectId,
  required int amount,
}) {
  final quote = quoteStructureFunding(
    state,
    projectId: projectId,
    amount: amount,
  );
  amount = quote.amount;
  _requireWallet(state, amount);
  final project = _structureProject(state, projectId);
  final newFunded = project.coinsFunded + amount;
  final complete = newFunded == project.totalCostCoins;
  final events = [
    ...state.events,
    _event(
      state,
      kind: 'structure-funded',
      description:
          '${content.structure(project.catalogueId!)!.name} funded · '
          '$newFunded/${project.totalCostCoins} coins',
      payload: {
        'projectId': project.id,
        'catalogueId': project.catalogueId!,
        'contribution': amount,
        'fundedCoins': newFunded,
        'totalCostCoins': project.totalCostCoins,
      },
    ),
  ];
  var nextEvent = state.nextEventNumber + 1;
  var structures = [...state.structures];
  var unlocked = {...state.unlockedCatalogueIds};
  var nextEntity = state.nextEntityNumber;
  var capacity = state.builderCapacity;
  if (complete) {
    final definition = content.structure(project.catalogueId!)!;
    structures.add(
      PlacedStructure(
        id: 'structure:${project.id}',
        catalogueId: definition.id,
        kind: definition.kind,
        origin: project.origin!,
        quarterTurns: project.quarterTurns,
        footprint: project.footprint,
        pricePaid: project.totalCostCoins,
        completedAtDay: state.constructionDay,
        population: project.population,
        assetRole: project.assetRole,
        facing: project.facing,
      ),
    );
    nextEntity++;
    events.add(
      _event(
        state,
        kind: 'construction-complete',
        description: '${definition.name} is complete',
        payload: {
          'projectId': project.id,
          'catalogueId': definition.id,
          'populationAdded': project.population,
        },
        eventNumber: nextEvent,
      ),
    );
    nextEvent++;
    // Population gates: unlock models whose threshold the settlement now
    // reaches, then reconcile builder capacity with the progression table.
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
            payload: {'catalogueId': candidate.id, 'population': population},
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
  }
  return state.copyWith(
    coins: state.coins - amount,
    totalCoinsSpent: state.totalCoinsSpent + amount,
    nextEntityNumber: nextEntity,
    unlockedCatalogueIds: unlocked,
    builderCapacity: capacity,
    structures: structures,
    constructions: complete
        ? state.constructions.where((job) => job.id != project.id).toList()
        : state.constructions
              .map(
                (job) => job.id == project.id
                    ? _withFundedCoins(job, newFunded)
                    : job,
              )
              .toList(),
    events: events,
    nextEventNumber: nextEvent,
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
  ).adjacentDoorSides(project.footprint);
  if (sides.length < 2) {
    throw const WorldRuleViolation(
      'The road touches only one side, so the door side is fixed.',
    );
  }
  final flipped = project.facing == 'left' ? 'right' : 'left';
  final swapped = _copyConstruction(project, facing: flipped);
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

/// Buys the quoted bridge corridor immediately, then assigns a builder to the
/// bridge project. Bridge coins themselves are contributed explicitly later.
ParcelWorldState startRiverBridgeConstruction(
  ParcelWorldState state,
  ContentBundle content,
  TerrainProvider terrainProvider, {
  required CellCoord nearBank,
  required CellCoord farBank,
}) {
  final quote = quoteRiverBridge(
    state,
    content,
    terrainProvider,
    nearBank: nearBank,
    farBank: farBank,
  );
  _requireWallet(state, quote.parcelCost);
  final newParcels = quote.parcelsToAcquire
      .map(
        (parcel) => OwnedParcel(
          coord: parcel.coord,
          pricePaid: parcel.price,
          purchasedAtDay: state.constructionDay,
          terrain: parcel.cells,
        ),
      )
      .toList();
  final job = WorldConstruction(
    id: 'construction-${state.nextEntityNumber}',
    kind: WorldConstructionKind.bridge,
    nearBank: nearBank,
    farBank: farBank,
    waterCells: quote.waterCells,
    totalCostCoins: quote.bridgeCost,
    coinsFunded: 0,
    builderSlot: quote.builderSlot,
    startedAtDay: state.constructionDay,
  );
  final parcelNames = quote.parcelsToAcquire.map((parcel) => parcel.coord.key);
  final detail = parcelNames.isEmpty
      ? ''
      : ' including crossing parcels ${parcelNames.join(', ')}';
  return state.copyWith(
    coins: state.coins - quote.parcelCost,
    totalCoinsSpent: state.totalCoinsSpent + quote.parcelCost,
    nextEntityNumber: state.nextEntityNumber + 1,
    parcels: [...state.parcels, ...newParcels],
    constructions: [...state.constructions, job],
    events: [
      ...state.events,
      _event(
        state,
        kind: 'bridge-project-planned',
        description:
            'River bridge planned · ${quote.bridgeCost} coins to fund$detail',
        payload: {
          'projectId': job.id,
          'nearBank': nearBank.toJson(),
          'farBank': farBank.toJson(),
          'waterCells': quote.waterCells.map((cell) => cell.toJson()).toList(),
          'parcelCoordinates': quote.parcelsToAcquire
              .map((parcel) => parcel.coord.toJson())
              .toList(),
          'bridgeCostCoins': quote.bridgeCost,
          'parcelCostCoins': quote.parcelCost,
          'builderSlot': quote.builderSlot,
        },
      ),
    ],
    nextEventNumber: state.nextEventNumber + 1,
  );
}

ParcelWorldState fundBridgeProject(
  ParcelWorldState state, {
  required String projectId,
  required int amount,
}) {
  final project = _bridgeProject(state, projectId);
  if (amount <= 0 || amount > state.coins || amount > project.coinsRemaining) {
    throw const WorldRuleViolation(
      'Choose a positive contribution no larger than your wallet or remaining bridge cost.',
    );
  }
  final newFunded = project.coinsFunded + amount;
  final complete = newFunded == project.totalCostCoins;
  final events = [
    ...state.events,
    _event(
      state,
      kind: 'bridge-funded',
      description: 'Bridge funded · $newFunded/${project.totalCostCoins} coins',
      payload: {
        'projectId': project.id,
        'contribution': amount,
        'fundedCoins': newFunded,
        'totalCostCoins': project.totalCostCoins,
      },
    ),
  ];
  var nextEvent = state.nextEventNumber + 1;
  var bridges = [...state.bridges];
  var roads = [...state.roads];
  var nextEntity = state.nextEntityNumber;
  if (complete) {
    bridges.add(
      CompletedBridge(
        id: 'bridge:${project.id}',
        waterCells: project.waterCells,
        nearBank: project.nearBank!,
        farBank: project.farBank!,
        pricePaid: project.totalCostCoins,
        completedAtDay: state.constructionDay,
      ),
    );
    roads.add(
      RoadSegment(
        id: 'bridge-approach:${project.id}',
        cell: project.farBank!,
        style: RoadStyle.asphalt,
        pricePaid: 0,
        completedAtDay: state.constructionDay,
      ),
    );
    nextEntity++;
    events.add(
      _event(
        state,
        kind: 'construction-complete',
        description: 'River bridge is open',
        payload: {'projectId': project.id},
        eventNumber: nextEvent,
      ),
    );
    nextEvent++;
  }
  return state.copyWith(
    coins: state.coins - amount,
    totalCoinsSpent: state.totalCoinsSpent + amount,
    nextEntityNumber: nextEntity,
    bridges: bridges,
    roads: roads,
    constructions: complete
        ? state.constructions.where((job) => job.id != project.id).toList()
        : state.constructions
              .map(
                (job) => job.id == project.id
                    ? _withFundedCoins(job, newFunded)
                    : job,
              )
              .toList(),
    events: events,
    nextEventNumber: nextEvent,
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

WorldConstruction _roadProject(ParcelWorldState state, String id) {
  final job = _project(state, id);
  if (job.kind != WorldConstructionKind.road) {
    throw const WorldRuleViolation('That is not a road project.');
  }
  return job;
}

WorldConstruction _structureProject(ParcelWorldState state, String id) {
  final job = _project(state, id);
  if (job.kind != WorldConstructionKind.structure) {
    throw const WorldRuleViolation('That is not a building project.');
  }
  return job;
}

WorldConstruction _bridgeProject(ParcelWorldState state, String id) {
  final job = _project(state, id);
  if (job.kind != WorldConstructionKind.bridge) {
    throw const WorldRuleViolation('That is not a bridge project.');
  }
  return job;
}

WorldConstruction _withFundedCoins(WorldConstruction job, int amount) =>
    _copyConstruction(job, coinsFunded: amount);

WorldConstruction _copyConstruction(
  WorldConstruction job, {
  int? coinsFunded,
  String? facing,
}) => WorldConstruction(
  id: job.id,
  kind: job.kind,
  catalogueId: job.catalogueId,
  structureKind: job.structureKind,
  origin: job.origin,
  quarterTurns: job.quarterTurns,
  footprint: job.footprint,
  roadStyle: job.roadStyle,
  roadCells: job.roadCells,
  waterCells: job.waterCells,
  nearBank: job.nearBank,
  farBank: job.farBank,
  totalCostCoins: job.totalCostCoins,
  coinsFunded: coinsFunded ?? job.coinsFunded,
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

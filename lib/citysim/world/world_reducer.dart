import 'coordinates.dart';
import 'terrain_provider.dart';
import 'world_content.dart';
import 'world_rules.dart';
import 'world_state.dart';

ParcelWorldState checkInWorldForToday(ParcelWorldState state) {
  if (!canCheckInWorldToday(state)) return state;
  return state.copyWith(
    coins: state.coins + 1,
    totalCoinsEarned: state.totalCoinsEarned + 1,
    creditedDates: {...state.creditedDates, state.dateKey},
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
    !state.creditedDates.contains(state.dateKey);

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
  TerrainProvider terrainProvider,
  ParcelCoord coord,
) {
  final quote = quoteParcelPurchase(state, terrainProvider, coord);
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
  TerrainProvider terrainProvider, {
  required List<CellCoord> cells,
  required RoadStyle style,
}) {
  final quote = quoteRoadStretch(
    state,
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
  TerrainProvider terrainProvider, {
  required String projectId,
  required CellCoord cell,
}) {
  final quote = quoteRoadTileFunding(
    state,
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
  TerrainProvider terrainProvider, {
  required String catalogueId,
  required CellCoord origin,
  int quarterTurns = 0,
}) {
  final quote = quoteStructurePlacement(
    state,
    terrainProvider,
    catalogueId: catalogueId,
    origin: origin,
    quarterTurns: quarterTurns,
  );
  final definition = structureById[catalogueId]!;
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
        },
      ),
    ],
    nextEventNumber: state.nextEventNumber + 1,
  );
}

ParcelWorldState fundStructureProject(
  ParcelWorldState state, {
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
          '${structureById[project.catalogueId]!.name} funded · '
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
  if (complete) {
    final definition = structureById[project.catalogueId]!;
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
      ),
    );
    nextEntity++;
    events.add(
      _event(
        state,
        kind: 'construction-complete',
        description: '${definition.name} is complete',
        payload: {'projectId': project.id, 'catalogueId': definition.id},
        eventNumber: nextEvent,
      ),
    );
    nextEvent++;
    final buildingCount = structures
        .where((structure) => structure.kind == StructureKind.building)
        .length;
    for (final candidate in structureCatalogue) {
      if (buildingCount >= candidate.milestoneBuildings &&
          unlocked.add(candidate.id)) {
        events.add(
          _event(
            state,
            kind: 'model-unlocked',
            description: '${candidate.name} model unlocked',
            payload: {
              'catalogueId': candidate.id,
              'completedBuildings': buildingCount,
            },
            eventNumber: nextEvent,
          ),
        );
        nextEvent++;
      }
    }
  }
  return state.copyWith(
    coins: state.coins - amount,
    totalCoinsSpent: state.totalCoinsSpent + amount,
    nextEntityNumber: nextEntity,
    unlockedCatalogueIds: unlocked,
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

/// Buys the quoted bridge corridor immediately, then assigns a builder to the
/// bridge project. Bridge coins themselves are contributed explicitly later.
ParcelWorldState startRiverBridgeConstruction(
  ParcelWorldState state,
  TerrainProvider terrainProvider, {
  required CellCoord nearBank,
  required CellCoord farBank,
}) {
  final quote = quoteRiverBridge(
    state,
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
    WorldConstruction(
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
      coinsFunded: amount,
      builderSlot: job.builderSlot,
      startedAtDay: job.startedAtDay,
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

import 'coordinates.dart';
import 'terrain_provider.dart';

import '../content/content_bundle.dart';
import 'world_content.dart';

const parcelWorldSchemaVersion = 4;
const parcelWorldGeneratorVersion = 1;
const parcelWorldRulesVersion = 2;
const parcelWorldContentVersion = 3;

class OwnedParcel {
  OwnedParcel({
    required this.coord,
    required this.pricePaid,
    required this.purchasedAtDay,
    required List<TerrainCell> terrain,
  }) : terrain = List.unmodifiable(terrain);

  final ParcelCoord coord;
  final int pricePaid;
  final int purchasedAtDay;
  final List<TerrainCell> terrain;

  Map<String, Object?> toJson() => {
    'coord': coord.toJson(),
    'pricePaid': pricePaid,
    'purchasedAtDay': purchasedAtDay,
    'terrain': terrain.map((cell) => cell.toJson()).toList(),
  };

  factory OwnedParcel.fromJson(Map<String, Object?> json) => OwnedParcel(
    coord: ParcelCoord.fromJson(worldJsonMap(json['coord'])),
    pricePaid: json['pricePaid']! as int,
    purchasedAtDay: json['purchasedAtDay']! as int,
    terrain: (json['terrain']! as List)
        .map((value) => TerrainCell.fromJson(worldJsonMap(value)))
        .toList(),
  );
}

class RoadSegment {
  const RoadSegment({
    required this.id,
    required this.cell,
    required this.style,
    required this.pricePaid,
    required this.completedAtDay,
    this.projectId,
  });

  final String id;
  final CellCoord cell;
  final RoadStyle style;
  final int pricePaid;
  final int completedAtDay;
  final String? projectId;

  Map<String, Object?> toJson() => {
    'id': id,
    'cell': cell.toJson(),
    'style': style.name,
    'pricePaid': pricePaid,
    'completedAtDay': completedAtDay,
    'projectId': projectId,
  };

  factory RoadSegment.fromJson(Map<String, Object?> json) => RoadSegment(
    id: json['id']! as String,
    cell: CellCoord.fromJson(worldJsonMap(json['cell'])),
    style: RoadStyle.values.firstWhere((value) => value.name == json['style']),
    pricePaid: json['pricePaid']! as int,
    completedAtDay: json['completedAtDay']! as int,
    projectId: json['projectId'] as String?,
  );
}

class PlacedStructure {
  PlacedStructure({
    required this.id,
    required this.catalogueId,
    required this.kind,
    required this.origin,
    required this.quarterTurns,
    required List<CellCoord> footprint,
    required this.pricePaid,
    required this.completedAtDay,
    required this.population,
    this.assetRole,
    this.facing,
  }) : footprint = List.unmodifiable(footprint);

  final String id;
  final String catalogueId;
  final StructureKind kind;
  final CellCoord origin;
  final int quarterTurns;
  final List<CellCoord> footprint;
  final int pricePaid;
  final int completedAtDay;

  /// Population contributed by this structure, snapshotted from content at
  /// placement time (like the footprint) so later content edits do not
  /// rewrite history. Defaults by kind for saves predating the field.
  final int population;

  /// Which of the model's sprite variants this structure renders as,
  /// rolled deterministically at placement. Null on saves predating
  /// variants — the model's first role is used.
  final String? assetRole;

  /// Door side snapshotted at plan time from the road-side rule: 'right'
  /// when the adjacent road sits on the footprint's screen-right half
  /// (grid north/east), 'left' for the screen-left half (grid south/west).
  /// Null when the chosen sprite has no facings or for decorations with a
  /// single facing.
  final String? facing;

  Map<String, Object?> toJson() => {
    'id': id,
    'catalogueId': catalogueId,
    'kind': kind.name,
    'origin': origin.toJson(),
    'quarterTurns': quarterTurns,
    'footprint': footprint.map((cell) => cell.toJson()).toList(),
    'pricePaid': pricePaid,
    'completedAtDay': completedAtDay,
    'population': population,
    'assetRole': assetRole,
    'facing': facing,
  };

  factory PlacedStructure.fromJson(Map<String, Object?> json) {
    final kind = StructureKind.values.firstWhere(
      (value) => value.name == json['kind'],
    );
    return PlacedStructure(
      id: json['id']! as String,
      catalogueId: json['catalogueId']! as String,
      kind: kind,
      origin: CellCoord.fromJson(worldJsonMap(json['origin'])),
      quarterTurns: json['quarterTurns']! as int,
      footprint: (json['footprint']! as List)
          .map((value) => CellCoord.fromJson(worldJsonMap(value)))
          .toList(),
      pricePaid: json['pricePaid']! as int,
      completedAtDay: json['completedAtDay']! as int,
      population:
          json['population'] as int? ??
          (kind == StructureKind.building ? 1 : 0),
      assetRole: json['assetRole'] as String?,
      facing: json['facing'] as String?,
    );
  }
}

class CompletedBridge {
  CompletedBridge({
    required this.id,
    required List<CellCoord> waterCells,
    required this.nearBank,
    required this.farBank,
    required this.pricePaid,
    required this.completedAtDay,
  }) : waterCells = List.unmodifiable(waterCells);

  final String id;
  final List<CellCoord> waterCells;
  final CellCoord nearBank;
  final CellCoord farBank;
  final int pricePaid;
  final int completedAtDay;

  Map<String, Object> toJson() => {
    'id': id,
    'waterCells': waterCells.map((cell) => cell.toJson()).toList(),
    'nearBank': nearBank.toJson(),
    'farBank': farBank.toJson(),
    'pricePaid': pricePaid,
    'completedAtDay': completedAtDay,
  };

  factory CompletedBridge.fromJson(Map<String, Object?> json) =>
      CompletedBridge(
        id: json['id']! as String,
        waterCells: (json['waterCells']! as List)
            .map((value) => CellCoord.fromJson(worldJsonMap(value)))
            .toList(),
        nearBank: CellCoord.fromJson(worldJsonMap(json['nearBank'])),
        farBank: CellCoord.fromJson(worldJsonMap(json['farBank'])),
        pricePaid: json['pricePaid']! as int,
        completedAtDay: json['completedAtDay']! as int,
      );
}

enum WorldConstructionKind { structure, road, bridge }

class WorldConstruction {
  WorldConstruction({
    required this.id,
    required this.kind,
    required this.totalCostCoins,
    required this.coinsFunded,
    required this.builderSlot,
    required this.startedAtDay,
    this.catalogueId,
    this.structureKind,
    this.origin,
    this.quarterTurns = 0,
    List<CellCoord> footprint = const [],
    this.roadStyle,
    List<CellCoord> roadCells = const [],
    List<CellCoord> waterCells = const [],
    this.nearBank,
    this.farBank,
    this.population = 0,
    this.assetRole,
    this.facing,
  }) : footprint = List.unmodifiable(footprint),
       roadCells = List.unmodifiable(roadCells),
       waterCells = List.unmodifiable(waterCells);

  final String id;
  final WorldConstructionKind kind;
  final String? catalogueId;
  final StructureKind? structureKind;
  final CellCoord? origin;
  final int quarterTurns;
  final List<CellCoord> footprint;
  final RoadStyle? roadStyle;
  final List<CellCoord> roadCells;
  final List<CellCoord> waterCells;
  final CellCoord? nearBank;
  final CellCoord? farBank;
  final int totalCostCoins;
  final int coinsFunded;
  final int builderSlot;
  final int startedAtDay;

  /// Population the finished building will contribute, snapshotted from
  /// content at plan time alongside the footprint and cost.
  final int population;

  /// Sprite variant rolled at plan time; transferred to the placed
  /// structure on completion. Null for non-structure jobs and saves
  /// predating variants.
  final String? assetRole;

  /// Door side chosen at plan time from the adjacent road; transferred to
  /// the placed structure on completion. Null for sprites without
  /// facings. The player may flip it while the plan is unfinished.
  final String? facing;

  int get coinsRemaining => totalCostCoins - coinsFunded;
  double get progress =>
      totalCostCoins <= 0 ? 1 : (coinsFunded / totalCostCoins).clamp(0.0, 1.0);

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'catalogueId': catalogueId,
    'structureKind': structureKind?.name,
    'origin': origin?.toJson(),
    'quarterTurns': quarterTurns,
    'footprint': footprint.map((cell) => cell.toJson()).toList(),
    'roadStyle': roadStyle?.name,
    'roadCells': roadCells.map((cell) => cell.toJson()).toList(),
    'waterCells': waterCells.map((cell) => cell.toJson()).toList(),
    'nearBank': nearBank?.toJson(),
    'farBank': farBank?.toJson(),
    'totalCostCoins': totalCostCoins,
    'coinsFunded': coinsFunded,
    'builderSlot': builderSlot,
    'startedAtDay': startedAtDay,
    'population': population,
    'assetRole': assetRole,
    'facing': facing,
  };

  factory WorldConstruction.fromJson(Map<String, Object?> json) =>
      WorldConstruction(
        id: json['id']! as String,
        kind: WorldConstructionKind.values.firstWhere(
          (value) => value.name == json['kind'],
        ),
        catalogueId: json['catalogueId'] as String?,
        structureKind: json['structureKind'] == null
            ? null
            : StructureKind.values.firstWhere(
                (value) => value.name == json['structureKind'],
              ),
        origin: json['origin'] == null
            ? null
            : CellCoord.fromJson(worldJsonMap(json['origin'])),
        quarterTurns: json['quarterTurns']! as int,
        footprint: (json['footprint']! as List)
            .map((value) => CellCoord.fromJson(worldJsonMap(value)))
            .toList(),
        roadStyle: json['roadStyle'] == null
            ? null
            : RoadStyle.values.firstWhere(
                (value) => value.name == json['roadStyle'],
              ),
        roadCells: (json['roadCells']! as List)
            .map((value) => CellCoord.fromJson(worldJsonMap(value)))
            .toList(),
        waterCells: (json['waterCells']! as List)
            .map((value) => CellCoord.fromJson(worldJsonMap(value)))
            .toList(),
        nearBank: json['nearBank'] == null
            ? null
            : CellCoord.fromJson(worldJsonMap(json['nearBank'])),
        farBank: json['farBank'] == null
            ? null
            : CellCoord.fromJson(worldJsonMap(json['farBank'])),
        totalCostCoins: json['totalCostCoins']! as int,
        coinsFunded: json['coinsFunded']! as int,
        builderSlot: json['builderSlot']! as int,
        startedAtDay: json['startedAtDay']! as int,
        population: json['population'] as int? ?? 0,
        assetRole: json['assetRole'] as String?,
        facing: json['facing'] as String?,
      );
}

class WorldEvent {
  WorldEvent({
    required this.id,
    required this.kind,
    required this.dateKey,
    required this.constructionDay,
    required this.description,
    Map<String, Object?> payload = const {},
  }) : payload = Map.unmodifiable(payload);

  final String id;
  final String kind;
  final String dateKey;
  final int constructionDay;
  final String description;
  final Map<String, Object?> payload;

  Map<String, Object> toJson() => {
    'id': id,
    'kind': kind,
    'dateKey': dateKey,
    'constructionDay': constructionDay,
    'description': description,
    'payload': payload,
  };

  factory WorldEvent.fromJson(Map<String, Object?> json) => WorldEvent(
    id: json['id']! as String,
    kind: json['kind']! as String,
    dateKey: json['dateKey']! as String,
    constructionDay: json['constructionDay']! as int,
    description: json['description']! as String,
    payload: json['payload'] == null ? const {} : worldJsonMap(json['payload']),
  );
}

class ParcelWorldState {
  ParcelWorldState({
    required this.worldId,
    required this.seed,
    required this.generatorVersion,
    required this.rulesVersion,
    required this.contentVersion,
    required this.parcelSize,
    required this.builderCapacity,
    required this.simulatedDate,
    required this.checkInHighWaterDate,
    required this.constructionDay,
    required this.coins,
    required this.totalCoinsEarned,
    required this.totalCoinsSpent,
    required this.nextEntityNumber,
    required this.nextEventNumber,
    required Set<String> creditedDates,
    required Set<String> unlockedCatalogueIds,
    required List<OwnedParcel> parcels,
    required List<RoadSegment> roads,
    required List<PlacedStructure> structures,
    required List<CompletedBridge> bridges,
    required List<WorldConstruction> constructions,
    required List<WorldEvent> events,
  }) : creditedDates = Set.unmodifiable(creditedDates),
       unlockedCatalogueIds = Set.unmodifiable(unlockedCatalogueIds),
       parcels = List.unmodifiable(parcels),
       roads = List.unmodifiable(roads),
       structures = List.unmodifiable(structures),
       bridges = List.unmodifiable(bridges),
       constructions = List.unmodifiable(constructions),
       events = List.unmodifiable(events);

  final String worldId;
  final int seed;
  final int generatorVersion;
  final int rulesVersion;
  final int contentVersion;
  final int parcelSize;
  final int builderCapacity;
  final DateTime simulatedDate;
  final DateTime checkInHighWaterDate;
  final int constructionDay;
  final int coins;
  final int totalCoinsEarned;
  final int totalCoinsSpent;
  final int nextEntityNumber;
  final int nextEventNumber;
  final Set<String> creditedDates;
  final Set<String> unlockedCatalogueIds;
  final List<OwnedParcel> parcels;
  final List<RoadSegment> roads;
  final List<PlacedStructure> structures;
  final List<CompletedBridge> bridges;
  final List<WorldConstruction> constructions;
  final List<WorldEvent> events;

  String get dateKey => worldDateKey(simulatedDate);
  int get completedBuildingCount => structures
      .where((structure) => structure.kind == StructureKind.building)
      .length;

  /// Derived progression metric: the population of every completed
  /// structure (snapshotted at placement). Never stored.
  int get population =>
      structures.fold<int>(0, (sum, structure) => sum + structure.population);
  int get creditedDayCount => creditedDates.length;

  Map<ParcelCoord, OwnedParcel> get parcelsByCoord => {
    for (final parcel in parcels) parcel.coord: parcel,
  };
  Map<CellCoord, RoadSegment> get roadsByCell => {
    for (final road in roads) road.cell: road,
  };
  Map<CellCoord, PlacedStructure> get structuresByCell => {
    for (final structure in structures)
      for (final cell in structure.footprint) cell: structure,
  };
  Set<CellCoord> get reservedCells => {
    for (final job in constructions) ...job.footprint,
    for (final job in constructions) ...job.roadCells,
    for (final job in constructions) ...job.waterCells,
    for (final job in constructions)
      if (job.nearBank != null) job.nearBank!,
    for (final job in constructions)
      if (job.farBank != null) job.farBank!,
  };

  ParcelWorldState copyWith({
    int? constructionDay,
    int? builderCapacity,
    DateTime? simulatedDate,
    DateTime? checkInHighWaterDate,
    int? coins,
    int? totalCoinsEarned,
    int? totalCoinsSpent,
    int? nextEntityNumber,
    int? nextEventNumber,
    Set<String>? creditedDates,
    Set<String>? unlockedCatalogueIds,
    List<OwnedParcel>? parcels,
    List<RoadSegment>? roads,
    List<PlacedStructure>? structures,
    List<CompletedBridge>? bridges,
    List<WorldConstruction>? constructions,
    List<WorldEvent>? events,
  }) => ParcelWorldState(
    worldId: worldId,
    seed: seed,
    generatorVersion: generatorVersion,
    rulesVersion: rulesVersion,
    contentVersion: contentVersion,
    parcelSize: parcelSize,
    builderCapacity: builderCapacity ?? this.builderCapacity,
    simulatedDate: simulatedDate ?? this.simulatedDate,
    checkInHighWaterDate: checkInHighWaterDate ?? this.checkInHighWaterDate,
    constructionDay: constructionDay ?? this.constructionDay,
    coins: coins ?? this.coins,
    totalCoinsEarned: totalCoinsEarned ?? this.totalCoinsEarned,
    totalCoinsSpent: totalCoinsSpent ?? this.totalCoinsSpent,
    nextEntityNumber: nextEntityNumber ?? this.nextEntityNumber,
    nextEventNumber: nextEventNumber ?? this.nextEventNumber,
    creditedDates: creditedDates ?? this.creditedDates,
    unlockedCatalogueIds: unlockedCatalogueIds ?? this.unlockedCatalogueIds,
    parcels: parcels ?? this.parcels,
    roads: roads ?? this.roads,
    structures: structures ?? this.structures,
    bridges: bridges ?? this.bridges,
    constructions: constructions ?? this.constructions,
    events: events ?? this.events,
  );

  Map<String, Object?> toJson() => {
    'schemaVersion': parcelWorldSchemaVersion,
    'worldId': worldId,
    'generatorVersion': generatorVersion,
    'rulesVersion': rulesVersion,
    'contentVersion': contentVersion,
    'seed': seed,
    'parcelSize': parcelSize,
    'builderCapacity': builderCapacity,
    'simulatedDate': dateKey,
    'checkInHighWaterDate': worldDateKey(checkInHighWaterDate),
    'constructionDay': constructionDay,
    'coins': coins,
    'totalCoinsEarned': totalCoinsEarned,
    'totalCoinsSpent': totalCoinsSpent,
    'nextEntityNumber': nextEntityNumber,
    'nextEventNumber': nextEventNumber,
    'creditedDates': creditedDates.toList()..sort(),
    'unlockedCatalogueIds': unlockedCatalogueIds.toList()..sort(),
    'parcels': parcels.map((parcel) => parcel.toJson()).toList(),
    'roads': roads.map((road) => road.toJson()).toList(),
    'structures': structures.map((structure) => structure.toJson()).toList(),
    'bridges': bridges.map((bridge) => bridge.toJson()).toList(),
    'constructions': constructions
        .map((construction) => construction.toJson())
        .toList(),
    'events': events.map((event) => event.toJson()).toList(),
  };

  factory ParcelWorldState.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != parcelWorldSchemaVersion) {
      throw const FormatException('Unsupported parcel-world save version.');
    }
    final dateKey = json['simulatedDate']! as String;
    final highWaterKey = json['checkInHighWaterDate']! as String;
    final parsedDate = DateTime.tryParse(dateKey);
    final parsedHighWater = DateTime.tryParse(highWaterKey);
    if (parsedDate == null ||
        worldDateKey(parsedDate) != dateKey ||
        parsedHighWater == null ||
        worldDateKey(parsedHighWater) != highWaterKey ||
        highWaterKey.compareTo(dateKey) < 0) {
      throw const FormatException('Invalid simulated date in world save.');
    }
    return ParcelWorldState(
      worldId: json['worldId']! as String,
      seed: json['seed']! as int,
      generatorVersion: json['generatorVersion']! as int,
      rulesVersion: json['rulesVersion']! as int,
      contentVersion: json['contentVersion']! as int,
      parcelSize: json['parcelSize']! as int,
      builderCapacity: json['builderCapacity']! as int,
      simulatedDate: DateTime.utc(
        parsedDate.year,
        parsedDate.month,
        parsedDate.day,
      ),
      checkInHighWaterDate: DateTime.utc(
        parsedHighWater.year,
        parsedHighWater.month,
        parsedHighWater.day,
      ),
      constructionDay: json['constructionDay']! as int,
      coins: json['coins']! as int,
      totalCoinsEarned: json['totalCoinsEarned']! as int,
      totalCoinsSpent: json['totalCoinsSpent']! as int,
      nextEntityNumber: json['nextEntityNumber']! as int,
      nextEventNumber: json['nextEventNumber']! as int,
      creditedDates: Set<String>.from(json['creditedDates']! as List),
      unlockedCatalogueIds: Set<String>.from(
        json['unlockedCatalogueIds']! as List,
      ),
      parcels: (json['parcels']! as List)
          .map((value) => OwnedParcel.fromJson(worldJsonMap(value)))
          .toList(),
      roads: (json['roads']! as List)
          .map((value) => RoadSegment.fromJson(worldJsonMap(value)))
          .toList(),
      structures: (json['structures']! as List)
          .map((value) => PlacedStructure.fromJson(worldJsonMap(value)))
          .toList(),
      bridges: (json['bridges']! as List)
          .map((value) => CompletedBridge.fromJson(worldJsonMap(value)))
          .toList(),
      constructions: (json['constructions']! as List)
          .map((value) => WorldConstruction.fromJson(worldJsonMap(value)))
          .toList(),
      events: (json['events']! as List)
          .map((value) => WorldEvent.fromJson(worldJsonMap(value)))
          .toList(),
    );
  }
}

String worldDateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

ParcelWorldState newParcelWorldState({
  required ContentBundle content,
  required int seed,
  required TerrainProvider terrainProvider,
  DateTime? today,
}) {
  final date = today ?? DateTime.now();
  final parcelCoord = const ParcelCoord(0, 0);
  final terrain = parcelCoord
      .cells(defaultParcelSize)
      .map((cell) => terrainProvider.sample(cell, seed))
      .toList();
  final startRoadCell = const CellCoord(
    defaultParcelSize ~/ 2,
    defaultParcelSize ~/ 2,
  );
  return ParcelWorldState(
    worldId: 'parcel-world-$seed',
    seed: seed,
    generatorVersion: terrainProvider.generatorVersion,
    rulesVersion: parcelWorldRulesVersion,
    contentVersion: parcelWorldContentVersion,
    parcelSize: defaultParcelSize,
    builderCapacity: content.economy.startingBuilderCapacity,
    simulatedDate: DateTime.utc(date.year, date.month, date.day),
    checkInHighWaterDate: DateTime.utc(date.year, date.month, date.day),
    constructionDay: 0,
    coins: content.economy.startingWalletCoins,
    totalCoinsEarned: 0,
    totalCoinsSpent: 0,
    nextEntityNumber: 1,
    nextEventNumber: 1,
    creditedDates: const {},
    // Derived: every enabled model that unlocks at population 0.
    unlockedCatalogueIds: {
      for (final model in content.purchaseableModels)
        if (model.unlockAtPopulation == 0) model.id,
    },
    parcels: [
      OwnedParcel(
        coord: parcelCoord,
        pricePaid: 0,
        purchasedAtDay: 0,
        terrain: terrain,
      ),
    ],
    roads: [
      RoadSegment(
        id: 'road-start',
        cell: startRoadCell,
        style: RoadStyle.dirt,
        pricePaid: 0,
        completedAtDay: 0,
      ),
    ],
    structures: const [],
    bridges: const [],
    constructions: const [],
    events: const [],
  );
}

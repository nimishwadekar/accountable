import 'coordinates.dart';
import 'terrain_provider.dart';

import '../content/content_bundle.dart';

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

  /// Road side the door faces, snapshotted at plan time from the
  /// bordering roads: 'north', 'east', 'south', or 'west'. The art
  /// variant follows the side's screen half — north/east draw the
  /// right-facing door, south/west the left. Null when the chosen
  /// sprite has no facings or for decorations with a single facing.
  final String? facing;
}

/// Subtiles per tile axis on the prop lattice: 8×8 = 64 positions,
/// and one tile's occupancy fits a 64-bit mask.
const propSubtilesPerAxis = 8;

/// The default subtile, and where props sat before the lattice
/// existed: the tile's front corner. Props anchor at their subtile's
/// centre, so this lands 2 px shy of the tile's old south-vertex
/// structure spot — the price of every prop standing inside its
/// slot rather than on its front tip.
const propFrontSubtile = propSubtilesPerAxis - 1;

/// A placed decoration: a point object on the subtile lattice, drawn
/// with the standing content but stored apart from buildings. One
/// prop per subtile; sprites may overlap freely.
class PlacedProp {
  PlacedProp({
    required this.id,
    required this.catalogueId,
    required this.cell,
    required this.subtileX,
    required this.subtileY,
    required this.pricePaid,
    required this.placedAtDay,
    this.assetRole,
    this.facing,
  });

  final String id;
  final String catalogueId;

  /// The tile the prop stands on: ground, a completed road, or a
  /// completed bridge deck.
  final CellCoord cell;

  /// Position on the tile's 8×8 subtile lattice (0..7). The sprite
  /// anchors at the subtile's centre.
  final int subtileX;
  final int subtileY;
  final int pricePaid;
  final int placedAtDay;

  /// Rolled sprite variant and facade side, snapshotted at placement
  /// exactly like a structure's.
  final String? assetRole;
  final String? facing;
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
}

enum WorldConstructionKind { structure, road, bridge }

class WorldConstruction {
  WorldConstruction({
    required this.id,
    required this.kind,
    required this.startedAtDay,
    this.stagesDone = 0,
    this.builderSlot,
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

  /// Stage progress. For structures: construction stages completed —
  /// the stage count itself is content ([StructureDefinition.
  /// constructionStages]). For bridges: span cells delivered so far,
  /// in order — near bank, span tiles, far bank. Roads keep no
  /// counter here: their delivered tiles are the road rows
  /// themselves, so delivery always agrees with the map.
  final int stagesDone;

  /// Builder slot holding this project. Structures only — building
  /// crews are the concurrency limit; road and bridge creep is
  /// automatic and consumes no builder.
  final int? builderSlot;
  final int startedAtDay;

  /// Population the finished building will contribute, snapshotted from
  /// content at plan time alongside the footprint and cost.
  final int population;

  /// Sprite variant rolled at plan time; transferred to the placed
  /// structure on completion. Null for non-structure jobs and saves
  /// predating variants.
  final String? assetRole;

  /// Road side the door faces, chosen at plan time from the bordering
  /// roads ('north', 'east', 'south', 'west') and transferred to the
  /// placed structure on completion. Null for sprites without facings.
  /// The player may flip it to the other screen half while the plan is
  /// unfinished.
  final String? facing;

  /// The cells a bridge delivers in order: near bank, span tiles,
  /// far bank. Empty for non-bridge jobs.
  List<CellCoord> get bridgeDeliveryCells => [
    ?nearBank,
    ...waterCells,
    ?farBank,
  ];
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
    required this.lastCheckInDate,
    required this.checkInCount,
    required Set<String> unlockedCatalogueIds,
    required List<OwnedParcel> parcels,
    required List<RoadSegment> roads,
    required List<PlacedStructure> structures,
    required List<PlacedProp> props,
    required List<CompletedBridge> bridges,
    required List<WorldConstruction> constructions,
    required List<WorldEvent> events,
  }) : unlockedCatalogueIds = Set.unmodifiable(unlockedCatalogueIds),
       parcels = List.unmodifiable(parcels),
       roads = List.unmodifiable(roads),
       structures = List.unmodifiable(structures),
       props = List.unmodifiable(props),
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

  /// The most recent date a check-in was credited. Check-in is allowed
  /// only on the high-water date and only if that date was not already
  /// credited — together with [checkInHighWaterDate] this reproduces the
  /// no-backfill rule without storing a dated ledger.
  final DateTime? lastCheckInDate;

  /// Total check-ins ever credited. The dated ledger itself is not
  /// stored; only this count and [lastCheckInDate] persist.
  final int checkInCount;
  final Set<String> unlockedCatalogueIds;
  final List<OwnedParcel> parcels;
  final List<RoadSegment> roads;
  final List<PlacedStructure> structures;
  final List<PlacedProp> props;
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
    DateTime? lastCheckInDate,
    int? checkInCount,
    Set<String>? unlockedCatalogueIds,
    List<OwnedParcel>? parcels,
    List<RoadSegment>? roads,
    List<PlacedStructure>? structures,
    List<PlacedProp>? props,
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
    lastCheckInDate: lastCheckInDate ?? this.lastCheckInDate,
    checkInCount: checkInCount ?? this.checkInCount,
    unlockedCatalogueIds: unlockedCatalogueIds ?? this.unlockedCatalogueIds,
    parcels: parcels ?? this.parcels,
    roads: roads ?? this.roads,
    structures: structures ?? this.structures,
    props: props ?? this.props,
    bridges: bridges ?? this.bridges,
    constructions: constructions ?? this.constructions,
    events: events ?? this.events,
  );
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
    // The founding stake counts as earned, so the earned-minus-spent
    // ledger reconciles from the first check-in.
    coins: content.economy.startingTreasuryCoins,
    totalCoinsEarned: content.economy.startingTreasuryCoins,
    totalCoinsSpent: 0,
    nextEntityNumber: 1,
    nextEventNumber: 1,
    lastCheckInDate: null,
    checkInCount: 0,
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
        style: RoadStyle.asphalt,
        pricePaid: 0,
        completedAtDay: 0,
      ),
    ],
    structures: const [],
    props: const [],
    bridges: const [],
    constructions: const [],
    events: const [],
  );
}

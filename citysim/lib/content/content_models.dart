/// Data model for the JSON content layer.
///
/// Everything here is pure Dart — no Flutter and no `dart:io` — so the
/// game, the widget/rule tests, and the content-editor server all parse
/// and validate the very same files. Content is *data*: the game loads it
/// at startup and never writes it; only the editor dashboard (through its
/// server) modifies these files.
library;

import '../world/coordinates.dart';

// ---------------------------------------------------------------------------
// Shared enums (also used inside saved world state)
// ---------------------------------------------------------------------------

enum RoadStyle { asphalt }

enum StructureKind { building, decoration }

enum TerrainKind { grass, water, fog }

enum GroundStyle { grass, grassPuddle, dirt, asphalt, concrete }

// ---------------------------------------------------------------------------
// Catalogue
// ---------------------------------------------------------------------------

class StructureDefinition {
  const StructureDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.kind,
    required this.assetRoles,
    required this.subcategory,
    required this.footprintColumns,
    required this.footprintRows,
    required this.costCoins,
    required this.population,
    required this.unlockAtPopulation,
    required this.enabled,
    this.taxCoins = 0,
    this.upkeepCoins = 0,
    this.constructionStages = 1,
  });

  final String id;
  final String name;
  final String description;
  final StructureKind kind;

  /// Sprite variants this model can render as — each entry names a sprite
  /// *entity* (which may carry both door facings). One is rolled
  /// deterministically when the plan is placed and snapshotted onto the
  /// structure, giving visual variety per model. Every role must belong to
  /// a sprite in [spriteCategory]/[subcategory].
  final List<String> assetRoles;

  /// Editor grouping within the sprite category (e.g. "houses" inside
  /// buildings, "trees" inside props). Variants are picked only from
  /// sprites sharing this pair. The category itself is derived from
  /// [kind], so a building always draws from building sprites.
  final String subcategory;
  final int footprintColumns;
  final int footprintRows;
  final int costCoins;

  /// Population this model contributes once completed. Derived from
  /// content at placement time and snapshotted onto the placed structure.
  final int population;

  /// Population at which the model becomes unlocked. Zero means unlocked
  /// from the start.
  final int unlockAtPopulation;

  /// Tax this building pays into the treasury at each check-in once
  /// complete. Construction sites pay nothing — tax starts on
  /// completion.
  final int taxCoins;

  /// Upkeep this building charges the treasury at each check-in once
  /// complete.
  final int upkeepCoins;

  /// Construction stages between planning and completion; each
  /// check-in advances one stage. Buildings only — decorations place
  /// instantly and are never staged.
  final int constructionStages;

  /// Net treasury effect of one completed building per check-in.
  int get netCoinsPerCheckIn => taxCoins - upkeepCoins;

  /// Disabled models stay loadable for existing saves but are hidden from
  /// new purchases and unlock grants.
  final bool enabled;

  /// The sprite category this model draws its variants from, derived from
  /// the gameplay kind — buildings render building sprites, decorations
  /// render props. Keeping this derived (rather than stored) means it can
  /// never disagree with [kind].
  String get spriteCategory =>
      kind == StructureKind.building ? 'buildings' : 'props';

  String get costLabel => '$costCoins ${costCoins == 1 ? 'coin' : 'coins'}';

  StructureDefinition copyWith({
    String? id,
    String? name,
    String? description,
    StructureKind? kind,
    List<String>? assetRoles,
    String? subcategory,
    int? footprintColumns,
    int? footprintRows,
    int? costCoins,
    int? population,
    int? unlockAtPopulation,
    bool? enabled,
    int? taxCoins,
    int? upkeepCoins,
    int? constructionStages,
  }) => StructureDefinition(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    kind: kind ?? this.kind,
    assetRoles: assetRoles ?? this.assetRoles,
    subcategory: subcategory ?? this.subcategory,
    footprintColumns: footprintColumns ?? this.footprintColumns,
    footprintRows: footprintRows ?? this.footprintRows,
    costCoins: costCoins ?? this.costCoins,
    population: population ?? this.population,
    unlockAtPopulation: unlockAtPopulation ?? this.unlockAtPopulation,
    enabled: enabled ?? this.enabled,
    taxCoins: taxCoins ?? this.taxCoins,
    upkeepCoins: upkeepCoins ?? this.upkeepCoins,
    constructionStages: constructionStages ?? this.constructionStages,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'kind': kind.name,
    'assetRoles': assetRoles,
    'subcategory': subcategory,
    'footprint': {'columns': footprintColumns, 'rows': footprintRows},
    'costCoins': costCoins,
    'population': population,
    'unlockAtPopulation': unlockAtPopulation,
    'enabled': enabled,
    'taxCoins': taxCoins,
    'upkeepCoins': upkeepCoins,
    'constructionStages': constructionStages,
  };

  static StructureDefinition fromJson(Map<String, Object?> json) =>
      StructureDefinition(
        id: json['id']! as String,
        name: json['name']! as String,
        description: json['description']! as String,
        kind: StructureKind.values.firstWhere(
          (value) => value.name == json['kind'],
        ),
        assetRoles: [
          for (final role in json['assetRoles']! as List) role as String,
        ],
        subcategory: json['subcategory'] as String? ?? '',
        footprintColumns:
            (json['footprint'] as Map<String, Object?>)['columns']! as int,
        footprintRows:
            (json['footprint'] as Map<String, Object?>)['rows']! as int,
        costCoins: json['costCoins']! as int,
        population: json['population'] as int? ?? 0,
        unlockAtPopulation: json['unlockAtPopulation'] as int? ?? 0,
        enabled: json['enabled'] as bool? ?? true,
        taxCoins: json['taxCoins'] as int? ?? 0,
        upkeepCoins: json['upkeepCoins'] as int? ?? 0,
        constructionStages: json['constructionStages'] as int? ?? 1,
      );
}

// ---------------------------------------------------------------------------
// Sprites
// ---------------------------------------------------------------------------

/// Which art variant a facing side draws with: the street face follows
/// the road's axis. A road on the north or south side runs east-west,
/// so the door belongs on the south (screen-left) facade — the `left`
/// variant. A road on the east or west side runs north-south, so the
/// door belongs on the east (screen-right) facade — the `right`
/// variant. Maps the compass facings saved with a structure to the
/// left/right keys of a sprite's `facings` art map.
String facingArtKey(String facing) =>
    facing == 'east' || facing == 'west' ? 'right' : 'left';

class SpriteDefinition {
  const SpriteDefinition({
    this.assetPath,
    this.facingPaths,
    this.renderScale = 0.5,
    this.groundAnchorX = 0.5,
    this.groundAnchorY = 1,
    this.baseOffsetY = 0,
    this.sideShifts = const {},
    this.sways = false,
    this.category = 'buildings',
    this.subcategory = '',
    this.codeReferenced = false,
    this.walkable = const [],
    this.surfaceLift = 0,
  });

  /// Path relative to the assets root for single-facing sprites (e.g.
  /// `sprites/ground/grass/tile_ground_grass.png`). Null when the sprite
  /// has [facingPaths].
  final String? assetPath;

  /// Left/right door facings for building sprites, each mapped to its own
  /// art file. A sprite with facings is one entity: every setting is
  /// shared by both sides and only the art differs. Null for
  /// single-facing sprites.
  final Map<String, String>? facingPaths;
  final double renderScale;
  final double groundAnchorX;
  final double groundAnchorY;

  /// Pixels of sprite content hanging below the tile's ground diamond
  /// (bridge support posts). The renderer keeps the sprite's aspect ratio
  /// and aligns the diamond's south tip with the cell's south vertex.
  final double baseOffsetY;

  /// Whether the ambient renderer gently rocks this sprite around its
  /// ground anchor to suggest wind. Only props may sway.
  final bool sways;

  /// Pedestrian walkability for road tiles: the tile's 8×8 subtile
  /// lattice as eight row bytes. Row index runs along the row axis
  /// (0 = north edge), bit index along the column axis (bit 0 = west
  /// edge), so `rows[y] & (1 << x)` marks subtile (x, y) walkable.
  /// People may only stand on painted subtiles — the mask is the
  /// sidewalk and crossing network. Empty = the tile is unwalkable;
  /// road roles ship blank and are painted in the editor.
  final List<int> walkable;

  /// Subtile (x, y) walkability, mirroring the prop lattice indexing.
  /// Row bytes are clamped so a malformed mask can never read as more
  /// walkable than authored.
  bool walkableAt(int x, int y) =>
      x >= 0 &&
      x < 8 &&
      y >= 0 &&
      y < walkable.length &&
      (walkable[y].clamp(0, 255) >> x & 1) == 1;

  /// How far the sprite's surface sits above the cell's ground plane,
  /// in world px. Bridge decks render elevated — measured at 12 world
  /// px for the current art — and everything standing on them
  /// (pedestrians, props) rises by this much. Ramp roles derive their
  /// incline from the deck roles' value.
  final double surfaceLift;

  /// Per-road-side placement shifts, keyed by compass side. Each entry
  /// is `(col, row)` in fractions of the drawn sprite width: `col`
  /// runs along the column axis (east-positive), `row` along the row
  /// axis (south-positive). A side with no entry keeps the anchor
  /// placement. Only sprites with door facings shift — their
  /// structures are the ones that save a facing.
  final Map<String, (double, double)> sideShifts;

  /// The shift for a door side, or null when that side has no entry —
  /// the anchor placement stands. Renderers turn the fractions into a
  /// world offset: `col` toward the screen down-right, `row` toward
  /// the down-left, half as tall as wide per the 2:1 iso.
  (double, double)? sideShiftFor(String? facing) =>
      facing == null ? null : sideShifts[facing];

  /// Dashboard grouping: ground, shores, roads, bridges, buildings, props.
  final String category;

  /// Grouping within the category (e.g. "houses" inside buildings, "trees"
  /// inside props). Sprites own the taxonomy — new subcategories are
  /// created here, and catalogue models pick from what exists. Defaults to
  /// the category itself for single-group categories like ground/roads.
  final String subcategory;

  /// True for roles whose names are constructed in game code (terrain,
  /// shores, road masks, bridges). Their metadata is editable but the role
  /// name is locked in the dashboard.
  final bool codeReferenced;

  bool get hasFacings => facingPaths != null;

  /// Every art file behind this sprite — one path for single-facing
  /// sprites, one per facing otherwise. Used by file-existence checks and
  /// image preloading.
  List<String> get allPaths {
    final facings = facingPaths;
    if (facings != null) return List.unmodifiable(facings.values);
    return assetPath == null ? const <String>[] : <String>[assetPath!];
  }

  /// Resolves the art file for a door side. Facings sprites keep one
  /// variant per street axis — north/south roads draw the left-facing
  /// door, east/west ones the right — so the compass facing maps to a
  /// variant before lookup, and a missing facing falls back to the left
  /// variant. Single-facing sprites ignore [facing].
  String pathFor(String? facing) {
    final facings = facingPaths;
    if (facings == null) return assetPath!;
    return facings[facingArtKey(facing ?? 'south')] ?? facings['left']!;
  }

  SpriteDefinition copyWith({
    String? assetPath,
    Map<String, String>? facingPaths,
    double? renderScale,
    double? groundAnchorX,
    double? groundAnchorY,
    double? baseOffsetY,
    Map<String, (double, double)>? sideShifts,
    bool? sways,
    String? category,
    String? subcategory,
    bool? codeReferenced,
    List<int>? walkable,
    double? surfaceLift,
  }) => SpriteDefinition(
    assetPath: assetPath ?? this.assetPath,
    facingPaths: facingPaths ?? this.facingPaths,
    renderScale: renderScale ?? this.renderScale,
    groundAnchorX: groundAnchorX ?? this.groundAnchorX,
    groundAnchorY: groundAnchorY ?? this.groundAnchorY,
    baseOffsetY: baseOffsetY ?? this.baseOffsetY,
    sideShifts: sideShifts ?? this.sideShifts,
    sways: sways ?? this.sways,
    category: category ?? this.category,
    subcategory: subcategory ?? this.subcategory,
    codeReferenced: codeReferenced ?? this.codeReferenced,
    walkable: walkable ?? this.walkable,
    surfaceLift: surfaceLift ?? this.surfaceLift,
  );

  Map<String, Object?> toJson() => {
    if (facingPaths != null) 'facings': facingPaths else 'path': assetPath,
    'renderScale': renderScale,
    'groundAnchor': [groundAnchorX, groundAnchorY],
    'baseOffsetY': baseOffsetY,
    if (sideShifts.isNotEmpty)
      'sideShifts': {
        for (final entry in sideShifts.entries)
          entry.key: [entry.value.$1, entry.value.$2],
      },
    'sways': sways,
    'category': category,
    'subcategory': subcategory,
    'codeReferenced': codeReferenced,
    if (walkable.isNotEmpty) 'walkable': walkable,
    if (surfaceLift != 0) 'surfaceLift': surfaceLift,
  };

  static SpriteDefinition fromJson(Map<String, Object?> json) {
    final anchor = (json['groundAnchor'] as List).cast<num>();
    final category = json['category'] as String? ?? 'buildings';
    final facings = json['facings'];
    return SpriteDefinition(
      assetPath: json['path'] as String?,
      facingPaths: facings is Map
          ? {
              for (final entry in facings.entries)
                entry.key as String: entry.value as String,
            }
          : null,
      renderScale: (json['renderScale'] as num?)?.toDouble() ?? 0.5,
      groundAnchorX: anchor.isNotEmpty ? anchor[0].toDouble() : 0.5,
      groundAnchorY: anchor.length > 1 ? anchor[1].toDouble() : 1,
      baseOffsetY: (json['baseOffsetY'] as num?)?.toDouble() ?? 0,
      sideShifts: _parseSideShifts(json['sideShifts']),
      sways: json['sways'] as bool? ?? false,
      category: category,
      subcategory: json['subcategory'] as String? ?? category,
      codeReferenced: json['codeReferenced'] as bool? ?? false,
      walkable: _parseWalkable(json['walkable']),
      surfaceLift: (json['surfaceLift'] as num?)?.toDouble() ?? 0,
    );
  }

  static Map<String, (double, double)> _parseSideShifts(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.value is List && (entry.value as List).length >= 2)
          entry.key as String: (
            ((entry.value as List)[0] as num?)?.toDouble() ?? 0,
            ((entry.value as List)[1] as num?)?.toDouble() ?? 0,
          ),
    };
  }

  /// Eight row bytes, kept exactly as authored (malformed rows become
  /// −1) so [validateContentData] can report them; the walkable
  /// lattice ignores any mask that is not eight bytes in 0–255.
  static List<int> _parseWalkable(Object? raw) {
    if (raw is! List) return const [];
    return [for (final row in raw) row is num ? row.toInt() : -1];
  }
}

// ---------------------------------------------------------------------------
// Economy and progression
// ---------------------------------------------------------------------------

class BuilderProgressionStep {
  const BuilderProgressionStep({
    required this.atPopulation,
    required this.capacity,
  });

  final int atPopulation;
  final int capacity;

  Map<String, Object?> toJson() => {
    'atPopulation': atPopulation,
    'capacity': capacity,
  };

  static BuilderProgressionStep fromJson(Map<String, Object?> json) =>
      BuilderProgressionStep(
        atPopulation: json['atPopulation']! as int,
        capacity: json['capacity']! as int,
      );
}

class EconomyContent {
  const EconomyContent({
    required this.startingTreasuryCoins,
    required this.startingBuilderCapacity,
    required this.roadTileCostCoins,
    required this.bridgeTileCostCoins,
    required this.parcelBaseCoins,
    required this.builderProgression,
    this.roadTaxCoinsPerTile = 0,
    this.roadUpkeepCoinsPerTile = 0,
    this.bridgeTaxCoinsPerTile = 0,
    this.bridgeUpkeepCoinsPerTile = 0,
  });

  /// The single town treasury's opening balance for a brand-new
  /// world. Existing saves carry their wallet over as the treasury.
  final int startingTreasuryCoins;

  /// Fixed at 1 by product rule; shown read-only in the dashboard.
  final int startingBuilderCapacity;

  /// Upfront price of one road tile in a stretch plan — the whole
  /// stretch is paid at planning, then creeps one tile per check-in.
  final int roadTileCostCoins;

  /// Upfront price of one bridge span tile; banks cost the road tile
  /// price. The bridge is paid at planning, then the deck creeps one
  /// tile per check-in.
  final int bridgeTileCostCoins;

  /// Flat parcel price: every parcel on the map costs the same.
  final int parcelBaseCoins;

  /// Per-tile tax and upkeep of infrastructure, collected at each
  /// check-in. Tax seeds at zero — paving must never mint coins — but
  /// the fields exist so infra stays uniform with buildings.
  final int roadTaxCoinsPerTile;
  final int roadUpkeepCoinsPerTile;
  final int bridgeTaxCoinsPerTile;
  final int bridgeUpkeepCoinsPerTile;
  final List<BuilderProgressionStep> builderProgression;

  /// Builder capacity granted for a population (monotonic; the highest
  /// crossed threshold wins, never below the starting capacity).
  int builderCapacityForPopulation(int population) {
    var capacity = startingBuilderCapacity;
    for (final step in builderProgression) {
      if (population >= step.atPopulation && step.capacity > capacity) {
        capacity = step.capacity;
      }
    }
    return capacity;
  }

  Map<String, Object?> toJson() => {
    'startingTreasuryCoins': startingTreasuryCoins,
    'startingBuilderCapacity': startingBuilderCapacity,
    'roadTileCostCoins': roadTileCostCoins,
    'bridgeCost': {'bridgeTileCostCoins': bridgeTileCostCoins},
    'roadTaxCoinsPerTile': roadTaxCoinsPerTile,
    'roadUpkeepCoinsPerTile': roadUpkeepCoinsPerTile,
    'bridgeTaxCoinsPerTile': bridgeTaxCoinsPerTile,
    'bridgeUpkeepCoinsPerTile': bridgeUpkeepCoinsPerTile,
    'parcelBaseCoins': parcelBaseCoins,
    'builderProgression': builderProgression
        .map((step) => step.toJson())
        .toList(),
  };

  static EconomyContent fromJson(Map<String, Object?> json) {
    final bridge = json['bridgeCost'] as Map<String, Object?>;
    return EconomyContent(
      startingTreasuryCoins: json['startingTreasuryCoins']! as int,
      startingBuilderCapacity: json['startingBuilderCapacity']! as int,
      roadTileCostCoins: json['roadTileCostCoins']! as int,
      bridgeTileCostCoins: bridge['bridgeTileCostCoins']! as int,
      roadTaxCoinsPerTile: json['roadTaxCoinsPerTile'] as int? ?? 0,
      roadUpkeepCoinsPerTile: json['roadUpkeepCoinsPerTile'] as int? ?? 0,
      bridgeTaxCoinsPerTile: json['bridgeTaxCoinsPerTile'] as int? ?? 0,
      bridgeUpkeepCoinsPerTile: json['bridgeUpkeepCoinsPerTile'] as int? ?? 0,
      parcelBaseCoins: json['parcelBaseCoins']! as int,
      builderProgression: [
        for (final step in json['builderProgression']! as List)
          BuilderProgressionStep.fromJson(
            (step as Map).cast<String, Object?>(),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Ambience
// ---------------------------------------------------------------------------

class VegetationSwayContent {
  const VegetationSwayContent({
    required this.maxAngleRadians,
    required this.baseFrequency,
    required this.frequencySteps,
    required this.frequencyStep,
  });

  final double maxAngleRadians;
  final double baseFrequency;
  final int frequencySteps;
  final double frequencyStep;

  Map<String, Object?> toJson() => {
    'maxAngleRadians': maxAngleRadians,
    'baseFrequency': baseFrequency,
    'frequencySteps': frequencySteps,
    'frequencyStep': frequencyStep,
  };

  static VegetationSwayContent fromJson(Map<String, Object?> json) =>
      VegetationSwayContent(
        maxAngleRadians: (json['maxAngleRadians']! as num).toDouble(),
        baseFrequency: (json['baseFrequency']! as num).toDouble(),
        frequencySteps: json['frequencySteps']! as int,
        frequencyStep: (json['frequencyStep']! as num).toDouble(),
      );
}

class PedestrianContent {
  const PedestrianContent({
    required this.spriteScale,
    required this.walkFrameRate,
    required this.speedMin,
    required this.speedRange,
    required this.roadCellsPerPerson,
    required this.maxCount,
    required this.lateralWanderX,
    required this.lateralWanderY,
  });

  final double spriteScale;
  final double walkFrameRate;
  final double speedMin;
  final double speedRange;
  final int roadCellsPerPerson;
  final int maxCount;
  final double lateralWanderX;
  final double lateralWanderY;

  Map<String, Object?> toJson() => {
    'spriteScale': spriteScale,
    'walkFrameRate': walkFrameRate,
    'speedMin': speedMin,
    'speedRange': speedRange,
    'roadCellsPerPerson': roadCellsPerPerson,
    'maxCount': maxCount,
    'lateralWanderX': lateralWanderX,
    'lateralWanderY': lateralWanderY,
  };

  static PedestrianContent fromJson(Map<String, Object?> json) =>
      PedestrianContent(
        spriteScale: (json['spriteScale']! as num).toDouble(),
        walkFrameRate: (json['walkFrameRate']! as num).toDouble(),
        speedMin: (json['speedMin']! as num).toDouble(),
        speedRange: (json['speedRange']! as num).toDouble(),
        roadCellsPerPerson: json['roadCellsPerPerson']! as int,
        maxCount: json['maxCount']! as int,
        lateralWanderX: (json['lateralWanderX']! as num).toDouble(),
        lateralWanderY: (json['lateralWanderY']! as num).toDouble(),
      );
}

class UnownedLandWashContent {
  const UnownedLandWashContent({required this.alpha, required this.colorRgb});

  final int alpha;
  final List<int> colorRgb;

  Map<String, Object?> toJson() => {'alpha': alpha, 'colorRgb': colorRgb};

  static UnownedLandWashContent fromJson(Map<String, Object?> json) =>
      UnownedLandWashContent(
        alpha: json['alpha']! as int,
        colorRgb: [for (final value in json['colorRgb']! as List) value as int],
      );
}

/// The faint cell grid drawn over every tile — one renderer-owned
/// lattice in addition to the natural grid the ground art's edge
/// shading tiles into. Tuned like the wash: enabled plus alpha plus
/// colour. Disabled, the renderer draws nothing and only the art's
/// own edges show.
class TileGridContent {
  const TileGridContent({
    this.enabled = true,
    required this.alpha,
    required this.colorRgb,
  });

  final bool enabled;
  final int alpha;
  final List<int> colorRgb;

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'alpha': alpha,
    'colorRgb': colorRgb,
  };

  static TileGridContent fromJson(Map<String, Object?> json) => TileGridContent(
    enabled: json['enabled'] as bool? ?? true,
    alpha: json['alpha'] as int? ?? 55,
    colorRgb: [
      for (final value in (json['colorRgb'] as List?) ?? const [30, 101, 82])
        value as int,
    ],
  );
}

class AmbienceContent {
  const AmbienceContent({
    required this.ambientTimeScale,
    required this.vegetationSway,
    required this.pedestrians,
    required this.unownedLandWash,
    required this.tileGrid,
  });

  final double ambientTimeScale;
  final VegetationSwayContent vegetationSway;
  final PedestrianContent pedestrians;
  final UnownedLandWashContent unownedLandWash;
  final TileGridContent tileGrid;

  Map<String, Object?> toJson() => {
    'ambientTimeScale': ambientTimeScale,
    'vegetationSway': vegetationSway.toJson(),
    'pedestrians': pedestrians.toJson(),
    'unownedLandWash': unownedLandWash.toJson(),
    'tileGrid': tileGrid.toJson(),
  };

  static AmbienceContent fromJson(Map<String, Object?> json) => AmbienceContent(
    ambientTimeScale: (json['ambientTimeScale']! as num).toDouble(),
    vegetationSway: VegetationSwayContent.fromJson(
      json['vegetationSway']! as Map<String, Object?>,
    ),
    pedestrians: PedestrianContent.fromJson(
      json['pedestrians']! as Map<String, Object?>,
    ),
    unownedLandWash: UnownedLandWashContent.fromJson(
      json['unownedLandWash']! as Map<String, Object?>,
    ),
    tileGrid: TileGridContent.fromJson(
      (json['tileGrid'] as Map?)?.cast<String, Object?>() ?? const {},
    ),
  );
}

// ---------------------------------------------------------------------------
// Terrain
// ---------------------------------------------------------------------------

/// One authored water body. The list is ordered: the first body whose
/// shape contains a cell determines that cell's water; land otherwise.
/// Authored geography: the `terrain.json` category. The map *is* the
/// entries — every authored parcel maps to its base terrain, and any
/// parcel without an entry is fog: uncharted, unbuyable, rendered as
/// the cloud deck that rings the known world. Authoring a parcel is
/// what clears the fog — nothing in the save tracks it, because the
/// fog is fully derived from the content. Cell-level detail layers
/// will be added on top of this later.
class TerrainContent {
  const TerrainContent({
    required this.generatorVersion,
    required this.parcels,
    this.tiles = const {},
  });

  final int generatorVersion;
  final Map<ParcelCoord, TerrainKind> parcels;

  /// Per-tile overrides inside authored parcels, keyed by absolute
  /// cell. An absent key falls back to the parcel's base kind, and
  /// painting a tile to its parcel's base is the same as erasing it —
  /// the editor writes it that way to keep the file sparse. Only
  /// grass and water are paintable: fog is a parcel-level kind, and
  /// other terrain types join the palette later.
  final Map<CellCoord, TerrainKind> tiles;

  /// Whether a parcel is authored on the map. Authored fog parcels
  /// are on the map but stay hidden — buying is gated by terrain
  /// kind, not authorship.
  bool isOnMap(ParcelCoord coord) => parcels.containsKey(coord);

  Map<String, Object?> toJson() => {
    'generatorVersion': generatorVersion,
    'parcels': {
      for (final entry in parcels.entries)
        '${entry.key.x},${entry.key.y}': entry.value.name,
    },
    if (tiles.isNotEmpty)
      'tiles': {
        for (final entry in tiles.entries)
          '${entry.key.column},${entry.key.row}': entry.value.name,
      },
  };

  static TerrainContent fromJson(Map<String, Object?> json) {
    final raw = json['parcels']! as Map;
    final rawTiles = json['tiles'];
    return TerrainContent(
      generatorVersion: json['generatorVersion']! as int,
      parcels: {
        for (final entry in raw.entries)
          _parcelCoord(entry.key as String): _terrainKind(
            entry.value as String,
          ),
      },
      tiles: rawTiles is Map
          ? {
              for (final entry in rawTiles.entries)
                _cellCoord(entry.key as String): _terrainKind(
                  entry.value as String,
                ),
            }
          : const {},
    );
  }
}

ParcelCoord _parcelCoord(String key) {
  final parts = key.split(',');
  if (parts.length != 2) {
    throw FormatException('"$key" is not a valid parcel key.');
  }
  final x = int.tryParse(parts[0].trim());
  final y = int.tryParse(parts[1].trim());
  if (x == null || y == null) {
    throw FormatException('"$key" is not a valid parcel key.');
  }
  return ParcelCoord(x, y);
}

CellCoord _cellCoord(String key) {
  final parts = key.split(',');
  if (parts.length != 2) {
    throw FormatException('"$key" is not a valid tile key.');
  }
  final column = int.tryParse(parts[0].trim());
  final row = int.tryParse(parts[1].trim());
  if (column == null || row == null) {
    throw FormatException('"$key" is not a valid tile key.');
  }
  return CellCoord(column, row);
}

TerrainKind _terrainKind(String name) =>
    TerrainKind.values.firstWhere((value) => value.name == name);

// ---------------------------------------------------------------------------
// Manifest
// ---------------------------------------------------------------------------

class ContentManifest {
  const ContentManifest({required this.schemaVersion});

  /// Version of the content *format* (field names and shapes), not a save
  /// counter — content history is tracked by git like any other source.
  final int schemaVersion;

  Map<String, Object?> toJson() => {'schemaVersion': schemaVersion};

  static ContentManifest fromJson(Map<String, Object?> json) =>
      ContentManifest(schemaVersion: json['schemaVersion']! as int);
}

// ---------------------------------------------------------------------------
// Validation (shared by the game loader and the editor server)
// ---------------------------------------------------------------------------

class ContentIssue {
  const ContentIssue(this.severity, this.message);

  /// 'error' blocks saving; 'warning' is informational.
  final String severity;
  final String message;

  @override
  String toString() => '[$severity] $message';
}

/// Sprite roles whose names are constructed in game code; a bundle without
/// them renders a broken world, so validation requires them.
final requiredSpriteRoles = <String>[
  'terrain.grass',
  'terrain.grass.puddle',
  'terrain.dirt',
  'terrain.asphalt',
  'terrain.concrete',
  'terrain.water',
  // Shores are not sprites: the water tile carries a band of the
  // neighbouring land's material, composed at runtime from the
  // ground tiles themselves (composeShoreBandPixels).
  for (final dir in ['ne', 'nw', 'se', 'sw']) 'road.end.$dir',
  'road.straight.se',
  'road.straight.sw',
  for (final dir in ['n', 'e', 's', 'w']) 'road.corner.$dir',
  for (final dir in ['ne', 'nw', 'se', 'sw']) 'road.t.$dir',
  'road.cross',
  // Pelican crossings paint the approach tiles beside junctions.
  for (final dir in ['ne', 'nw', 'se', 'sw']) 'road.pelican.$dir',
  'bridge.body.se',
  'bridge.body.sw',
  for (final dir in ['ne', 'nw', 'se', 'sw']) 'bridge.ramp.$dir',
  // The fog deck over uncharted parcels — a terrain like any other,
  // rendered from sprites like grass and water. One PERIODIC tile:
  // its grain wraps, so every cell continues its neighbours
  // seamlessly (no per-tile borders reading as a grid). The wisps
  // are large soft cloud sprites hash-scattered over fog cells at
  // low density — their overlap is the foggy look. The boundary is
  // deliberately plain: fog tiles meet terrain directly, with no
  // edge-overlay or bank logic (tried in previews and dropped —
  // see ASSET_NOTICE).
  'terrain.fog',
  'fog.wisp.a',
  'fog.wisp.b',
  'fog.wisp.c',
];

/// Structural validation: cross-references, ranges, and ordering. File
/// existence is checked server-side only (the game cannot list assets).
List<ContentIssue> validateContentData({
  required List<StructureDefinition> catalogue,
  required Map<String, SpriteDefinition> sprites,
  required EconomyContent economy,
  required AmbienceContent ambience,
  required TerrainContent terrain,
}) {
  final issues = <ContentIssue>[];
  void error(String message) => issues.add(ContentIssue('error', message));
  void warning(String message) => issues.add(ContentIssue('warning', message));

  if (terrain.generatorVersion < 1) {
    error('Terrain generator version must be positive.');
  }
  if (terrain.parcels.isEmpty) {
    error('The terrain map needs at least one parcel.');
  }
  if (terrain.parcels[const ParcelCoord(0, 0)] != TerrainKind.grass) {
    error('The starter parcel (0,0) must be authored on the map as grass.');
  }
  for (final entry in terrain.parcels.entries) {
    if (entry.value == TerrainKind.fog) {
      error(
        'Parcel ${entry.key.x},${entry.key.y} cannot be fog — fog is not '
        'a terrain type, only the look of uncharted space. Delete the '
        'parcel to make it uncharted.',
      );
    }
  }
  for (final entry in terrain.tiles.entries) {
    if (entry.value == TerrainKind.fog) {
      error(
        'Tile ${entry.key.key} cannot be fog — fog is not a terrain '
        'type, only the look of uncharted space.',
      );
    }
    if (!terrain.isOnMap(parcelForCell(entry.key))) {
      error(
        'Tile ${entry.key.key} sits on an unauthored parcel — author '
        'the parcel before painting its tiles.',
      );
    }
  }

  if (catalogue.isEmpty) {
    error('The catalogue needs at least one model.');
  }
  final ids = <String>{};
  for (final model in catalogue) {
    if (model.id.isEmpty) error('A model has an empty id.');
    if (!ids.add(model.id)) error('Duplicate model id "${model.id}".');
    if (model.costCoins < 0) {
      error('${model.id}: cost must not be negative.');
    }
    if (model.population < 0) {
      error('${model.id}: population must not be negative.');
    }
    if (model.taxCoins < 0) {
      error('${model.id}: tax must not be negative.');
    }
    if (model.upkeepCoins < 0) {
      error('${model.id}: upkeep must not be negative.');
    }
    if (model.constructionStages < 1) {
      error('${model.id}: construction needs at least one stage.');
    }
    if (model.unlockAtPopulation < 0) {
      error('${model.id}: unlock threshold must not be negative.');
    }
    if (model.footprintColumns < 1 || model.footprintRows < 1) {
      error('${model.id}: footprint must be at least 1×1.');
    }
    if (model.assetRoles.isEmpty) {
      error('${model.id}: needs at least one sprite role.');
    }
    // Variants must come from the model's category/subcategory pair, and
    // the pair must exist among sprites — otherwise a model can point at
    // a group that was emptied or renamed.
    final pairSprites = sprites.values
        .where(
          (sprite) =>
              sprite.category == model.spriteCategory &&
              sprite.subcategory == model.subcategory,
        )
        .length;
    if (model.subcategory.isEmpty || pairSprites == 0) {
      error(
        '${model.id}: subcategory "${model.subcategory}" has no sprites in '
        '"${model.spriteCategory}".',
      );
    }
    for (final role in model.assetRoles) {
      final sprite = sprites[role];
      if (sprite == null) {
        error(
          '${model.id}: asset role "$role" is missing '
          'from the sprite manifest.',
        );
      } else if (sprite.category != model.spriteCategory ||
          sprite.subcategory != model.subcategory) {
        error(
          '${model.id}: variant "$role" belongs to '
          '${sprite.category}/${sprite.subcategory}, not '
          '${model.spriteCategory}/${model.subcategory}.',
        );
      }
    }
  }
  final startingModels = catalogue
      .where((model) => model.enabled && model.unlockAtPopulation == 0)
      .length;
  if (startingModels == 0) {
    error('At least one enabled model must unlock at population 0.');
  }
  final disabledInUse = catalogue
      .where((model) => !model.enabled && model.unlockAtPopulation == 0)
      .length;
  if (disabledInUse > 0) {
    warning(
      '$disabledInUse start-unlocked model(s) are disabled; new '
      'worlds will not offer them.',
    );
  }

  if (sprites.isEmpty) error('The sprite manifest is empty.');
  for (final entry in sprites.entries) {
    final sprite = entry.value;
    // A sprite is either single-facing (path) or a left/right pair
    // (facings) — never both, never neither, and a pair is complete.
    final hasPath = sprite.assetPath != null;
    if (hasPath == sprite.hasFacings) {
      error('Sprite "${entry.key}" needs exactly one of "path" or "facings".');
    } else if (sprite.hasFacings) {
      final facings = sprite.facingPaths!;
      if (facings.length != 2 ||
          !facings.containsKey('left') ||
          !facings.containsKey('right') ||
          facings.values.any((path) => path.isEmpty)) {
        error(
          'Sprite "${entry.key}" needs both a "left" and a "right" '
          'facing path.',
        );
      }
    } else if (sprite.assetPath!.isEmpty) {
      error('Sprite "${entry.key}" has an empty path.');
    }
    if (sprite.renderScale <= 0 || sprite.renderScale > 10) {
      error('Sprite "${entry.key}": renderScale must be within (0, 10].');
    }
    if (sprite.groundAnchorX < 0 ||
        sprite.groundAnchorX > 1 ||
        sprite.groundAnchorY < 0 ||
        sprite.groundAnchorY > 1) {
      error('Sprite "${entry.key}": ground anchors must be within [0, 1].');
    }
    if (sprite.baseOffsetY < -64 || sprite.baseOffsetY > 64) {
      error(
        'Sprite "${entry.key}": baseOffsetY must stay within ±64 art '
        'pixels of the ground anchor.',
      );
    }
    for (final shift in sprite.sideShifts.entries) {
      if (!const ['north', 'east', 'south', 'west'].contains(shift.key)) {
        error(
          'Sprite "${entry.key}": side shift "${shift.key}" is not a '
          'compass side.',
        );
        continue;
      }
      if (shift.value.$1 < -0.5 ||
          shift.value.$1 > 0.5 ||
          shift.value.$2 < -0.5 ||
          shift.value.$2 > 0.5) {
        error(
          'Sprite "${entry.key}": side shifts must stay within ±0.5 of '
          'the sprite width, per axis.',
        );
      }
    }
    if (sprite.sways && sprite.category != 'props') {
      warning('Sprite "${entry.key}": only props may sway in the wind.');
    }
    if (sprite.walkable.isNotEmpty) {
      if (sprite.category != 'roads' && sprite.category != 'bridges') {
        warning(
          'Sprite "${entry.key}": only road and bridge tiles carry '
          'walkable subtiles — pedestrians read them from those roles.',
        );
      }
      if (sprite.walkable.length != 8) {
        error(
          'Sprite "${entry.key}": walkable must be exactly eight row '
          'bytes, one per lattice row.',
        );
      } else if (sprite.walkable.any((row) => row < 0 || row > 255)) {
        error(
          'Sprite "${entry.key}": walkable row bytes must stay within '
          '0–255.',
        );
      }
    }
    if (sprite.surfaceLift < 0) {
      error(
        'Sprite "${entry.key}": surfaceLift cannot be negative — '
        'lowered surfaces are not a thing yet.',
      );
    }
  }
  for (final role in requiredSpriteRoles) {
    if (!sprites.containsKey(role)) {
      error('Required code-referenced sprite "$role" is missing.');
    }
  }

  if (economy.startingTreasuryCoins < 0) {
    error('Starting treasury must not be negative.');
  }
  if (economy.startingBuilderCapacity < 1) {
    error('Starting builder capacity must be at least 1.');
  }
  if (economy.roadTileCostCoins < 0) {
    error('Road tile cost must not be negative.');
  }
  if (economy.bridgeTileCostCoins < 0) {
    error('Bridge tile cost must not be negative.');
  }
  if (economy.parcelBaseCoins < 0) {
    error('The parcel price must not be negative.');
  }
  if (economy.roadUpkeepCoinsPerTile < 0 ||
      economy.bridgeUpkeepCoinsPerTile < 0) {
    error('Infrastructure upkeep must not be negative.');
  }
  if (economy.roadTaxCoinsPerTile < 0 || economy.bridgeTaxCoinsPerTile < 0) {
    error('Infrastructure tax must not be negative.');
  }
  if (economy.roadTaxCoinsPerTile > 0 || economy.bridgeTaxCoinsPerTile > 0) {
    warning(
      'Infrastructure tax mints coins from paving — keep road and '
      'bridge tax at zero.',
    );
  }
  var lastPopulation = -1;
  var lastCapacity = economy.startingBuilderCapacity;
  for (final step in economy.builderProgression) {
    if (step.atPopulation <= lastPopulation) {
      error('Builder progression thresholds must strictly increase.');
      break;
    }
    if (step.capacity <= lastCapacity) {
      error(
        'Builder progression capacities must strictly increase '
        'above ${economy.startingBuilderCapacity}.',
      );
      break;
    }
    lastPopulation = step.atPopulation;
    lastCapacity = step.capacity;
  }

  if (ambience.ambientTimeScale <= 0) {
    error('Ambient time scale must be positive.');
  }
  if (ambience.tileGrid.alpha < 0 ||
      ambience.tileGrid.alpha > 255 ||
      ambience.tileGrid.colorRgb.length != 3 ||
      ambience.tileGrid.colorRgb.any(
        (channel) => channel < 0 || channel > 255,
      )) {
    error('Tile grid needs an alpha and RGB channels within [0, 255].');
  }
  if (ambience.vegetationSway.maxAngleRadians < 0 ||
      ambience.vegetationSway.maxAngleRadians > 0.5) {
    error('Vegetation sway angle must be within [0, 0.5] radians.');
  }
  if (ambience.pedestrians.spriteScale <= 0 ||
      ambience.pedestrians.walkFrameRate <= 0 ||
      ambience.pedestrians.speedMin <= 0 ||
      ambience.pedestrians.speedRange < 0 ||
      ambience.pedestrians.roadCellsPerPerson < 1 ||
      ambience.pedestrians.maxCount < 0) {
    error('Pedestrian ambience values are out of range.');
  }
  return issues;
}

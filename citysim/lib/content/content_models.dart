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
    this.households = 0,
    this.jobs = 0,
    this.serviceCategory,
    this.serviceCapacity = 0,
    this.legalTerrain = const [],
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

  /// Terrain tags this model may stand on — the nature brush's
  /// legality vocabulary. Today the only tag is `land` (grass); the
  /// list is empty for models the brush must not offer (settlement
  /// props like lamps and clutter) and non-empty for nature the map
  /// may sprinkle (trees, flowers, rocks). Future tags (shore, rocky)
  /// join here without code changes.
  final List<String> legalTerrain;

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

  /// Households this home can hold — its occupancy capacity. A
  /// residential model: filled family by family at check-ins while
  /// residential demand exists. Zero on non-residential models.
  final int households;

  /// Job positions this commerce building offers — its occupancy
  /// capacity, staffed one position per check-in while commercial
  /// demand exists. Zero on non-commerce models.
  final int jobs;

  /// Service category this civic building covers (e.g. 'fire'),
  /// or null on non-service models.
  final String? serviceCategory;

  /// Households one completed service building of this model covers.
  final int serviceCapacity;

  /// The occupancy-flavoured classification: a model is what it
  /// offers. Households make it residential, jobs make it commerce,
  /// a service category makes it a service building; anything else
  /// is plain civic (upkeep drain, no coverage).
  bool get isResidential => households > 0;
  bool get isCommerce => jobs > 0;
  bool get isService => serviceCategory != null;

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
    int? households,
    int? jobs,
    String? serviceCategory,
    int? serviceCapacity,
    List<String>? legalTerrain,
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
    households: households ?? this.households,
    jobs: jobs ?? this.jobs,
    serviceCategory: serviceCategory ?? this.serviceCategory,
    serviceCapacity: serviceCapacity ?? this.serviceCapacity,
    legalTerrain: legalTerrain ?? this.legalTerrain,
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
    'households': households,
    'jobs': jobs,
    if (serviceCategory != null) 'serviceCategory': serviceCategory,
    'serviceCapacity': serviceCapacity,
    if (legalTerrain.isNotEmpty) 'legalTerrain': legalTerrain,
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
        households: json['households'] as int? ?? 0,
        jobs: json['jobs'] as int? ?? 0,
        serviceCategory: (json['serviceCategory'] as String?)?.isEmpty == true
            ? null
            : json['serviceCategory'] as String?,
        serviceCapacity: json['serviceCapacity'] as int? ?? 0,
        legalTerrain: [
          for (final tag in json['legalTerrain'] as List? ?? const [])
            tag as String,
        ],
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
    this.lanes = const {},
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

  /// Directional driving lanes for road tiles, keyed
  /// `direction-lane` (`north-1` … `west-4`, up to four lanes per
  /// direction of travel): each value is the tile's 8×8 subtile
  /// lattice as eight row bytes, in the same indexing as [walkable].
  /// Distinct lanes of one direction are distinct authored bands —
  /// a car centres on whichever it drives and never weaves between
  /// them. A subtile may carry several directions (a crossing,
  /// where cars keep their heading); cars may only enter a subtile
  /// moving in a direction it is painted for, and never reverse.
  /// Empty = the tile carries no traffic; road roles ship blank and
  /// are painted in the editor.
  final Map<String, List<int>> lanes;

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
    Map<String, List<int>>? lanes,
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
    lanes: lanes ?? this.lanes,
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
    if (lanes.isNotEmpty) 'lanes': lanes,
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
      lanes: _parseLanes(json['lanes']),
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

  /// Lane masks per direction, kept exactly as authored so
  /// [validateContentData] can report malformed rows; the vehicle
  /// lattice ignores any mask that is not eight bytes in 0–255.
  static Map<String, List<int>> _parseLanes(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        entry.key as String: [
          for (final row
              in entry.value is List ? entry.value as List : const [])
            row is num ? row.toInt() : -1,
        ],
    };
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
    this.parcelPerPopulationCoins = 0,
    this.migrationPercentPerCheckIn = 2,
    this.employmentPercentPerCheckIn = 5,
    this.waitingHouseholdsCapPercent = 10,
    this.unemploymentTolerancePercent = 10,
    this.jobPullPercentPerCheckIn = 10,
    this.contentmentFloorPercent = 0,
    this.serviceRequirementPopulation = 0,
    this.requiredServiceCategories = const [],
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

  /// Base parcel price at population zero.
  final int parcelBaseCoins;

  /// Added to [parcelBaseCoins] per point of population — expanding
  /// a settlement gets pricier as it grows, pricing each parcel by
  /// the buyer's size rather than the land's distance.
  final int parcelPerPopulationCoins;

  /// Households that may move in per check-in, as a percentage of
  /// population (floored at one). Also the waiting list's refill
  /// rate — growth costs check-ins, not money.
  final int migrationPercentPerCheckIn;

  /// Job positions that may staff per check-in, as a percentage of
  /// population (floored at one). Employment adjusts faster than
  /// migration.
  final int employmentPercentPerCheckIn;

  /// The waiting list's cap, as a percentage of population (floored
  /// at one) — the residential demand bar's scale.
  final int waitingHouseholdsCapPercent;

  /// Unemployment up to this percentage of population (floored at
  /// one household) does not stop the waiting list from refilling —
  /// frontier towns tolerate some joblessness. Above it, migration
  /// pauses until staffing catches up.
  final int unemploymentTolerancePercent;

  /// Job-pull: each surplus job beyond the employed population adds
  /// this percentage of an arrival to the migration budget —
  /// commerce built ahead visibly accelerates migration. Zero
  /// disables the pull.
  final int jobPullPercentPerCheckIn;

  /// Contentment never drops below this percentage — the
  /// no-dead-ends guarantee: unhappy citizens still pay something, so
  /// even a neglected town keeps a trickle of income.
  final int contentmentFloorPercent;

  /// Population below which no service coverage is demanded — the
  /// early game stays pure.
  final int serviceRequirementPopulation;

  /// Service categories whose coverage feeds contentment (e.g.
  /// 'fire', 'police', 'health'). Capacities come from the models
  /// carrying each category.
  final List<String> requiredServiceCategories;

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
    'parcelPerPopulationCoins': parcelPerPopulationCoins,
    'migrationPercentPerCheckIn': migrationPercentPerCheckIn,
    'employmentPercentPerCheckIn': employmentPercentPerCheckIn,
    'waitingHouseholdsCapPercent': waitingHouseholdsCapPercent,
    'unemploymentTolerancePercent': unemploymentTolerancePercent,
    'jobPullPercentPerCheckIn': jobPullPercentPerCheckIn,
    'contentmentFloorPercent': contentmentFloorPercent,
    'serviceRequirementPopulation': serviceRequirementPopulation,
    'requiredServiceCategories': requiredServiceCategories,
    'builderProgression': builderProgression
        .map((step) => step.toJson())
        .toList(),
  };

  EconomyContent copyWith({
    int? startingTreasuryCoins,
    int? roadTileCostCoins,
    int? bridgeTileCostCoins,
    int? parcelBaseCoins,
    int? parcelPerPopulationCoins,
    int? migrationPercentPerCheckIn,
    int? employmentPercentPerCheckIn,
    int? waitingHouseholdsCapPercent,
    int? unemploymentTolerancePercent,
    int? jobPullPercentPerCheckIn,
    int? contentmentFloorPercent,
    int? serviceRequirementPopulation,
    List<String>? requiredServiceCategories,
    List<BuilderProgressionStep>? builderProgression,
  }) => EconomyContent(
    startingTreasuryCoins: startingTreasuryCoins ?? this.startingTreasuryCoins,
    startingBuilderCapacity: startingBuilderCapacity,
    roadTileCostCoins: roadTileCostCoins ?? this.roadTileCostCoins,
    bridgeTileCostCoins: bridgeTileCostCoins ?? this.bridgeTileCostCoins,
    parcelBaseCoins: parcelBaseCoins ?? this.parcelBaseCoins,
    parcelPerPopulationCoins:
        parcelPerPopulationCoins ?? this.parcelPerPopulationCoins,
    migrationPercentPerCheckIn:
        migrationPercentPerCheckIn ?? this.migrationPercentPerCheckIn,
    employmentPercentPerCheckIn:
        employmentPercentPerCheckIn ?? this.employmentPercentPerCheckIn,
    waitingHouseholdsCapPercent:
        waitingHouseholdsCapPercent ?? this.waitingHouseholdsCapPercent,
    unemploymentTolerancePercent:
        unemploymentTolerancePercent ?? this.unemploymentTolerancePercent,
    jobPullPercentPerCheckIn:
        jobPullPercentPerCheckIn ?? this.jobPullPercentPerCheckIn,
    contentmentFloorPercent:
        contentmentFloorPercent ?? this.contentmentFloorPercent,
    serviceRequirementPopulation:
        serviceRequirementPopulation ?? this.serviceRequirementPopulation,
    requiredServiceCategories:
        requiredServiceCategories ?? this.requiredServiceCategories,
    builderProgression: builderProgression ?? this.builderProgression,
  );

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
      parcelPerPopulationCoins: json['parcelPerPopulationCoins'] as int? ?? 0,
      migrationPercentPerCheckIn:
          json['migrationPercentPerCheckIn'] as int? ?? 2,
      employmentPercentPerCheckIn:
          json['employmentPercentPerCheckIn'] as int? ?? 5,
      waitingHouseholdsCapPercent:
          json['waitingHouseholdsCapPercent'] as int? ?? 10,
      unemploymentTolerancePercent:
          json['unemploymentTolerancePercent'] as int? ?? 10,
      jobPullPercentPerCheckIn: json['jobPullPercentPerCheckIn'] as int? ?? 10,
      contentmentFloorPercent: json['contentmentFloorPercent'] as int? ?? 0,
      serviceRequirementPopulation:
          json['serviceRequirementPopulation'] as int? ?? 0,
      requiredServiceCategories: [
        for (final category
            in json['requiredServiceCategories'] as List? ?? const [])
          category as String,
      ],
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
    required this.minScale,
  });

  final double maxAngleRadians;
  final double baseFrequency;
  final int frequencySteps;
  final double frequencyStep;

  /// Camera scale below which swaying sprites draw still. At far
  /// zoom the rock is a sub-pixel shiver, and paying a per-sprite
  /// save/rotate/restore for it is what makes dense vegetation
  /// expensive — so the gate keeps far-zoom frames flat draws.
  /// Zero keeps the sway at every zoom.
  final double minScale;

  Map<String, Object?> toJson() => {
    'maxAngleRadians': maxAngleRadians,
    'baseFrequency': baseFrequency,
    'frequencySteps': frequencySteps,
    'frequencyStep': frequencyStep,
    'minScale': minScale,
  };

  static VegetationSwayContent fromJson(Map<String, Object?> json) =>
      VegetationSwayContent(
        maxAngleRadians: (json['maxAngleRadians']! as num).toDouble(),
        baseFrequency: (json['baseFrequency']! as num).toDouble(),
        frequencySteps: json['frequencySteps']! as int,
        frequencyStep: (json['frequencyStep']! as num).toDouble(),
        minScale: (json['minScale']! as num).toDouble(),
      );
}

class PedestrianContent {
  const PedestrianContent({
    required this.spriteScale,
    required this.walkFrameRate,
    required this.speedMin,
    required this.speedRange,
    required this.populationPercent,
    required this.lateralWanderX,
    required this.lateralWanderY,
  });

  final double spriteScale;
  final double walkFrameRate;
  final double speedMin;
  final double speedRange;

  /// Street life as a percentage of the town's population, floored
  /// at one walker once anyone lives there. Zero turns pedestrians
  /// off; painted sidewalk still bounds the count.
  final int populationPercent;

  final double lateralWanderX;
  final double lateralWanderY;

  Map<String, Object?> toJson() => {
    'spriteScale': spriteScale,
    'walkFrameRate': walkFrameRate,
    'speedMin': speedMin,
    'speedRange': speedRange,
    'populationPercent': populationPercent,
    'lateralWanderX': lateralWanderX,
    'lateralWanderY': lateralWanderY,
  };

  static PedestrianContent fromJson(Map<String, Object?> json) =>
      PedestrianContent(
        spriteScale: (json['spriteScale']! as num).toDouble(),
        walkFrameRate: (json['walkFrameRate']! as num).toDouble(),
        speedMin: (json['speedMin']! as num).toDouble(),
        speedRange: (json['speedRange']! as num).toDouble(),
        // Absent defaults to the seed so content written before the
        // percent existed still loads.
        populationPercent: (json['populationPercent'] as int?) ?? 20,
        lateralWanderX: (json['lateralWanderX']! as num).toDouble(),
        lateralWanderY: (json['lateralWanderY']! as num).toDouble(),
      );
}

/// One vehicle item type in the traffic mix — an art family, the
/// way a catalogue model is one building family.
class CarTypeContent {
  const CarTypeContent({
    required this.id,
    required this.percent,
    this.variants = const [],
  });

  /// The type's id; sprites resolve as `veh_<id>_<variant>_<dir>`
  /// or `veh_<id>_<dir>` when the type has no colour variants.
  final String id;

  /// This type's share of traffic. All types sum to one hundred,
  /// validated.
  final int percent;

  /// Colour variants under the type, like a model's asset roles —
  /// one is rolled per car and held for the trip's life. Empty for
  /// single-colour types.
  final List<String> variants;

  Map<String, Object?> toJson() => {
    'percent': percent,
    if (variants.isNotEmpty) 'variants': variants,
  };

  static CarTypeContent fromJson(String id, Map<String, Object?> json) =>
      CarTypeContent(
        id: id,
        percent: json['percent']! as int,
        variants: [
          for (final value in (json['variants'] as List?) ?? const [])
            value as String,
        ],
      );
}

/// Per-type render tuning for vehicle sprites, authored against
/// the editor's Vehicles page preview: a scale override and
/// per-direction ground anchors for the fine placement no formula
/// can guess from hand-drawn art.
class VehicleRenderContent {
  const VehicleRenderContent({this.scale, this.anchor = const {}});

  /// Draw scale for this type's art; falls back to the cars'
  /// global spriteScale when null.
  final double? scale;

  /// Per-direction ground anchor `[ax, ay]` — fractions of the
  /// sprite's drawn size, ax from the left edge, ay from the top.
  /// Absent directions use the computed default: the ground
  /// centre of tight iso art, a quarter of the box width above
  /// the box bottom.
  final Map<String, (double, double)> anchor;

  Map<String, Object?> toJson() => {
    if (scale != null) 'scale': scale,
    if (anchor.isNotEmpty)
      'anchor': {
        for (final entry in anchor.entries)
          entry.key: [entry.value.$1, entry.value.$2],
      },
  };

  static VehicleRenderContent fromJson(Map<String, Object?> json) =>
      VehicleRenderContent(
        scale: (json['scale'] as num?)?.toDouble(),
        anchor: {
          for (final entry in ((json['anchor'] as Map?) ?? const {}).entries)
            if (entry.value is List && (entry.value as List).length >= 2)
              entry.key as String: (
                ((entry.value as List)[0] as num?)?.toDouble() ?? 0.5,
                ((entry.value as List)[1] as num?)?.toDouble() ?? 0.75,
              ),
        },
      );
}

/// Ambient car traffic: population-scaled slots running errands
/// between buildings, tuned like the pedestrians.
class CarContent {
  const CarContent({
    required this.populationPercent,
    required this.speedMin,
    required this.speedRange,
    required this.spriteScale,
    required this.dwellSeconds,
    required this.respawnDelaySeconds,
    required this.minTripCells,
    required this.types,
    this.render = const {},
  });

  /// Traffic as a percentage of the town's population, floored at
  /// one car once anyone lives there. Zero turns cars off — and an
  /// absent `cars` section reads as zero, so pre-car content loads.
  final int populationPercent;

  /// Driving speed in grid cells per second. One cell/s is 12 m/s
  /// at the 12 m tile — honest in-town pace.
  final double speedMin;

  /// Random extra speed on top of the minimum, so cars overtake.
  final double speedRange;

  /// Draw size multiplier relative to the standard tile unit.
  final double spriteScale;

  /// How long a car sits at each curb — loading up on departure,
  /// parked on arrival.
  final double dwellSeconds;

  /// Pause between a slot's trips, jittered in the sim so slots
  /// desynchronize.
  final double respawnDelaySeconds;

  /// A trip's minimum length in road cells: the planner's BFS
  /// distance map filters ends nearer than this, so degenerate
  /// trips need no rerolls.
  final int minTripCells;

  /// The traffic mix: item types with authored percents (summing
  /// to one hundred) and colour variants.
  final List<CarTypeContent> types;

  /// Per-type render tuning — scale overrides and per-direction
  /// ground anchors, from the Vehicles page. Absent types render
  /// with the global spriteScale and the computed ground-centre
  /// anchor.
  final Map<String, VehicleRenderContent> render;

  Map<String, Object?> toJson() => {
    'populationPercent': populationPercent,
    'speedMin': speedMin,
    'speedRange': speedRange,
    'spriteScale': spriteScale,
    'dwellSeconds': dwellSeconds,
    'respawnDelaySeconds': respawnDelaySeconds,
    'minTripCells': minTripCells,
    'types': {for (final type in types) type.id: type.toJson()},
    if (render.isNotEmpty)
      'render': {
        for (final entry in render.entries) entry.key: entry.value.toJson(),
      },
  };

  static CarContent fromJson(Map<String, Object?> json) => CarContent(
    populationPercent: (json['populationPercent'] as int?) ?? 0,
    speedMin: (json['speedMin'] as num?)?.toDouble() ?? 0.9,
    speedRange: (json['speedRange'] as num?)?.toDouble() ?? 0.3,
    spriteScale: (json['spriteScale'] as num?)?.toDouble() ?? 0.9,
    dwellSeconds: (json['dwellSeconds'] as num?)?.toDouble() ?? 2.5,
    respawnDelaySeconds: (json['respawnDelaySeconds'] as num?)?.toDouble() ?? 4,
    minTripCells: (json['minTripCells'] as int?) ?? 10,
    types: [
      for (final entry in ((json['types'] as Map?) ?? const {}).entries)
        CarTypeContent.fromJson(
          entry.key as String,
          (entry.value as Map).cast<String, Object?>(),
        ),
    ],
    render: {
      for (final entry in ((json['render'] as Map?) ?? const {}).entries)
        entry.key as String: VehicleRenderContent.fromJson(
          (entry.value as Map).cast<String, Object?>(),
        ),
    },
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
    required this.cars,
    required this.unownedLandWash,
    required this.tileGrid,
  });

  final double ambientTimeScale;
  final VegetationSwayContent vegetationSway;
  final PedestrianContent pedestrians;
  final CarContent cars;
  final UnownedLandWashContent unownedLandWash;
  final TileGridContent tileGrid;

  Map<String, Object?> toJson() => {
    'ambientTimeScale': ambientTimeScale,
    'vegetationSway': vegetationSway.toJson(),
    'pedestrians': pedestrians.toJson(),
    'cars': cars.toJson(),
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
    cars: CarContent.fromJson(
      (json['cars'] as Map?)?.cast<String, Object?>() ?? const {},
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
/// One authored nature prop on the terrain map — a row in the save's
/// Props-table shape (the sheet's columns as named JSON fields), so
/// purchasing its parcel is a byte-identical copy into the save. The
/// id is derived, exactly like the codec derives it: nothing stored.
/// Nature rows are the map's pristine vegetation: read-only in game,
/// live for unowned parcels, and materialized into the save the
/// moment their parcel is purchased.
class TerrainProp {
  const TerrainProp({
    required this.catalogueId,
    required this.cell,
    required this.subtileX,
    required this.subtileY,
    this.assetRole,
    this.facing,
  });

  final String catalogueId;
  final CellCoord cell;
  final int subtileX;
  final int subtileY;

  /// Rolled once by the brush at paint time and stored, so the game's
  /// frontier render and the purchase copy draw the identical sprite.
  final String? assetRole;
  final String? facing;

  Map<String, Object?> toJson() => {
    'catalogueId': catalogueId,
    'x': cell.column,
    'y': cell.row,
    'subtileX': subtileX,
    'subtileY': subtileY,
    if (assetRole != null) 'assetRole': assetRole,
    if (facing != null) 'facing': facing,
  };

  static TerrainProp fromJson(Map<String, Object?> json) => TerrainProp(
    catalogueId: json['catalogueId']! as String,
    cell: CellCoord(json['x']! as int, json['y']! as int),
    subtileX: json['subtileX']! as int,
    subtileY: json['subtileY']! as int,
    assetRole: json['assetRole'] as String?,
    facing: json['facing'] as String?,
  );
}

class TerrainContent {
  const TerrainContent({
    required this.generatorVersion,
    required this.parcels,
    this.tiles = const {},
    this.props = const [],
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

  /// Authored nature props — the map's pristine vegetation, painted
  /// by the editor's nature brush. The game shows them on unowned
  /// parcels and copies them into the save when a parcel is
  /// purchased; rows inside owned parcels are ignored (the save is
  /// the truth there). See [TerrainProp] for the row shape.
  final List<TerrainProp> props;

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
    if (props.isNotEmpty) 'props': [for (final prop in props) prop.toJson()],
  };

  static TerrainContent fromJson(Map<String, Object?> json) {
    final raw = json['parcels']! as Map;
    final rawTiles = json['tiles'];
    final rawProps = json['props'];
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
      props: rawProps is List
          ? [
              for (final row in rawProps)
                TerrainProp.fromJson((row as Map).cast<String, Object?>()),
            ]
          : const [],
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

  // Nature props: rows must name brushable decorations, stand on land
  // their model's legalTerrain covers, and never share a subtile. The
  // subtile lattice is the props' 8×8 grid (propSubtilesPerAxis lives
  // in the world layer; content mirrors its range).
  final modelsById = {for (final model in catalogue) model.id: model};
  final natureAnchors = <String>{};
  for (final prop in terrain.props) {
    final model = modelsById[prop.catalogueId];
    if (model == null) {
      error(
        'Nature prop at ${prop.cell.key} names unknown model '
        '"${prop.catalogueId}".',
      );
      continue;
    }
    if (model.kind != StructureKind.decoration) {
      error(
        'Nature prop at ${prop.cell.key} names "${prop.catalogueId}" — '
        'only decorations can be painted as nature.',
      );
    }
    final parcel = terrain.parcels[parcelForCell(prop.cell)];
    if (parcel == null) {
      error(
        'Nature prop at ${prop.cell.key} sits on an unauthored parcel — '
        'author the parcel before painting nature on it.',
      );
      continue;
    }
    final resolved = terrain.tiles[prop.cell] ?? parcel;
    if (!model.legalTerrain.contains('land') || resolved != TerrainKind.grass) {
      error(
        'Nature prop at ${prop.cell.key} cannot stand on '
        '${resolved.name} — "${prop.catalogueId}" needs land.',
      );
    }
    if (prop.subtileX < 0 ||
        prop.subtileX > 7 ||
        prop.subtileY < 0 ||
        prop.subtileY > 7) {
      error('Nature prop at ${prop.cell.key} has a subtile outside 0..7.');
    }
    if (!natureAnchors.add(
      '${prop.cell.key}:${prop.subtileX}.${prop.subtileY}',
    )) {
      error(
        'Two nature props share the subtile at ${prop.cell.key} '
        '(${prop.subtileX}, ${prop.subtileY}).',
      );
    }
  }
  for (final model in catalogue) {
    if (model.legalTerrain.isNotEmpty &&
        model.kind != StructureKind.decoration) {
      error(
        '${model.id}: legalTerrain is the nature brush\'s vocabulary — '
        'only decorations may carry it.',
      );
    }
    for (final tag in model.legalTerrain) {
      if (tag != 'land') {
        error(
          '${model.id}: unknown legalTerrain tag "$tag" — land is the '
          'only tag today.',
        );
      }
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
    if (model.households < 0) {
      error('${model.id}: households must not be negative.');
    }
    if (model.jobs < 0) {
      error('${model.id}: jobs must not be negative.');
    }
    if (model.households > 0 && model.jobs > 0) {
      error(
        '${model.id}: a model cannot be both residential (households) '
        'and commercial (jobs).',
      );
    }
    if (model.serviceCapacity < 0) {
      error('${model.id}: service capacity must not be negative.');
    }
    if (model.serviceCategory != null && model.serviceCapacity < 1) {
      error(
        '${model.id}: service category "${model.serviceCategory}" needs '
        'a capacity of at least one household.',
      );
    }
    if (model.serviceCategory == null && model.serviceCapacity > 0) {
      error('${model.id}: service capacity without a service category.');
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
    if (sprite.lanes.isNotEmpty) {
      if (sprite.category != 'roads' && sprite.category != 'bridges') {
        warning(
          'Sprite "${entry.key}": only road and bridge tiles carry '
          'driving lanes — cars read them from those roles.',
        );
      }
      for (final lane in sprite.lanes.entries) {
        final parts = lane.key.split('-');
        final laneNumber = parts.length == 2 ? int.tryParse(parts[1]) : null;
        if (parts.length != 2 ||
            !const ['north', 'east', 'south', 'west'].contains(parts[0]) ||
            laneNumber == null ||
            laneNumber < 1 ||
            laneNumber > 4) {
          error(
            'Sprite "${entry.key}": lane "${lane.key}" must name a '
            'direction and lane number, like "east-2" (lanes 1–4).',
          );
          continue;
        }
        if (lane.value.length != 8) {
          error(
            'Sprite "${entry.key}": the ${lane.key} lane must be '
            'exactly eight row bytes, one per lattice row.',
          );
        } else if (lane.value.any((row) => row < 0 || row > 255)) {
          error(
            'Sprite "${entry.key}": the ${lane.key} lane row bytes must '
            'stay within 0–255.',
          );
        }
      }
      // Lanes of one direction must not share subtiles — a subtile
      // belongs to at most one lane per direction (cross-direction
      // overlap is a crossing and is fine).
      for (final direction in const ['north', 'east', 'south', 'west']) {
        final sameDirection = [
          for (final lane in sprite.lanes.entries)
            if (lane.key.startsWith('$direction-')) lane.value,
        ];
        for (var i = 0; i < sameDirection.length; i++) {
          for (var j = i + 1; j < sameDirection.length; j++) {
            final a = sameDirection[i];
            final b = sameDirection[j];
            if (a.length != 8 ||
                b.length != 8 ||
                List.generate(
                  8,
                  (y) =>
                      a[y].clamp(0, 255).toInt() & b[y].clamp(0, 255).toInt(),
                ).any((row) => row != 0)) {
              warning(
                'Sprite "${entry.key}": lanes of one direction must not '
                'share subtiles — "$direction" lanes overlap.',
              );
            }
          }
        }
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
  if (economy.parcelPerPopulationCoins < 0) {
    error('The parcel population surcharge must not be negative.');
  }
  if (economy.migrationPercentPerCheckIn < 0 ||
      economy.employmentPercentPerCheckIn < 0 ||
      economy.waitingHouseholdsCapPercent < 0 ||
      economy.unemploymentTolerancePercent < 0 ||
      economy.jobPullPercentPerCheckIn < 0) {
    error('Demand percentages must not be negative.');
  }
  if (economy.contentmentFloorPercent < 0 ||
      economy.contentmentFloorPercent > 100) {
    error('The contentment floor must be a percentage within [0, 100].');
  }
  if (economy.serviceRequirementPopulation < 0) {
    error('The service requirement population must not be negative.');
  }
  final categories = economy.requiredServiceCategories;
  if (categories.toSet().length != categories.length) {
    error('Required service categories must be unique.');
  }
  for (final category in categories) {
    if (category.isEmpty) {
      error('Required service categories must not be empty strings.');
    }
  }
  for (final category in categories) {
    final covered = catalogue.any(
      (model) => model.enabled && model.serviceCategory == category,
    );
    if (!covered) {
      warning(
        'Required service category "$category" has no enabled model '
        'providing it — contentment can never reach 100%.',
      );
    }
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
  if (ambience.vegetationSway.minScale < 0 ||
      ambience.vegetationSway.minScale > 2) {
    error('Vegetation sway zoom gate must be within [0, 2].');
  }
  if (ambience.pedestrians.spriteScale <= 0 ||
      ambience.pedestrians.walkFrameRate <= 0 ||
      ambience.pedestrians.speedMin <= 0 ||
      ambience.pedestrians.speedRange < 0 ||
      ambience.pedestrians.populationPercent < 0) {
    error('Pedestrian ambience values are out of range.');
  }
  final cars = ambience.cars;
  if (cars.populationPercent < 0 ||
      cars.speedMin <= 0 ||
      cars.speedRange < 0 ||
      cars.spriteScale <= 0 ||
      cars.dwellSeconds < 0 ||
      cars.respawnDelaySeconds < 0 ||
      cars.minTripCells < 0) {
    error('Car ambience values are out of range.');
  }
  if (cars.types.isEmpty) {
    if (cars.populationPercent > 0) {
      error('Car traffic needs at least one vehicle type.');
    }
  } else if (cars.types.any((type) => type.percent < 0) ||
      cars.types.fold(0, (sum, type) => sum + type.percent) != 100) {
    error('Car type percents must be non-negative and sum to 100.');
  }
  for (final entry in cars.render.entries) {
    if (!cars.types.any((type) => type.id == entry.key)) {
      error('Car render tuning "${entry.key}" names no vehicle type.');
      continue;
    }
    if (entry.value.scale != null && entry.value.scale! <= 0) {
      error('Car render tuning "${entry.key}": scale must be positive.');
    }
    for (final anchor in entry.value.anchor.entries) {
      if (!const ['NE', 'NW', 'SE', 'SW'].contains(anchor.key)) {
        error(
          'Car render tuning "${entry.key}": anchor direction '
          '"${anchor.key}" is not one of NE, NW, SE, SW.',
        );
        continue;
      }
      final (ax, ay) = anchor.value;
      if (ax < -0.5 || ax > 1.5 || ay < -0.5 || ay > 1.5) {
        error(
          'Car render tuning "${entry.key}": the ${anchor.key} anchor '
          'must stay within −0.5…1.5 of the sprite.',
        );
      }
    }
  }
  return issues;
}

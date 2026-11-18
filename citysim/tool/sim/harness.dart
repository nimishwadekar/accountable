// Player-simulation harness: a scripted persona plays a fresh city
// from founding through the real reducer — the same quotes, wallet
// rules, and check-in heartbeat the shipped game runs, minus the
// rendering. Every simulated day is logged as one JSON record, so
// the batch runner can aggregate cash flow, pacing, and the dead
// check-ins that make a player feel stuck or rich.
//
// Not part of the app or tests; drive it through
// tool/sim/simulate_batch.dart.

import 'dart:math' as math;

import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:citysim/world/terrain_provider.dart';
import 'package:citysim/world/world_content.dart';
import 'package:citysim/world/world_queries.dart';
import 'package:citysim/world/world_reducer.dart';
import 'package:citysim/world/world_rules.dart';
import 'package:citysim/world/world_state.dart';

/// One action attempt, successful or refused — refusals are feel
/// data too: "the game told me no" is a player experience.
class SimAction {
  SimAction(this.op, this.detail, {this.ok = true, this.reason, this.coins});

  final String op;
  final String detail;
  final bool ok;
  final String? reason;

  /// Coins the action moved, when it moved any.
  final int? coins;

  Map<String, Object?> toJson() => {
    'op': op,
    'detail': detail,
    if (coins != null) 'coins': coins,
    'ok': ok,
    if (reason != null) 'reason': reason,
  };
}

/// How a build attempt resolved.
enum BuildOutcome { built, roadPlanned, cannotAfford, noSpace, notUnlocked }

/// The player policy: what to want, and how often to show up. The
/// harness handles the motor skills — where a building fits and how
/// its frontage road gets planned — and the persona supplies the
/// strategy and the habits.
abstract class PlayerPersona {
  String get id;
  String get name;

  /// Whether the player opens the game on this calendar day.
  bool checksInToday(int day, math.Random rng);

  /// Decisions for the day, made after the check-in report — the
  /// order a real session runs in: the report greets the player,
  /// then they build.
  void playDay(SimHarness harness);
}

/// One simulated day, logged for the report.
class DayRecord {
  DayRecord({
    required this.day,
    required this.dateKey,
    required this.credited,
    required this.coins,
    required this.population,
    required this.employed,
    required this.waiting,
    required this.residentialCapacity,
    required this.jobCapacity,
    required this.parcels,
    required this.roads,
    required this.structures,
    required this.constructions,
    required this.milestone,
    required this.actions,
    required this.dead,
    this.taxes,
    this.upkeep,
    this.net,
    this.contentment,
    this.arrived = 0,
    this.completions = 0,
    this.nextParcelPrice,
  });

  final int day;
  final String dateKey;
  final bool credited;
  final int coins;
  final int population;
  final int employed;
  final int waiting;
  final int residentialCapacity;
  final int jobCapacity;
  final int parcels;
  final int roads;
  final int structures;
  final int constructions;
  final String milestone;
  final List<SimAction> actions;
  final bool dead;
  final int? taxes;
  final int? upkeep;
  final int? net;
  final int? contentment;
  final int arrived;
  final int completions;
  final int? nextParcelPrice;

  Map<String, Object?> toJson() => {
    'day': day,
    'date': dateKey,
    'credited': credited,
    'coins': coins,
    'population': population,
    'employed': employed,
    'waiting': waiting,
    'residentialCapacity': residentialCapacity,
    'jobCapacity': jobCapacity,
    'parcels': parcels,
    'roads': roads,
    'structures': structures,
    'constructions': constructions,
    'milestone': milestone,
    'dead': dead,
    if (taxes != null) 'taxes': taxes,
    if (upkeep != null) 'upkeep': upkeep,
    if (net != null) 'net': net,
    if (contentment != null) 'contentment': contentment,
    if (arrived > 0) 'arrived': arrived,
    if (completions > 0) 'completions': completions,
    if (nextParcelPrice != null) 'nextParcelPrice': nextParcelPrice,
    'actions': [for (final action in actions) action.toJson()],
  };
}

/// A candidate placement found by the scanner: where the building
/// would sit, how it is turned, and which road tiles its door side
/// still needs before the game will accept it.
class _Placement {
  _Placement({
    required this.origin,
    required this.turns,
    required this.footprint,
    required this.missingRoadCells,
  });

  final CellCoord origin;
  final int turns;
  final List<CellCoord> footprint;
  final List<CellCoord> missingRoadCells;
}

/// The headless game: one city, one persona, one seed, replayed
/// through the real rules. All state transitions go through the
/// production reducer functions — the harness never re-implements a
/// rule or a price, so a simulation cannot drift from the game.
class SimHarness {
  SimHarness({
    required ContentBundle bundle,
    required this.persona,
    required this.seed,
    DateTime? startDate,
  }) : content = bundle,
       state = newParcelWorldState(
         content: bundle,
         seed: seed,
         today: startDate ?? DateTime.utc(2026, 11, 16),
       ),
       terrain = ContentTerrainProvider(bundle.terrain),
       rng = math.Random(seed * 7919 + 13);

  final ContentBundle content;
  final TerrainProvider terrain;
  final PlayerPersona persona;
  final int seed;
  final math.Random rng;
  ParcelWorldState state;

  final List<DayRecord> records = [];
  final List<SimAction> _actionsToday = [];
  int _day = 0;

  /// Set when today's build attempts found no room even with new
  /// roads — the persona's cue that it is time to buy land.
  bool noSpaceThisSession = false;

  // ------------------------------------------------------------
  // Capacities and projections — completed plus in-flight, the way
  // a player sees a town with construction sites standing.
  // ------------------------------------------------------------

  int get residentialCapacityPlanned {
    var capacity = 0;
    for (final structure in state.structures) {
      final model = content.structure(structure.catalogueId);
      if (model?.isResidential ?? false) capacity += model!.population;
    }
    for (final job in state.constructions) {
      final model = _structureModel(job);
      if (model?.isResidential ?? false) capacity += model!.population;
    }
    return capacity;
  }

  int get jobCapacityPlanned {
    var capacity = 0;
    for (final structure in state.structures) {
      final model = content.structure(structure.catalogueId);
      if (model?.isCommerce ?? false) capacity += model!.jobs;
    }
    for (final job in state.constructions) {
      final model = _structureModel(job);
      if (model?.isCommerce ?? false) capacity += model!.jobs;
    }
    return capacity;
  }

  /// Service coverage for a category, counting sites in flight —
  /// the planner's view, not the ledger's completed-only one.
  double serviceCoveragePlanned(String category) {
    if (state.population <= 0) return 1;
    var capacity = 0;
    for (final structure in state.structures) {
      final model = content.structure(structure.catalogueId);
      if (model?.serviceCategory == category) {
        capacity += model?.serviceCapacity ?? 0;
      }
    }
    for (final job in state.constructions) {
      final model = _structureModel(job);
      if (model?.serviceCategory == category) {
        capacity += model?.serviceCapacity ?? 0;
      }
    }
    return (capacity / state.population).clamp(0.0, 1.0);
  }

  StructureDefinition? _structureModel(WorldConstruction job) {
    if (job.kind != WorldConstructionKind.structure) return null;
    return job.catalogueId == null ? null : content.structure(job.catalogueId!);
  }

  /// Owned, dry, unbuilt cells — the town's room to grow into.
  /// Nature props do not count as built: the player clears them for
  /// free. The persona's cue for when it is time to buy land.
  int get freeLandCells {
    final queries = WorldQueries(state, terrain);
    var free = 0;
    for (final parcel in state.parcels) {
      for (final cell in parcel.coord.cells(state.parcelSize)) {
        if (!queries.terrainAt(cell).isLand) continue;
        if (queries.roadsByCell.containsKey(cell)) continue;
        if (queries.structuresByCell.containsKey(cell)) continue;
        if (queries.reservedCells.contains(cell)) continue;
        free++;
      }
    }
    return free;
  }

  // ------------------------------------------------------------
  // Land.
  // ------------------------------------------------------------

  /// The price of a parcel, or null when it cannot be bought at all
  /// (fog, not adjacent, already owned). A silent probe — scanning
  /// with it never logs.
  int? parcelPrice(ParcelCoord coord) {
    try {
      return quoteParcelPurchase(state, content, terrain, coord).price;
    } on WorldRuleViolation {
      return null;
    }
  }

  /// Charted parcels that touch the town.
  Set<ParcelCoord> expansionCandidates() {
    final owned = state.parcels.map((parcel) => parcel.coord).toSet();
    final candidates = <ParcelCoord>{};
    for (final parcel in owned) {
      for (final neighbor in parcel.neighbors) {
        if (owned.contains(neighbor)) continue;
        if (terrain
                .sample(neighbor.origin(state.parcelSize), state.seed)
                .kind ==
            TerrainKind.fog) {
          continue;
        }
        candidates.add(neighbor);
      }
    }
    return candidates;
  }

  /// Land cells in a charted parcel — founding and expansion both
  /// prefer buildable ground.
  int landCells(ParcelCoord coord) {
    var land = 0;
    for (final cell in coord.cells(state.parcelSize)) {
      if (terrain.sample(cell, state.seed).isLand) land++;
    }
    return land;
  }

  /// Picks a founding parcel: the best of a shortlist of scouted
  /// spots, so planners survey the whole map and casual players
  /// take the first decent patch they happen to see. Falls back to
  /// a full scan when the shortlist drew all shoreline.
  ParcelCoord chooseFoundingParcel({required int shortlist}) {
    final charted =
        content.terrain.parcels.keys
            .where(
              (coord) =>
                  terrain
                      .sample(coord.origin(state.parcelSize), state.seed)
                      .kind !=
                  TerrainKind.fog,
            )
            .toList()
          ..shuffle(rng);
    final best = _bestFounding(charted.take(shortlist));
    return (best ?? _bestFounding(charted)) ??
        content.terrain.parcels.keys.first;
  }

  ParcelCoord? _bestFounding(Iterable<ParcelCoord> coords) {
    ParcelCoord? best;
    var bestLand = -1;
    for (final coord in coords) {
      final land = landCells(coord);
      if (land >= foundingLandCells && land > bestLand) {
        best = coord;
        bestLand = land;
      }
    }
    return best;
  }

  bool foundAt(ParcelCoord coord) {
    try {
      state = purchaseParcel(state, content, terrain, coord);
      _act(
        SimAction('found', 'parcel (${coord.x},${coord.y}), free', coins: 0),
      );
      return true;
    } on WorldRuleViolation catch (e) {
      _act(
        SimAction(
          'found',
          'parcel (${coord.x},${coord.y})',
          ok: false,
          reason: e.message,
        ),
      );
      return false;
    }
  }

  /// Buys the best adjacent parcel if the treasury covers it.
  bool buyBestAdjacentParcel() {
    ParcelCoord? best;
    var bestLand = -1;
    final candidates = [...expansionCandidates()]
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final coord in candidates) {
      final land = landCells(coord);
      if (land > bestLand) {
        best = coord;
        bestLand = land;
      }
    }
    if (best == null) return false;
    final price = parcelPrice(best);
    if (price == null) return false;
    if (state.coins < price) {
      _act(
        SimAction(
          'parcel',
          'parcel (${best.x},${best.y})',
          ok: false,
          reason: 'You need $price coins for this purchase.',
        ),
      );
      return false;
    }
    try {
      state = purchaseParcel(state, content, terrain, best);
      _act(SimAction('parcel', 'parcel (${best.x},${best.y})', coins: price));
      return true;
    } on WorldRuleViolation catch (e) {
      _act(
        SimAction(
          'parcel',
          'parcel (${best.x},${best.y})',
          ok: false,
          reason: e.message,
        ),
      );
      return false;
    }
  }

  /// The next parcel's price, for the day record — the number a
  /// player stares at while saving up.
  int? nextParcelPrice() {
    ParcelCoord? best;
    var bestLand = -1;
    for (final coord in expansionCandidates()) {
      final land = landCells(coord);
      if (land > bestLand) {
        best = coord;
        bestLand = land;
      }
    }
    return best == null ? null : parcelPrice(best);
  }

  // ------------------------------------------------------------
  // Building.
  // ------------------------------------------------------------

  /// Tries to place a model: scans outward from the town's centre
  /// for a spot whose footprint fits, preferring sides already
  /// lined with road. When no spot is directly buildable, plans the
  /// frontage road for the best pending spot and lets a later day
  /// place the building once the tiles creep in — exactly the loop
  /// a player runs: extend the street, then line it with buildings.
  BuildOutcome attemptBuild(String catalogueId, {required bool splitStrokes}) {
    final definition = content.structure(catalogueId);
    if (definition == null ||
        !definition.enabled ||
        !state.unlockedCatalogueIds.contains(catalogueId)) {
      return BuildOutcome.notUnlocked;
    }
    final queries = WorldQueries(state, terrain);
    _Placement? pending;
    for (final origin in _scanOrigins()) {
      // Cheap pre-filter: every footprint contains its origin cell,
      // so an occupied origin can never host anything. In a dense
      // town this skips nearly the whole scan.
      if (queries.structuresByCell.containsKey(origin) ||
          queries.roadsByCell.containsKey(origin) ||
          queries.reservedCells.contains(origin)) {
        continue;
      }
      final placement = _placementFor(definition, origin, queries);
      if (placement == null) continue;
      if (placement.missingRoadCells.isEmpty) {
        if (_place(catalogueId, placement)) return BuildOutcome.built;
        continue;
      }
      pending ??= placement;
    }
    if (pending == null) {
      noSpaceThisSession = true;
      return BuildOutcome.noSpace;
    }
    final planned = planRoads(
      pending.missingRoadCells,
      splitStrokes: splitStrokes,
    );
    return planned ? BuildOutcome.roadPlanned : BuildOutcome.cannotAfford;
  }

  bool _place(String catalogueId, _Placement placement) {
    final cleared = _clearProps(placement.footprint);
    final name = content.structure(catalogueId)!.name;
    try {
      state = startStructureConstruction(
        state,
        content,
        terrain,
        catalogueId: catalogueId,
        origin: placement.origin,
        quarterTurns: placement.turns,
      );
      _act(
        SimAction(
          'build',
          '$name at (${placement.origin.column},${placement.origin.row})'
              '${cleared > 0 ? ' · cleared $cleared nature props' : ''}',
          coins: 0,
        ),
      );
      return true;
    } on WorldRuleViolation catch (e) {
      _act(SimAction('build', name, ok: false, reason: e.message));
      return false;
    }
  }

  /// Picks up the nature props standing on the cells — the player's
  /// land-clearing chore before every build on wild ground.
  int _clearProps(List<CellCoord> cells) {
    final blocking = cells.toSet();
    var cleared = 0;
    for (final prop in [...state.props]) {
      if (!blocking.contains(prop.cell)) continue;
      state = pickUpProp(state, content, propId: prop.id);
      cleared++;
    }
    return cleared;
  }

  /// Candidate origins, scanning outward from the town's centre so
  /// towns grow compactly. Deterministic: the same town state
  /// always suggests the same next spot. Cached across build
  /// attempts — the order only changes when land is bought.
  List<CellCoord>? _scanCache;
  int _scanCacheParcels = -1;

  List<CellCoord> _scanOrigins() {
    if (state.parcels.isEmpty) return const [];
    if (_scanCache != null && _scanCacheParcels == state.parcels.length) {
      return _scanCache!;
    }
    var centreColumn = 0.0;
    var centreRow = 0.0;
    for (final parcel in state.parcels) {
      final origin = parcel.coord.origin(state.parcelSize);
      centreColumn += origin.column + state.parcelSize / 2;
      centreRow += origin.row + state.parcelSize / 2;
    }
    centreColumn /= state.parcels.length;
    centreRow /= state.parcels.length;
    final centre = CellCoord(centreColumn.round(), centreRow.round());
    final origins = <CellCoord>[
      for (final parcel in state.parcels)
        for (final cell in parcel.coord.cells(state.parcelSize)) cell,
    ];
    final distance = <CellCoord, int>{
      for (final cell in origins) cell: _distance2(cell, centre),
    };
    origins.sort((a, b) {
      final difference = distance[a]!.compareTo(distance[b]!);
      if (difference != 0) return difference;
      if (a.row != b.row) return a.row.compareTo(b.row);
      return a.column.compareTo(b.column);
    });
    _scanCache = origins;
    _scanCacheParcels = state.parcels.length;
    return origins;
  }

  int _distance2(CellCoord a, CellCoord b) =>
      (a.column - b.column) * (a.column - b.column) +
      (a.row - b.row) * (a.row - b.row);

  /// A placement option at [origin] over the four door sides,
  /// preferring the side whose road frontage is closest to done.
  _Placement? _placementFor(
    StructureDefinition definition,
    CellCoord origin,
    WorldQueries queries,
  ) {
    const sides = ['north', 'east', 'south', 'west'];
    final sideOptions = <(int, _Placement)>[];
    for (final side in sides) {
      final turns = footprintTurnsFor(definition, side);
      final footprint = structureFootprint(
        definition,
        origin,
        quarterTurns: turns,
      );
      var fits = true;
      for (final cell in footprint) {
        if (!queries.ownsCell(cell) ||
            !queries.terrainAt(cell).isLand ||
            queries.roadsByCell.containsKey(cell) ||
            queries.structuresByCell.containsKey(cell) ||
            queries.reservedCells.contains(cell)) {
          fits = false;
          break;
        }
      }
      if (!fits) continue;
      final edge = _outsideEdge(footprint, side);
      if (edge.isEmpty) continue;
      var lined = true;
      final missing = <CellCoord>[];
      var buildable = true;
      for (final cell in edge) {
        if (queries.roadsByCell.containsKey(cell)) continue;
        lined = false;
        missing.add(cell);
        if (!queries.ownsCell(cell) ||
            !queries.terrainAt(cell).isLand ||
            queries.structuresByCell.containsKey(cell) ||
            queries.reservedCells.contains(cell)) {
          buildable = false;
        }
      }
      if (lined) {
        return _Placement(
          origin: origin,
          turns: turns,
          footprint: footprint,
          missingRoadCells: const [],
        );
      }
      if (!buildable) continue;
      // Prefer the side with the fewest tiles still to lay.
      sideOptions.add((
        missing.length,
        _Placement(
          origin: origin,
          turns: turns,
          footprint: footprint,
          missingRoadCells: missing,
        ),
      ));
    }
    if (sideOptions.isEmpty) return null;
    sideOptions.sort((a, b) => a.$1.compareTo(b.$1));
    return sideOptions.first.$2;
  }

  /// The cells just outside one footprint edge — where its frontage
  /// road must run.
  List<CellCoord> _outsideEdge(List<CellCoord> footprint, String side) {
    var minColumn = footprint.first.column;
    var maxColumn = footprint.first.column;
    var minRow = footprint.first.row;
    var maxRow = footprint.first.row;
    for (final cell in footprint) {
      if (cell.column < minColumn) minColumn = cell.column;
      if (cell.column > maxColumn) maxColumn = cell.column;
      if (cell.row < minRow) minRow = cell.row;
      if (cell.row > maxRow) maxRow = cell.row;
    }
    final cells = <CellCoord>[];
    if (side == 'north') {
      for (var column = minColumn; column <= maxColumn; column++) {
        cells.add(CellCoord(column, minRow - 1));
      }
    } else if (side == 'south') {
      for (var column = minColumn; column <= maxColumn; column++) {
        cells.add(CellCoord(column, maxRow + 1));
      }
    } else if (side == 'west') {
      for (var row = minRow; row <= maxRow; row++) {
        cells.add(CellCoord(minColumn - 1, row));
      }
    } else {
      for (var row = minRow; row <= maxRow; row++) {
        cells.add(CellCoord(maxColumn + 1, row));
      }
    }
    return cells;
  }

  // ------------------------------------------------------------
  // Roads.
  // ------------------------------------------------------------

  /// Plans the given road cells as contiguous strokes. With
  /// [splitStrokes], each tile becomes its own job — every road job
  /// lays one tile per check-in, so parallel strokes deliver in
  /// parallel. The savvy-player trick, and a pacing question worth
  /// measuring.
  bool planRoads(List<CellCoord> cells, {required bool splitStrokes}) {
    if (cells.isEmpty) return true;
    // Clear the ground before quoting: nature props on a tile make
    // the quote refuse, and a player clears the brush before buying
    // the road anyway.
    _clearProps(cells);
    final strokes = <List<CellCoord>>[
      for (final run in _contiguousRuns(cells))
        if (splitStrokes)
          for (final cell in run) [cell]
        else
          run,
    ];
    var total = 0;
    final priced = <(List<CellCoord>, int)>[];
    for (final stroke in strokes) {
      try {
        final quote = quoteRoadStretch(state, content, terrain, cells: stroke);
        priced.add((stroke, quote.price));
        total += quote.price;
      } on WorldRuleViolation catch (e) {
        _act(
          SimAction(
            'roads',
            '${stroke.length}-tile stretch',
            ok: false,
            reason: e.message,
          ),
        );
        return false;
      }
    }
    if (total > state.coins) {
      _act(
        SimAction(
          'roads',
          '${cells.length} tiles',
          ok: false,
          reason: 'You need $total coins for this purchase.',
        ),
      );
      return false;
    }
    for (final (stroke, price) in priced) {
      state = planRoadStretch(state, content, terrain, cells: stroke);
      _act(SimAction('roads', '${stroke.length} tiles', coins: price));
    }
    return true;
  }

  List<List<CellCoord>> _contiguousRuns(List<CellCoord> cells) {
    final runs = <List<CellCoord>>[];
    for (final cell in cells) {
      if (runs.isNotEmpty && runs.last.last.neighbors.contains(cell)) {
        runs.last.add(cell);
      } else {
        runs.add([cell]);
      }
    }
    return runs;
  }

  // ------------------------------------------------------------
  // The day loop.
  // ------------------------------------------------------------

  /// Runs [totalDays] calendar days. Each day: the calendar rolls,
  /// the player may open the game (persona cadence), the check-in
  /// heart beats if they do, and then they act.
  List<DayRecord> run(int totalDays) {
    while (_day < totalDays) {
      _day++;
      state = advanceWorldDays(state, 1);
      // A fresh slate every day, credited or not — a skipped day
      // must never inherit the previous session's action log.
      _actionsToday.clear();
      noSpaceThisSession = false;
      final showsUp = persona.checksInToday(_day, rng);
      var credited = false;
      int? taxes;
      int? upkeep;
      int? net;
      int? contentment;
      var arrived = 0;
      var completions = 0;
      if (showsUp && canCheckInWorldToday(state)) {
        state = checkInWorldForToday(state, content);
        credited = true;
        final report = state.events.lastWhere(
          (event) =>
              event.kind == 'check-in' &&
              event.payload['creditedDate'] == state.dateKey,
        );
        final payload = report.payload;
        taxes = (payload['taxes'] as num?)?.toInt();
        upkeep = (payload['upkeep'] as num?)?.toInt();
        net = (payload['net'] as num?)?.toInt();
        contentment = (payload['contentment'] as num?)?.toInt();
        arrived = (payload['populationArrived'] as num?)?.toInt() ?? 0;
        completions = (payload['completions'] as List?)?.length ?? 0;
        persona.playDay(this);
      }
      final acted = _actionsToday.any((action) => action.ok);
      records.add(
        DayRecord(
          day: _day,
          dateKey: state.dateKey,
          credited: credited,
          coins: state.coins,
          population: state.population,
          employed: state.employedPopulation,
          waiting: state.waitingPopulation,
          residentialCapacity: residentialCapacityPlanned,
          jobCapacity: jobCapacityPlanned,
          parcels: state.parcels.length,
          roads: state.roads.length,
          structures: state.structures.length,
          constructions: state.constructions.length,
          milestone: state.progressionMilestoneId ?? 'none',
          actions: List.unmodifiable(_actionsToday),
          dead: credited && arrived == 0 && completions == 0 && !acted,
          taxes: taxes,
          upkeep: upkeep,
          net: net,
          contentment: contentment,
          arrived: arrived,
          completions: completions,
          nextParcelPrice: nextParcelPrice(),
        ),
      );
      if (state.coins < 0) {
        throw StateError('treasury went negative on day $_day');
      }
    }
    return records;
  }

  void _act(SimAction action) => _actionsToday.add(action);
}

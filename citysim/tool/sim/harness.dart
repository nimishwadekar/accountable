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

  /// Founds the city: the hall needs a 3×3 of dry land plus a dry
  /// front cell, all inside the parcel. The scouted parcel hosts it
  /// or the founder drives on — a full scan, the way a player
  /// passes a valley with no room.
  bool foundAt(ParcelCoord coord) {
    if (_tryFoundAt(coord)) return true;
    final charted =
        content.terrain.parcels.keys
            .where(
              (c) =>
                  terrain.sample(c.origin(state.parcelSize), state.seed).kind !=
                  TerrainKind.fog,
            )
            .toList()
          ..shuffle(rng);
    for (final candidate in charted) {
      if (_tryFoundAt(candidate)) return true;
    }
    _act(
      SimAction(
        'found',
        'parcel (${coord.x},${coord.y})',
        ok: false,
        reason: 'no charted parcel can host the city hall',
      ),
    );
    return false;
  }

  bool _tryFoundAt(ParcelCoord coord) {
    final root = rootHallModel(content);
    if (root == null) return false;
    final size = state.parcelSize;
    final northWest = coord.origin(size);
    // The hall prefers the rim with open country ahead of its front:
    // the whole parcel stays buildable behind it, and the front road
    // starts the town's main street outward. Score every legal
    // (spot, facing) by the open run ahead and found on the best.
    CellCoord? bestOrigin;
    String? bestFacing;
    var bestRun = -1;
    for (var dy = 0; dy <= size - 3; dy++) {
      for (var dx = 0; dx <= size - 3; dx++) {
        final origin = CellCoord(northWest.column + dx, northWest.row + dy);
        for (final facing in const ['south', 'east', 'north', 'west']) {
          final CityFoundingQuote quote;
          try {
            quote = quoteCityFounding(
              state,
              content,
              terrain,
              origin: origin,
              facing: facing,
            );
          } on WorldRuleViolation {
            continue;
          }
          final run = _openRunAhead(quote.frontCell, facing);
          if (run > bestRun) {
            bestRun = run;
            bestOrigin = origin;
            bestFacing = facing;
          }
        }
      }
    }
    if (bestOrigin == null || bestFacing == null) return false;
    state = foundCity(
      state,
      content,
      terrain,
      origin: bestOrigin,
      facing: bestFacing,
    );
    _act(
      SimAction(
        'found',
        'hall at (${bestOrigin.column},${bestOrigin.row}) facing '
            '$bestFacing',
        coins: 0,
      ),
    );
    return true;
  }

  /// Consecutive land cells from [front] in [facing]'s direction —
  /// the open ground the main street can grow into. Water ends the
  /// run; unowned parcels do not (they can be bought).
  int _openRunAhead(CellCoord front, String facing) {
    final step = switch (facing) {
      'north' => const CellCoord(0, -1),
      'south' => const CellCoord(0, 1),
      'east' => const CellCoord(1, 0),
      _ => const CellCoord(-1, 0),
    };
    var run = 0;
    var cursor = front;
    for (var i = 0; i < state.parcelSize * 2; i++) {
      cursor = CellCoord(cursor.column + step.column, cursor.row + step.row);
      if (!terrain.sample(cursor, state.seed).isLand) break;
      run++;
    }
    return run;
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
    // The outside connection once per attempt: only roads linked to
    // the hall's front road carry buildings.
    final connected = connectedRoadCells(state, content);
    _Placement? pending;
    List<CellCoord>? pendingConnector;
    var pendingCost = 1 << 30;
    for (final origin in _scanOrigins()) {
      // Cheap pre-filter: every footprint contains its origin cell,
      // so an occupied origin can never host anything. In a dense
      // town this skips nearly the whole scan.
      if (queries.structuresByCell.containsKey(origin) ||
          queries.roadsByCell.containsKey(origin) ||
          queries.reservedCells.contains(origin)) {
        continue;
      }
      final placement = _placementFor(definition, origin, queries, connected);
      if (placement == null) continue;
      if (placement.missingRoadCells.isEmpty) {
        if (_place(catalogueId, placement)) return BuildOutcome.built;
        continue;
      }
      // A frontage that touches no connected tile needs a connector —
      // and one that has no path is skipped outright: an orphan road
      // carries no buildings and is pure waste. Among the rest, the
      // cheapest total paving wins, the street a player would extend.
      final touches = placement.missingRoadCells.any(
        (cell) =>
            connected.contains(cell) || cell.neighbors.any(connected.contains),
      );
      List<CellCoord>? connector;
      if (!touches) {
        connector = _connectingStroke(
          placement.missingRoadCells.first,
          connected,
          avoid: placement.footprint,
        );
        if (connector == null) continue;
      }
      final cost = placement.missingRoadCells.length + (connector?.length ?? 0);
      final roadPlan = [...placement.missingRoadCells, ...?connector];
      // Every consuming act must leave the network breathing: the
      // footprint and its roads together may never take the last
      // free cells touching the connected streets, or nothing can
      // ever attach again.
      if (!_keepsBreathing(
        placement.footprint.toSet(),
        roadPlan,
        queries,
        connected,
      )) {
        continue;
      }
      if (cost < pendingCost) {
        pendingCost = cost;
        pending = placement;
        pendingConnector = connector;
      }
    }
    if (pending == null) {
      // Nothing placeable at any price: extend a street into open
      // ground instead of giving up — the street-first loop every
      // player runs.
      if (extendStreet()) return BuildOutcome.roadPlanned;
      noSpaceThisSession = true;
      return BuildOutcome.noSpace;
    }
    // A connector that outprices the wallet is paved the player's
    // way: extend the street in affordable pieces, and the frontage
    // arrives with it.
    final tileCost = content.economy.roadTileCostCoins;
    if (pendingCost * tileCost > state.coins) {
      return extendStreet()
          ? BuildOutcome.roadPlanned
          : BuildOutcome.cannotAfford;
    }
    final planned = planRoads([
      ...pending.missingRoadCells,
      ...?pendingConnector,
    ], splitStrokes: splitStrokes);
    return planned ? BuildOutcome.roadPlanned : BuildOutcome.cannotAfford;
  }

  /// Extends a street from the connected network into open ground:
  /// the straight run ahead of some escape cell. A street is at
  /// least three tiles or nothing — paving one tile the moment the
  /// wallet crosses one tile's price spends every scrap of income on
  /// stubs that front nothing, where saving a few days buys a run
  /// buildings can actually line.
  bool extendStreet({int minTiles = 3, int maxTiles = 6}) {
    final queries = WorldQueries(state, terrain);
    final connected = connectedRoadCells(state, content);
    if (connected.isEmpty) return false;
    bool paveable(CellCoord cell) =>
        !queries.roadsByCell.containsKey(cell) &&
        !queries.structuresByCell.containsKey(cell) &&
        !queries.reservedCells.contains(cell) &&
        queries.ownsCell(cell) &&
        queries.terrainAt(cell).isLand;
    final affordable = (state.coins ~/ content.economy.roadTileCostCoins).clamp(
      0,
      maxTiles,
    );
    if (affordable < minTiles) return false;
    List<CellCoord>? best;
    for (final road in connected) {
      for (final start in road.neighbors) {
        if (!paveable(start)) continue;
        for (final direction in [
          const CellCoord(1, 0),
          const CellCoord(-1, 0),
          const CellCoord(0, 1),
          const CellCoord(0, -1),
        ]) {
          final run = <CellCoord>[start];
          var cursor = start;
          while (run.length < affordable) {
            final next = CellCoord(
              cursor.column + direction.column,
              cursor.row + direction.row,
            );
            if (!paveable(next)) break;
            run.add(next);
            cursor = next;
          }
          if (best == null || run.length > best.length) {
            best = run;
          }
        }
      }
    }
    if (best == null || best.isEmpty) return false;
    if (!_keepsBreathing(const {}, best, queries, connected)) return false;
    return planRoads(best, splitStrokes: false);
  }

  /// Whether the network still breathes after [footprint] and
  /// [newRoads] land: at least two free owned land cells remain
  /// adjacent to the (grown) connected streets — the places a future
  /// street can attach. Lined placements guard themselves inside
  /// [_placementFor]; everything else that consumes ground passes
  /// through here.
  bool _keepsBreathing(
    Set<CellCoord> footprint,
    List<CellCoord> newRoads,
    WorldQueries queries,
    Set<CellCoord> connected,
  ) {
    final blocked = {...footprint, ...newRoads};
    bool free(CellCoord cell) =>
        !blocked.contains(cell) &&
        !newRoads.contains(cell) &&
        !queries.roadsByCell.containsKey(cell) &&
        !queries.structuresByCell.containsKey(cell) &&
        !queries.reservedCells.contains(cell) &&
        queries.ownsCell(cell) &&
        queries.terrainAt(cell).isLand;
    final escape = <CellCoord>{
      for (final road in {...connected, ...newRoads})
        for (final neighbour in road.neighbors)
          if (free(neighbour)) neighbour,
    };
    return escape.length >= 2;
  }

  /// The shortest connector of new road cells linking [from] back to
  /// the connected network, paving around whatever already stands —
  /// structures, rising sites, roads that are not the network's, and
  /// the cells in [avoid]. Null when no free path exists.
  List<CellCoord>? _connectingStroke(
    CellCoord from,
    Set<CellCoord> connected, {
    List<CellCoord> avoid = const [],
  }) {
    final queries = WorldQueries(state, terrain);
    final blocked = avoid.toSet();
    bool paveable(CellCoord cell) =>
        !queries.roadsByCell.containsKey(cell) &&
        !queries.structuresByCell.containsKey(cell) &&
        !queries.reservedCells.contains(cell) &&
        !blocked.contains(cell) &&
        queries.ownsCell(cell) &&
        queries.terrainAt(cell).isLand;
    final queue = <CellCoord>[from];
    final cameFrom = <CellCoord, CellCoord>{};
    final seen = {from};
    while (queue.isNotEmpty) {
      final cell = queue.removeAt(0);
      if (cell != from && cell.neighbors.any(connected.contains)) {
        final path = <CellCoord>[cell];
        var cursor = cell;
        while (true) {
          final previous = cameFrom[cursor];
          if (previous == null || previous == from) break;
          cursor = previous;
          path.add(cursor);
        }
        return path.reversed.toList();
      }
      for (final neighbour in cell.neighbors) {
        if (seen.contains(neighbour) || !paveable(neighbour)) continue;
        seen.add(neighbour);
        cameFrom[neighbour] = cell;
        queue.add(neighbour);
      }
    }
    return null;
  }

  /// Whether [catalogueId] has a spot on the existing connected
  /// street — lined, connected, no paving needed.
  bool canLineUp(String catalogueId) {
    final definition = content.structure(catalogueId);
    if (definition == null ||
        !definition.enabled ||
        !state.unlockedCatalogueIds.contains(catalogueId)) {
      return false;
    }
    final queries = WorldQueries(state, terrain);
    final connected = connectedRoadCells(state, content);
    for (final origin in _scanOrigins()) {
      if (queries.structuresByCell.containsKey(origin) ||
          queries.roadsByCell.containsKey(origin) ||
          queries.reservedCells.contains(origin)) {
        continue;
      }
      final placement = _placementFor(definition, origin, queries, connected);
      if (placement != null && placement.missingRoadCells.isEmpty) {
        return true;
      }
    }
    return false;
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
      state = demolishProp(state, content, propId: prop.id);
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
    Set<CellCoord> connected,
  ) {
    const sides = ['north', 'east', 'south', 'west'];
    final sideOptions = <(int, _Placement)>[];
    // The network's escape cells: free ground still touching a
    // connected road, where a future street can attach. A town that
    // builds on all of them walls itself in — nothing can connect
    // again — so placements leave two open (the cross-street-gap
    // rule every reviewer learned the hard way).
    final escape = <CellCoord>{
      for (final road in queries.roadsByCell.keys)
        if (connected.contains(road))
          for (final neighbour in road.neighbors)
            if (!queries.roadsByCell.containsKey(neighbour) &&
                !queries.structuresByCell.containsKey(neighbour) &&
                !queries.reservedCells.contains(neighbour) &&
                queries.ownsCell(neighbour) &&
                queries.terrainAt(neighbour).isLand)
              neighbour,
    };
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
        // A bridge bank is not frontage — it falls to the missing
        // list, and being a road it can never be paved, so the side
        // is simply unusable.
        if (queries.roadsByCell.containsKey(cell) &&
            !queries.bridgeBankCells.contains(cell)) {
          continue;
        }
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
        // A lined side must also belong to the outside connection —
        // a road beside the building is not enough, it must be THE
        // road, linked back to the hall's front.
        if (!edge.any(connected.contains)) continue;
        // And it must not seal the last escape cells: a footprint on
        // the network's last free touchpoints walls the town in.
        final consumed = footprint.where(escape.contains).length;
        if (consumed > 0 && escape.length - consumed < 2) continue;
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
    // A frontage plus its connector can name a cell twice — the
    // connector's path may cross the frontage it serves. Strokes
    // share every named cell exactly once.
    final seen = <CellCoord>{};
    cells = [
      for (final cell in cells)
        if (seen.add(cell)) cell,
    ];
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

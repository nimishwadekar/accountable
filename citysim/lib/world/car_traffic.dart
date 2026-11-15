import 'dart:math' as math;

import '../content/content_models.dart' show CarContent, StructureKind;
import 'coordinates.dart';
import 'pedestrian_lattice.dart' show bridgeSurfaceLift, pedestrianBridgeRoles;
import 'world_state.dart' show ParcelWorldState, PlacedStructure;

/// Road cells cars may drive: every completed road — bridge banks
/// included, they are road tiles — plus completed bridges' water
/// cells, whose decks continue the road across the water. Half-built
/// crossings carry no traffic until they finish.
Set<CellCoord> carDrivableCells(ParcelWorldState state) => {
  for (final road in state.roads) road.cell,
  for (final bridge in state.bridges) ...bridge.waterCells,
};

/// Drivable cells that front a structure: the four-neighbours of
/// its footprint on the car graph. A corner lot fronts two sides;
/// every front counts, in a deterministic order.
List<CellCoord> carFrontCells(
  PlacedStructure structure,
  Set<CellCoord> drivable,
) {
  final fronts = <CellCoord>{};
  for (final cell in structure.footprint) {
    for (final neighbor in cell.neighbors) {
      if (drivable.contains(neighbor)) fronts.add(neighbor);
    }
  }
  return fronts.toList()..sort();
}

/// How many car slots a town of [population] runs: traffic as a
/// percentage of the town's people, floored at one car once anyone
/// lives there. Zero percent turns cars off.
int carTargetCount(int population, CarContent cars) {
  if (cars.populationPercent <= 0 || population <= 0) return 0;
  return math.max(1, (population * cars.populationPercent / 100).floor());
}

/// Picks a vehicle item type by its authored percent — the table
/// sums to one hundred, validated — then a colour variant
/// uniformly, the way a placed structure rolls its asset role.
(String, String?) pickCarModel(CarContent cars, math.Random random) {
  if (cars.types.isEmpty) return ('', null);
  var roll = random.nextInt(100);
  var type = cars.types.last;
  for (final candidate in cars.types) {
    roll -= candidate.percent;
    if (roll < 0) {
      type = candidate;
      break;
    }
  }
  final variant = type.variants.isEmpty
      ? null
      : type.variants[random.nextInt(type.variants.length)];
  return (type.id, variant);
}

/// The pack's iso compass for a grid heading: north (row −1) is
/// screen NE, east (col +1) SE, south (row +1) SW, west (col −1)
/// NW — the same mapping the pedestrian walk cycles use.
String carCompassForHeading(int dx, int dy) => switch ((dx, dy)) {
  (0, -1) => 'NE',
  (1, 0) => 'SE',
  (0, 1) => 'SW',
  (-1, 0) => 'NW',
  _ => 'SE',
};

/// Asset path of one vehicle sprite: variant-less types name no
/// colour segment.
String carAssetPath(String type, String? variant, String compass) =>
    variant == null
    ? 'assets/vehicles/veh_${type}_$compass.png'
    : 'assets/vehicles/veh_${type}_${variant}_$compass.png';

class _CarReach {
  final Map<CellCoord, int> distance = {};
  final Map<CellCoord, CellCoord> parent = {};
}

/// Multi-source breadth-first search across the drivable cells:
/// distances count road cells from the nearest source, parents
/// rebuild the path a car drives.
_CarReach _breadthFirstSearch(
  Set<CellCoord> drivable,
  Iterable<CellCoord> sources,
) {
  final reach = _CarReach();
  final queue = <CellCoord>[];
  for (final source in sources) {
    if (!drivable.contains(source)) continue;
    if (reach.distance.containsKey(source)) continue;
    reach.distance[source] = 0;
    queue.add(source);
  }
  var head = 0;
  while (head < queue.length) {
    final cell = queue[head++];
    for (final neighbor in cell.neighbors) {
      if (reach.distance.containsKey(neighbor)) continue;
      if (!drivable.contains(neighbor)) continue;
      reach.distance[neighbor] = reach.distance[cell]! + 1;
      reach.parent[neighbor] = cell;
      queue.add(neighbor);
    }
  }
  return reach;
}

/// Grid direction from a front cell toward the building it fronts —
/// where a dwelling car pulls to park.
(int, int) _curbDirection(PlacedStructure structure, CellCoord front) {
  for (final neighbor in front.neighbors) {
    if (structure.footprint.contains(neighbor)) {
      return (neighbor.column - front.column, neighbor.row - front.row);
    }
  }
  return (0, 0); // Unreachable: fronts are footprint-adjacent.
}

/// One car's errand: the road cells it drives between two curbs,
/// plus the grid directions those curbs pull toward.
class CarTripPlan {
  CarTripPlan({
    required this.path,
    required this.startCurb,
    required this.endCurb,
  });

  /// The cells driven, from the start building's front to the end
  /// building's front. Consecutive cells are always four-adjacent,
  /// and shortest paths never double back.
  final List<CellCoord> path;
  final (int, int) startCurb;
  final (int, int) endCurb;
}

/// Plans one errand: a start building, a home-biased end building
/// at least `minTripCells` of road away — the BFS distance map is
/// the filter, so degenerate pairs need no rerolls — and the
/// shortest path between their fronts. Null when the town cannot
/// host a trip yet: too few buildings, or none far enough apart.
CarTripPlan? planCarTrip(
  ParcelWorldState state,
  CarContent cars,
  math.Random random,
) {
  final drivable = carDrivableCells(state);
  final fronted = <(PlacedStructure, List<CellCoord>)>[];
  for (final structure in state.structures) {
    if (structure.kind != StructureKind.building) continue;
    final fronts = carFrontCells(structure, drivable);
    if (fronts.isNotEmpty) fronted.add((structure, fronts));
  }
  if (fronted.isEmpty) return null;

  // A bounded number of starts: most towns host a trip from any
  // building, but an isolated one may not — try another.
  for (var attempt = 0; attempt < 8; attempt++) {
    final start = fronted[random.nextInt(fronted.length)];
    final reach = _breadthFirstSearch(drivable, start.$2);
    // End candidates: other buildings whose nearest front sits at
    // least minTripCells of road away from the start's fronts.
    final ends = <(PlacedStructure, CellCoord)>[];
    for (final entry in fronted) {
      if (identical(entry.$1, start.$1)) continue;
      CellCoord? nearest;
      var best = -1;
      for (final front in entry.$2) {
        final distance = reach.distance[front];
        if (distance == null) continue;
        if (nearest == null || distance < best) {
          nearest = front;
          best = distance;
        }
      }
      if (nearest != null && best >= cars.minTripCells) {
        ends.add((entry.$1, nearest));
      }
    }
    if (ends.isEmpty) continue;
    // Home-biased errands: mostly cross-kind pairs — home to shop,
    // shop to home — with any-to-any as variety. A population on a
    // structure marks its building residential.
    var pool = ends;
    if (random.nextDouble() < 0.7) {
      final startIsHome = start.$1.population > 0;
      final biased = [
        for (final end in ends)
          if ((end.$1.population > 0) != startIsHome) end,
      ];
      if (biased.isNotEmpty) pool = biased;
    }
    final end = pool[random.nextInt(pool.length)];
    // Rebuild the path: the end's front back to a start front.
    final path = <CellCoord>[end.$2];
    CellCoord? step = reach.parent[path.last];
    while (step != null) {
      path.add(step);
      step = reach.parent[step];
    }
    if (path.length < 2) continue;
    final forward = path.reversed.toList();
    return CarTripPlan(
      path: forward,
      startCurb: _curbDirection(start.$1, forward.first),
      endCurb: _curbDirection(end.$1, forward.last),
    );
  }
  return null;
}

/// One visible car: what it is, where it stands in continuous grid
/// space, which way it faces, and how far through its trip it is.
/// Pure data for the renderer — the sim mutates it in place, the
/// way the pedestrian sim moves its walkers.
class CarActor {
  CarActor({
    required this.type,
    required this.variant,
    required this.gridColumn,
    required this.gridRow,
    required this.headingDx,
    required this.headingDy,
    required this.dwelling,
    required this.distanceCells,
    required this.tripCells,
    required this.startCurb,
    required this.endCurb,
  });

  final String type;
  final String? variant;

  /// Continuous grid coordinates — the car's unoffset centre on the
  /// road. The renderer adds lane and curb offsets in world space.
  double gridColumn;
  double gridRow;

  /// Facing in grid steps (one of the four axis unit deltas).
  int headingDx;
  int headingDy;

  /// True while parked at a curb — the departure and arrival
  /// pauses.
  bool dwelling;

  /// Distance driven so far and the trip's total, in road cells —
  /// the renderer blends curb-to-lane offsets over the first and
  /// last stretch.
  double distanceCells;
  final double tripCells;
  final (int, int) startCurb;
  final (int, int) endCurb;
}

enum _CarPhase { planning, dwellingStart, driving, dwellingEnd, cooldown }

class _CarSlot {
  _CarPhase phase = _CarPhase.planning;
  double timer = 0;
  CarActor? actor;
  CarTripPlan? trip;

  /// This trip's speed in cells per second.
  double speed = 1;
  double distance = 0;
}

/// Render-only ambient car traffic: population-scaled slots, each
/// running errands between buildings — spawn at a curb, dwell,
/// drive the planned path, dwell at the destination, cooldown, then
/// a new trip. Deliberately excluded from world state and saves,
/// exactly like the pedestrian sim: ambience never affects
/// gameplay, and a reload simply restarts the traffic.
class CarTrafficSim {
  final List<CarActor> actors = [];
  final List<_CarSlot> _slots = [];
  int _population = -1;
  int _drivableCount = -1;
  int _structureCount = -1;
  double _lastSeconds = 0;
  math.Random _random = math.Random();
  Map<CellCoord, String> _bridgeRoles = const {};
  double _deckLift = 0;

  /// Advances the traffic. Population changes resize the slot
  /// count; road, bridge, and building changes reshape trips — all
  /// three happen on check-ins, so new slots and fronts join
  /// mid-session while running trips keep their paths.
  void update(
    double seconds,
    ParcelWorldState state,
    CarContent cars, {
    double deckLift = 0,
  }) {
    var drivableCount = state.roads.length;
    for (final bridge in state.bridges) {
      drivableCount += bridge.waterCells.length;
    }
    if (state.population != _population ||
        drivableCount != _drivableCount ||
        state.structures.length != _structureCount) {
      _population = state.population;
      _drivableCount = drivableCount;
      _structureCount = state.structures.length;
      _bridgeRoles = state.bridges.isEmpty
          ? const {}
          : pedestrianBridgeRoles(state);
      _deckLift = deckLift;
      _random = math.Random(state.seed + state.population);
      _reconcileSlots(state, cars);
      _collectActors();
      _lastSeconds = seconds;
      return;
    }
    final dt = (seconds - _lastSeconds).clamp(0.0, 0.25);
    _lastSeconds = seconds;
    if (dt <= 0) return;
    for (final slot in _slots) {
      _advanceSlot(slot, dt, state, cars);
    }
    _collectActors();
  }

  void _reconcileSlots(ParcelWorldState state, CarContent cars) {
    final target = carTargetCount(state.population, cars);
    while (_slots.length > target) {
      _slots.removeLast();
    }
    while (_slots.length < target) {
      // New slots enter cooldown on staggered timers, so a load
      // trickle cars in over the first seconds instead of
      // spawning the whole fleet at once.
      _slots.add(
        _CarSlot()
          ..phase = _CarPhase.cooldown
          ..timer = (_slots.length % 8) * 0.8 + _random.nextDouble() * 1.2,
      );
    }
  }

  void _collectActors() {
    actors.clear();
    for (final slot in _slots) {
      final actor = slot.actor;
      if (actor != null) actors.add(actor);
    }
  }

  void _advanceSlot(
    _CarSlot slot,
    double dt,
    ParcelWorldState state,
    CarContent cars,
  ) {
    switch (slot.phase) {
      case _CarPhase.planning:
        _planTrip(slot, state, cars);
      case _CarPhase.dwellingStart:
        slot.timer -= dt;
        if (slot.timer <= 0) {
          slot.phase = _CarPhase.driving;
          slot.actor?.dwelling = false;
        }
      case _CarPhase.driving:
        slot.distance += slot.speed * dt;
        final hops = slot.trip!.path.length - 1;
        if (slot.distance >= hops) {
          slot.distance = hops.toDouble();
          _positionActor(slot);
          final actor = slot.actor!;
          actor.dwelling = true;
          slot.phase = _CarPhase.dwellingEnd;
          slot.timer = cars.dwellSeconds;
        } else {
          _positionActor(slot);
        }
      case _CarPhase.dwellingEnd:
        slot.timer -= dt;
        if (slot.timer <= 0) {
          slot.actor = null;
          slot.trip = null;
          slot.phase = _CarPhase.cooldown;
          // Jittered so slot cycles desynchronize.
          slot.timer = cars.respawnDelaySeconds * (0.5 + _random.nextDouble());
        }
      case _CarPhase.cooldown:
        slot.timer -= dt;
        if (slot.timer <= 0) {
          slot.phase = _CarPhase.planning;
        }
    }
  }

  void _planTrip(_CarSlot slot, ParcelWorldState state, CarContent cars) {
    if (cars.types.isEmpty) {
      slot.phase = _CarPhase.cooldown;
      slot.timer = cars.respawnDelaySeconds;
      return;
    }
    final trip = planCarTrip(state, cars, _random);
    if (trip == null) {
      // The town cannot host a trip yet — roads and buildings are
      // still growing. Retry after the respawn delay.
      slot.phase = _CarPhase.cooldown;
      slot.timer = cars.respawnDelaySeconds;
      return;
    }
    final (type, variant) = pickCarModel(cars, _random);
    final path = trip.path;
    slot
      ..trip = trip
      ..speed = cars.speedMin + _random.nextDouble() * cars.speedRange
      ..distance = 0
      ..phase = _CarPhase.dwellingStart
      ..timer = cars.dwellSeconds
      ..actor = CarActor(
        type: type,
        variant: variant,
        gridColumn: path.first.column.toDouble(),
        gridRow: path.first.row.toDouble(),
        headingDx: path[1].column - path[0].column,
        headingDy: path[1].row - path[0].row,
        dwelling: true,
        distanceCells: 0,
        tripCells: (path.length - 1).toDouble(),
        startCurb: trip.startCurb,
        endCurb: trip.endCurb,
      );
  }

  void _positionActor(_CarSlot slot) {
    final path = slot.trip!.path;
    final hops = path.length - 1;
    final d = slot.distance.clamp(0.0, hops.toDouble());
    final segment = math.min(d.floor(), hops - 1);
    final fraction = (d - segment).clamp(0.0, 1.0);
    final a = path[segment];
    final b = path[segment + 1];
    final actor = slot.actor!;
    actor.gridColumn = a.column + (b.column - a.column) * fraction;
    actor.gridRow = a.row + (b.row - a.row) * fraction;
    actor.headingDx = b.column - a.column;
    actor.headingDy = b.row - a.row;
    actor.distanceCells = d;
  }

  /// World-px lift of a car standing at [cell] at grid fraction
  /// (fx, fy), both −0.5…0.5 from the cell centre: ramps climb
  /// toward the deck, decks sit at full lift, roads lift nothing.
  double surfaceLift(CellCoord cell, double fx, double fy) {
    final role = _bridgeRoles[cell];
    if (role == null) return 0;
    return bridgeSurfaceLift(role, fx, fy, _deckLift);
  }

  /// Painter's depth for a car, matching how walkers sort: ground
  /// cars keep the plain ground depth; cars on bridge tiles climb
  /// the same per-cell ramp so they never dip under adjacent art.
  double sortDepth(CarActor actor) {
    final cell = CellCoord(actor.gridColumn.floor(), actor.gridRow.floor());
    final fx = actor.gridColumn - cell.column;
    final fy = actor.gridRow - cell.row;
    final cellDepth = cell.column + cell.row;
    if (!_bridgeRoles.containsKey(cell)) {
      return cellDepth + fx + fy - 1;
    }
    return cellDepth + 0.06 + (fx + fy) * 0.55;
  }
}

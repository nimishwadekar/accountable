import 'dart:math' as math;

import '../content/content_models.dart' show CarContent, StructureKind;
import 'coordinates.dart' show CellCoord;
import 'pedestrian_lattice.dart'
    show LatticeSpot, pedestrianBridgeRoles, pedestrianRoadCells;
import 'vehicle_lattice.dart'
    show
        VehicleLattice,
        blankVehicleLattice,
        deltaForDirection,
        directionForDelta,
        oppositeDirection;
import 'world_state.dart'
    show ParcelWorldState, PlacedStructure, propSubtilesPerAxis;

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

class _LaneReach {
  /// Distance in subtile hops from a source, per (spot, heading)
  /// state — heading matters because crossings only accept cars
  /// already moving their way.
  final Map<(LatticeSpot, int), int> distance = {};
  final Map<(LatticeSpot, int), (LatticeSpot, int)> parent = {};

  /// The best distance any heading reaches a spot at.
  int distanceAt(LatticeSpot spot) {
    var best = -1;
    for (final direction in const [1, 2, 4, 8]) {
      final d = distance[(spot, direction)];
      if (d != null && (best < 0 || d < best)) best = d;
    }
    return best;
  }

  /// The state a path rebuild starts from: the heading that reaches
  /// [spot] soonest.
  (LatticeSpot, int)? bestStateAt(LatticeSpot spot) {
    (LatticeSpot, int)? best;
    var bestDistance = -1;
    for (final direction in const [1, 2, 4, 8]) {
      final state = (spot, direction);
      final d = distance[state];
      if (d != null && (bestDistance < 0 || d < bestDistance)) {
        best = state;
        bestDistance = d;
      }
    }
    return best;
  }
}

/// Breadth-first search over the lane lattice's driving states: a
/// car facing [heading] may step in direction δ when δ is not the
/// reverse of its heading and the destination subtile is painted
/// for δ — so it passes through crossings moving its own way, turns
/// by stepping onto a single-direction lane, and never reverses.
_LaneReach _laneSearch(VehicleLattice lattice, List<LatticeSpot> sources) {
  final reach = _LaneReach();
  final queue = <(LatticeSpot, int)>[];
  for (final spot in sources) {
    final dirs = lattice.dirsAt(spot.cell, spot.x, spot.y);
    for (final direction in const [1, 2, 4, 8]) {
      if ((dirs & direction) == 0) continue;
      final state = (spot, direction);
      if (reach.distance.containsKey(state)) continue;
      reach.distance[state] = 0;
      queue.add(state);
    }
  }
  var head = 0;
  while (head < queue.length) {
    final (spot, heading) = queue[head++];
    for (final direction in const [1, 2, 4, 8]) {
      if (direction == oppositeDirection(heading)) continue;
      final (dx, dy) = deltaForDirection(direction);
      final next = lattice.surface.step(spot, dx, dy);
      if (next == null) continue;
      if ((lattice.dirsAt(next.cell, next.x, next.y) & direction) == 0) {
        continue;
      }
      final state = (next, direction);
      if (reach.distance.containsKey(state)) continue;
      reach.distance[state] = reach.distance[(spot, heading)]! + 1;
      reach.parent[state] = (spot, heading);
      queue.add(state);
    }
  }
  return reach;
}

/// Plans one errand on the lane lattice: a start building, a
/// home-biased end building whose nearest front spot sits at least
/// `minTripCells` of road away — the BFS distance map is the
/// filter, so degenerate pairs need no rerolls — and the lane path
/// between their fronts. Null when the town cannot host a trip:
/// unpainted roads, too few fronted buildings, or none far enough
/// apart.
List<LatticeSpot>? planCarTrip(
  ParcelWorldState state,
  CarContent cars,
  VehicleLattice lattice,
  math.Random random,
) {
  if (lattice.isEmpty) return null;
  final fronted = <(PlacedStructure, List<LatticeSpot>)>[];
  for (final structure in state.structures) {
    if (structure.kind != StructureKind.building) continue;
    final fronts = lattice.frontSpots(structure.footprint);
    if (fronts.isNotEmpty) fronted.add((structure, fronts));
  }
  if (fronted.isEmpty) return null;

  var minHops = cars.minTripCells * propSubtilesPerAxis;
  if (minHops < 1) minHops = 1;
  // A bounded number of starts: most towns host a trip from any
  // building, but an isolated one may not — try another.
  for (var attempt = 0; attempt < 8; attempt++) {
    final start = fronted[random.nextInt(fronted.length)];
    final reach = _laneSearch(lattice, start.$2);
    final ends = <(PlacedStructure, LatticeSpot, int)>[];
    for (final entry in fronted) {
      if (identical(entry.$1, start.$1)) continue;
      LatticeSpot? nearest;
      var best = -1;
      for (final front in entry.$2) {
        final distance = reach.distanceAt(front);
        if (distance < 0) continue;
        if (nearest == null || distance < best) {
          nearest = front;
          best = distance;
        }
      }
      // NOTE (2026-11): equal-distance ties break to the
      // first-sorted front spot, so parallel same-direction lanes
      // pile their traffic into one lane. Seeded tie-breaking
      // spreads it — deferred until multi-lane roads arrive.
      if (nearest != null && best >= minHops) {
        ends.add((entry.$1, nearest, best));
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
    // Rebuild the path from the end's best state back to a source.
    final endState = reach.bestStateAt(end.$2);
    if (endState == null) continue;
    final spots = <LatticeSpot>[end.$2];
    var previous = reach.parent[endState];
    while (previous != null) {
      spots.add(previous.$1);
      previous = reach.parent[previous];
    }
    if (spots.length < 2) continue;
    return spots.reversed.toList();
  }
  return null;
}

/// One visible car: what it is, and where it stands on the lane
/// lattice — the segment being driven and the progress along it,
/// exactly like a pedestrian. Pure data for the renderer; the sim
/// mutates it in place.
class CarActor {
  CarActor({
    required this.type,
    required this.variant,
    required LatticeSpot spot,
    required this.headingDx,
    required this.headingDy,
  }) : from = spot,
       to = spot;

  final String type;
  final String? variant;

  /// Position on the lane lattice: the segment being driven and
  /// the progress along it. While dwelling, both ends are the
  /// stop's spot.
  LatticeSpot from;
  LatticeSpot to;
  double progress = 0;

  /// Facing in grid steps — always the direction of the segment
  /// being driven, so a car faces the lane it is on.
  int headingDx;
  int headingDy;

  /// Lateral lane centring, in grid-cell fractions: the car sits at
  /// the centre of the lane it drives, whatever its painted
  /// thickness. The renderer turns this into a world offset.
  double laneOffsetCol = 0;
  double laneOffsetRow = 0;

  /// True while stopped on the lane at a curb — the departure and
  /// arrival pauses.
  bool dwelling = true;
}

/// One car's standings in the painter-order contest resolution.
/// [actor] is the actor-list index the slot draws — how the
/// resolved order writes back into the painter sequence — and the
/// rest is what the pairwise rule compares: the mid-body depth
/// [anchor], the deep corner's (col+row) gain over it
/// [halfDiag], whether the car stands on a bridge cell anywhere
/// along its drawn extent [touchesBridge], and the drawn box on
/// screen. Built by the renderer in painter order.
class CarPainterSlot {
  CarPainterSlot({
    required this.actor,
    required this.anchor,
    required this.halfDiag,
    required this.touchesBridge,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final int actor;
  final double anchor;
  final double halfDiag;
  final bool touchesBridge;
  final double left;
  final double top;
  final double right;
  final double bottom;
}

/// Painter order among the cars, resolving the pairs a single sort
/// key cannot. The global sort keys every car by its deep corner —
/// the (col+row)-max point of its drawn footprint — which is
/// exactly the depth that must clear a bridge tile's art or the
/// leading end of a car being passed. But a pass has two ends: at
/// the trailing ends the deep-corner keys of unequal cars (a
/// sedan against a bus) disagree with the ground under the overlap
/// by the difference of their spans, so the long car's nose rides
/// over the short car's tail through much of every pass. When two
/// cars' sprites actually overlap on screen and their depth spans
/// interleave — neither body unambiguously deeper — their centres
/// decide instead. Cars touching a bridge are exempt: there the
/// deep-corner key is load-bearing — it is what keeps a climbing
/// car above the deck pieces while its anchor is still behind
/// them — so the key order stands exactly as the depth sort gave
/// it. [slots] must arrive in painter order — the order the scene
/// is about to draw — and the returned list is the same slots
/// re-ordered. Inversion edges always run from the shallower
/// centre to the deeper one, so the graph cannot cycle.
List<CarPainterSlot> resolveCarPainterOrder(List<CarPainterSlot> slots) {
  final n = slots.length;
  if (n < 2) return slots;
  final successors = List.generate(n, (_) => <int>[]);
  final pending = List<int>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final a = slots[i];
      final b = slots[j];
      // Sprites that never meet need no rule; when one body's
      // span clears the other's the deep-corner key already
      // holds; and a car touching a bridge keeps its key order.
      if (a.touchesBridge || b.touchesBridge) continue;
      if (a.right <= b.left ||
          b.right <= a.left ||
          a.bottom <= b.top ||
          b.bottom <= a.top) {
        continue;
      }
      if ((a.anchor - b.anchor).abs() >= a.halfDiag + b.halfDiag) {
        continue;
      }
      // Contested: the deeper centre draws in front. Only a pair
      // the incoming order already gets wrong needs an edge.
      if (a.anchor <= b.anchor) continue;
      successors[j].add(i);
      pending[i]++;
    }
  }
  if (successors.every((edges) => edges.isEmpty)) return slots;
  // Emit the earliest car whose contested predecessors are drawn.
  final out = <int>[];
  while (out.length < n) {
    var pick = -1;
    for (var i = 0; i < n; i++) {
      if (pending[i] == 0) {
        pick = i;
        break;
      }
    }
    if (pick < 0) break; // Unreachable: edges order by centre.
    pending[pick] = -1;
    out.add(pick);
    for (final next in successors[pick]) {
      pending[next]--;
    }
  }
  for (var i = 0; i < n; i++) {
    if (pending[i] > 0) out.add(i); // Defensive: keep every car.
  }
  return [for (final i in out) slots[i]];
}

enum _CarPhase { planning, dwellingStart, driving, dwellingEnd, cooldown }

class _CarSlot {
  _CarPhase phase = _CarPhase.planning;
  double timer = 0;
  CarActor? actor;
  List<LatticeSpot>? path;

  /// This trip's speed in cells per second.
  double speed = 1;

  /// Distance driven, in subtile hops.
  double distance = 0;
}

/// Render-only ambient car traffic on the painted lane lattice:
/// population-scaled slots, each running errands between buildings
/// — spawn at a curb, dwell, drive the planned lane path, dwell at
/// the destination, cooldown, then a new trip. Cars stop on the
/// main lane (parking paint is future work). Deliberately excluded
/// from world state and saves, exactly like the pedestrian sim:
/// ambience never affects gameplay, and a reload simply restarts
/// the traffic.
class CarTrafficSim {
  final List<CarActor> actors = [];
  final List<_CarSlot> _slots = [];
  VehicleLattice lattice = blankVehicleLattice;
  int _population = -1;
  int _roadCount = -1;
  int _bridgeCount = -1;
  int _structureCount = -1;
  double _lastSeconds = 0;
  math.Random _random = math.Random();

  /// Advances the traffic. Population changes resize the slot
  /// count; road, bridge, and building changes rebuild the lane
  /// lattice — all three happen on check-ins, so new slots and
  /// fronts join mid-session while running trips keep their paths.
  void update(
    double seconds,
    ParcelWorldState state,
    CarContent cars,
    Map<String, List<int>>? Function(String role) lanesFor, {
    double deckLift = 0,
  }) {
    if (state.population != _population ||
        state.roads.length != _roadCount ||
        state.bridges.length != _bridgeCount ||
        state.structures.length != _structureCount) {
      _population = state.population;
      _roadCount = state.roads.length;
      _bridgeCount = state.bridges.length;
      _structureCount = state.structures.length;
      _random = math.Random(state.seed + state.population);
      lattice = VehicleLattice(
        roadCells: pedestrianRoadCells(state),
        connectionCells: {
          for (final road in state.roads) road.cell,
          for (final bridge in state.bridges) ...bridge.waterCells,
        },
        lanesFor: lanesFor,
        bridgeRoles: pedestrianBridgeRoles(state),
        deckLift: deckLift,
      );
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

  /// The car's continuous grid position — its anchor spot lerped
  /// along the driven segment plus the lane-centring offset. The
  /// sort depth and the slope pitch agree on this one position.
  (double, double) actorPosition(CarActor car) {
    final fromCol = car.from.cell.column + (car.from.x + 0.5) / 8;
    final toCol = car.to.cell.column + (car.to.x + 0.5) / 8;
    final fromRow = car.from.cell.row + (car.from.y + 0.5) / 8;
    final toRow = car.to.cell.row + (car.to.y + 0.5) / 8;
    return (
      fromCol + (toCol - fromCol) * car.progress + car.laneOffsetCol,
      fromRow + (toRow - fromRow) * car.progress + car.laneOffsetRow,
    );
  }

  /// The car's mid-body painter depth — the spot depth lerped
  /// along the driven segment, before any extremity raise. Pairs
  /// of cars whose sprites contest on screen compare these (see
  /// [resolveCarPainterOrder]): the deep corner is exactly right
  /// at the leading end of a pass but wrong at the trailing end of
  /// unequal cars, where the bodies' centres are the fair judge.
  double actorAnchorDepth(CarActor car) {
    final a = lattice.surface.walkerSortDepth(car.from);
    final b = lattice.surface.walkerSortDepth(car.to);
    return a + (b - a) * car.progress;
  }

  /// Painter's depth for a car: the mid-body depth raised, for an
  /// extended body, to the deep extremity's depth. A car is 3–8
  /// subtiles long, and the anchor point alone would let a nose
  /// already over a bridge tile (or over the car ahead) sort
  /// behind that tile's art until the anchor crossed; the deep
  /// end — the (col+row)-max corner of the drawn footprint, front
  /// for east/south travel and rear for west/north — is what
  /// actually needs to clear it. [halfDiagCells] is that corner's
  /// (col+row) gain over the anchor: half the drawn footprint's
  /// length plus half its width, which is the drawn width in
  /// cells — so the key evaluates the true deepest ground point
  /// under the sprite.
  double actorDepth(CarActor car, {double halfDiagCells = 0}) {
    final base = actorAnchorDepth(car);
    if (halfDiagCells <= 0) return base;
    final (col, row) = actorPosition(car);
    // The deep end sits along the heading for east/south travel
    // and against it for west/north — either way its (col+row)
    // gain is the half-diagonal.
    final sign = car.headingDx + car.headingDy > 0 ? 1.0 : -1.0;
    final cornerDepth = lattice.depthAt(
      col + sign * car.headingDx * halfDiagCells,
      row + sign * car.headingDy * halfDiagCells,
    );
    return cornerDepth > base ? cornerDepth : base;
  }

  /// Whether any of the car's drawn extent — the anchor or the
  /// deep corner — stands on a bridge cell. Such cars are exempt
  /// from contested painter re-ordering (see
  /// [resolveCarPainterOrder]): near a bridge the deep-corner key
  /// is load-bearing, keeping a climbing car above the deck
  /// pieces while its anchor is still behind them, and an
  /// anchor-based contest would pull it back under the art.
  bool touchesBridge(CarActor car, {double halfDiagCells = 0}) {
    final (col, row) = actorPosition(car);
    if (lattice.surface.isBridgeCell(CellCoord(col.floor(), row.floor()))) {
      return true;
    }
    if (halfDiagCells <= 0) return false;
    final sign = car.headingDx + car.headingDy > 0 ? 1.0 : -1.0;
    return lattice.surface.isBridgeCell(
      CellCoord(
        (col + sign * car.headingDx * halfDiagCells).floor(),
        (row + sign * car.headingDy * halfDiagCells).floor(),
      ),
    );
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
        slot.distance += slot.speed * propSubtilesPerAxis * dt;
        final hops = slot.path!.length - 1;
        if (slot.distance >= hops) {
          slot.distance = hops.toDouble();
          _positionActor(slot);
          slot.actor!.dwelling = true;
          slot.phase = _CarPhase.dwellingEnd;
          slot.timer = cars.dwellSeconds;
        } else {
          _positionActor(slot);
        }
      case _CarPhase.dwellingEnd:
        slot.timer -= dt;
        if (slot.timer <= 0) {
          slot.actor = null;
          slot.path = null;
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
    final path = planCarTrip(state, cars, lattice, _random);
    if (path == null) {
      // The town cannot host a trip yet — lanes and buildings are
      // still being painted and built. Retry after the respawn
      // delay.
      slot.phase = _CarPhase.cooldown;
      slot.timer = cars.respawnDelaySeconds;
      return;
    }
    final (type, variant) = pickCarModel(cars, _random);
    slot
      ..path = path
      ..speed = cars.speedMin + _random.nextDouble() * cars.speedRange
      ..distance = 0
      ..phase = _CarPhase.dwellingStart
      ..timer = cars.dwellSeconds
      ..actor = CarActor(
        type: type,
        variant: variant,
        spot: path.first,
        headingDx: _segmentDx(path, 0),
        headingDy: _segmentDy(path, 0),
      );
    // Place the dwelling car on its lane's centre right away, so
    // the pull-out does not jump sideways when driving begins.
    _positionActor(slot);
  }

  /// The heading of a path segment, in grid steps — the direction
  /// of the lane being driven.
  int _segmentDx(List<LatticeSpot> path, int index) =>
      ((path[index + 1].cell.column - path[index].cell.column) *
                  propSubtilesPerAxis +
              path[index + 1].x -
              path[index].x)
          .sign;
  int _segmentDy(List<LatticeSpot> path, int index) =>
      ((path[index + 1].cell.row - path[index].cell.row) * propSubtilesPerAxis +
              path[index + 1].y -
              path[index].y)
          .sign;

  void _positionActor(_CarSlot slot) {
    final path = slot.path!;
    final hops = path.length - 1;
    final d = slot.distance.clamp(0.0, hops.toDouble());
    final segment = math.min(d.floor(), hops - 1);
    final actor = slot.actor!;
    actor.from = path[segment];
    actor.to = path[segment + 1];
    actor.progress = (d - segment).clamp(0.0, 1.0);
    actor.headingDx = _segmentDx(path, segment);
    actor.headingDy = _segmentDy(path, segment);
    // Lane centring: the car sits at the centre of the lane it
    // drives, whatever its painted thickness — measured at both
    // ends of the segment and lerped, so tapering bands glide.
    final direction = directionForDelta(actor.headingDx, actor.headingDy);
    final fromCentre = lattice.laneCenterOffset(actor.from, direction);
    final toCentre = lattice.laneCenterOffset(actor.to, direction);
    actor.laneOffsetCol =
        fromCentre.$1 + (toCentre.$1 - fromCentre.$1) * actor.progress;
    actor.laneOffsetRow =
        fromCentre.$2 + (toCentre.$2 - fromCentre.$2) * actor.progress;
  }
}

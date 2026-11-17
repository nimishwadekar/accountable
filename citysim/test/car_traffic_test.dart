import 'dart:math' as math;

import 'package:citysim/content/content_models.dart'
    show CarContent, CarTypeContent, RoadStyle, StructureKind;
import 'package:citysim/world/car_traffic.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:citysim/world/pedestrian_lattice.dart'
    show LatticeSpot, pedestrianBridgeRoles, pedestrianRoadCells;
import 'package:citysim/world/vehicle_lattice.dart';
import 'package:citysim/world/world_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// A minimal state carrying roads, bridges, buildings, and a
/// population — enough to plan and drive trips.
ParcelWorldState carState({
  required List<RoadSegment> roads,
  List<PlacedStructure> structures = const [],
  List<CompletedBridge> bridges = const [],
  int population = 0,
}) => ParcelWorldState(
  seed: 1,
  generatorVersion: 1,
  parcelSize: 8,
  simulatedDate: DateTime(2026, 1, 1),
  checkInHighWaterDate: DateTime(2026, 1, 1),
  constructionDay: 0,
  coins: 0,
  totalCoinsEarned: 0,
  totalCoinsSpent: 0,
  nextEntityNumber: 1,
  nextEventNumber: 1,
  lastCheckInDate: null,
  checkInCount: 0,
  unlockedCatalogueIds: const {},
  parcels: const [],
  roads: roads,
  structures: structures,
  props: const [],
  bridges: bridges,
  constructions: const [],
  events: const [],
  population: population,
);

RoadSegment roadAt(String id, int column, int row) => RoadSegment(
  id: id,
  cell: CellCoord(column, row),
  style: RoadStyle.asphalt,
  pricePaid: 1,
  completedAtDay: 0,
);

/// A one-tile building; population marks it residential the way
/// placed structures carry their housed population.
PlacedStructure building(
  String id,
  int column,
  int row, {
  int population = 0,
}) => PlacedStructure(
  id: id,
  catalogueId: id,
  kind: StructureKind.building,
  origin: CellCoord(column, row),
  quarterTurns: 0,
  footprint: [CellCoord(column, row)],
  pricePaid: 0,
  completedAtDay: 0,
  population: population,
);

const carContent = CarContent(
  populationPercent: 10,
  speedMin: 1,
  speedRange: 0,
  spriteScale: 0.9,
  dwellSeconds: 2.5,
  respawnDelaySeconds: 4,
  minTripCells: 10,
  types: [
    CarTypeContent(id: 'sedan', percent: 60, variants: ['blue', 'white']),
    CarTypeContent(id: 'firetruck', percent: 40),
  ],
);

/// Two-lane paint: an eastbound band on rows 4-5 (right-hand
/// traffic) and a westbound band on rows 2-3, on every role —
/// straights, end caps, ramps, and decks alike.
Map<String, List<int>> twoLanePaint(String role) => {
  'east-1': [for (var y = 0; y < 8; y++) y == 4 || y == 5 ? 255 : 0],
  'west-1': [for (var y = 0; y < 8; y++) y == 2 || y == 3 ? 255 : 0],
};

/// The lane lattice a town's roads carry under the test paint.
VehicleLattice latticeFor(ParcelWorldState state, {double deckLift = 0}) =>
    VehicleLattice(
      roadCells: pedestrianRoadCells(state),
      connectionCells: {
        for (final road in state.roads) road.cell,
        for (final bridge in state.bridges) ...bridge.waterCells,
      },
      lanesFor: twoLanePaint,
      bridgeRoles: pedestrianBridgeRoles(state),
      deckLift: deckLift,
    );

/// A long east-west road with a home at the west end and a shop at
/// the east end — twenty road cells apart.
(ParcelWorldState, VehicleLattice, CellCoord, CellCoord) errandTown({
  int population = 10,
}) {
  final state = carState(
    roads: [
      for (var column = 0; column <= 20; column++)
        roadAt('r$column', column, 0),
    ],
    structures: [
      building('home', 0, 1, population: 1),
      building('shop', 20, 1),
    ],
    population: population,
  );
  return (
    state,
    latticeFor(state),
    const CellCoord(0, 0),
    const CellCoord(20, 0),
  );
}

int _subtileColumn(LatticeSpot spot) => spot.cell.column * 8 + spot.x;
int _subtileRow(LatticeSpot spot) => spot.cell.row * 8 + spot.y;

void main() {
  test('traffic scales with population, not roads', () {
    expect(carTargetCount(0, carContent), 0);
    expect(carTargetCount(1, carContent), 1);
    expect(carTargetCount(10, carContent), 1);
    expect(carTargetCount(51, carContent), 5);
    expect(carTargetCount(500, carContent), 50);
    const off = CarContent(
      populationPercent: 0,
      speedMin: 1,
      speedRange: 0,
      spriteScale: 0.9,
      dwellSeconds: 2.5,
      respawnDelaySeconds: 4,
      minTripCells: 10,
      types: [],
    );
    expect(carTargetCount(51, off), 0, reason: 'zero percent is off');
  });

  test('vehicle types roll by percent, colours by variant', () {
    const allSedan = CarContent(
      populationPercent: 10,
      speedMin: 1,
      speedRange: 0,
      spriteScale: 0.9,
      dwellSeconds: 2.5,
      respawnDelaySeconds: 4,
      minTripCells: 10,
      types: [
        CarTypeContent(id: 'sedan', percent: 100, variants: ['blue']),
      ],
    );
    for (var i = 0; i < 10; i++) {
      final (type, variant) = pickCarModel(allSedan, math.Random(i));
      expect(type, 'sedan');
      expect(variant, 'blue');
    }
    // A mixed table rolls both types; variant-less types carry null.
    final random = math.Random(7);
    var sawSedan = false;
    var sawFiretruck = false;
    for (var i = 0; i < 200; i++) {
      final (type, variant) = pickCarModel(carContent, random);
      if (type == 'sedan') {
        sawSedan = true;
        expect(variant, anyOf('blue', 'white'));
      } else {
        sawFiretruck = true;
        expect(variant, isNull);
      }
    }
    expect(sawSedan, isTrue);
    expect(sawFiretruck, isTrue);
  });

  test('trips need buildings a minimum of road apart', () {
    final (state, lattice, westFront, eastFront) = errandTown();

    // No buildings, no trips — and no paint, none either.
    final bareRoads = carState(
      roads: [for (var c = 0; c <= 20; c++) roadAt('r$c', c, 0)],
    );
    expect(
      planCarTrip(bareRoads, carContent, latticeFor(bareRoads), math.Random(1)),
      isNull,
      reason: 'a town without buildings hosts no errands',
    );
    final unpainted = VehicleLattice(
      roadCells: pedestrianRoadCells(bareRoads),
      connectionCells: {for (final road in bareRoads.roads) road.cell},
      lanesFor: (_) => null,
    );
    expect(
      planCarTrip(state, carContent, unpainted, math.Random(1)),
      isNull,
      reason: 'unpainted roads carry no traffic',
    );

    // Buildings two cells apart sit under the ten-cell minimum.
    final near = carState(
      roads: [roadAt('a', 0, 0), roadAt('b', 1, 0), roadAt('c', 2, 0)],
      structures: [
        building('home', 0, 1, population: 1),
        building('shop', 2, 1),
      ],
    );
    expect(
      planCarTrip(near, carContent, latticeFor(near), math.Random(1)),
      isNull,
    );

    // Twenty cells apart: a full trip, pinned end to end.
    final path = planCarTrip(state, carContent, lattice, math.Random(1));
    expect(path, isNotNull);
    final trip = path!;
    expect(trip.first.cell, anyOf(westFront, eastFront));
    expect(trip.last.cell, anyOf(westFront, eastFront));
    expect(trip.first.cell, isNot(trip.last.cell));
    // Ten road cells is eighty subtile hops at minimum.
    expect(trip.length - 1, greaterThanOrEqualTo(80));
    // Every step is one subtile in one axis, and no step reverses
    // the one before it — cars never U-turn.
    var previousDx = 0;
    var previousDy = 0;
    for (var i = 1; i < trip.length; i++) {
      final dx = _subtileColumn(trip[i]) - _subtileColumn(trip[i - 1]);
      final dy = _subtileRow(trip[i]) - _subtileRow(trip[i - 1]);
      expect(dx.abs() + dy.abs(), 1, reason: 'steps are single subtiles');
      expect(
        dx == -previousDx && dy == -previousDy,
        isFalse,
        reason: 'no step reverses its predecessor',
      );
      previousDx = dx;
      previousDy = dy;
    }

    // Only homes: the cross-kind bias falls back to any pair.
    final homesOnly = carState(
      roads: [for (var c = 0; c <= 20; c++) roadAt('r$c', c, 0)],
      structures: [
        building('home-a', 0, 1, population: 1),
        building('home-b', 20, 1, population: 1),
      ],
    );
    expect(
      planCarTrip(homesOnly, carContent, latticeFor(homesOnly), math.Random(1)),
      isNotNull,
    );
  });

  test('bridge crossings carry traffic with climbing lift', () {
    final state = carState(
      roads: [
        roadAt('approach', 0, 0),
        roadAt('near-bank', 1, 0),
        roadAt('far-bank', 3, 0),
        roadAt('beyond', 4, 0),
      ],
      bridges: [
        CompletedBridge(
          id: 'bridge',
          waterCells: const [CellCoord(2, 0)],
          nearBank: const CellCoord(1, 0),
          farBank: const CellCoord(3, 0),
          completedAtDay: 0,
          pricePaid: 6,
        ),
      ],
      structures: [
        building('home', 0, 1, population: 1),
        building('shop', 4, 1),
      ],
      population: 10,
    );
    // The minimum trip is short enough for the crossing.
    const content = CarContent(
      populationPercent: 10,
      speedMin: 1,
      speedRange: 0,
      spriteScale: 0.9,
      dwellSeconds: 2.5,
      respawnDelaySeconds: 4,
      minTripCells: 2,
      types: [CarTypeContent(id: 'sedan', percent: 100)],
    );
    final lattice = latticeFor(state, deckLift: 12);
    final trip = planCarTrip(state, content, lattice, math.Random(1));
    expect(trip, isNotNull);
    expect(
      trip!.any((spot) => spot.cell == const CellCoord(2, 0)),
      isTrue,
      reason: 'the errand crosses the deck over the water',
    );

    // The lattice climbs the near ramp and sits flat on the deck,
    // through the same surface the pedestrians use.
    expect(
      lattice.surface.liftAt(const LatticeSpot(CellCoord(1, 0), 0, 4)),
      closeTo(12 * 0.0625, 0.001),
    );
    expect(
      lattice.surface.liftAt(const LatticeSpot(CellCoord(1, 0), 7, 4)),
      closeTo(12 * 0.9375, 0.001),
    );
    expect(
      lattice.surface.liftAt(const LatticeSpot(CellCoord(2, 0), 3, 4)),
      12,
    );
    expect(lattice.surface.liftAt(const LatticeSpot(CellCoord(0, 0), 3, 4)), 0);
  });

  test('slots run the errand lifecycle', () {
    final (state, lattice, westFront, eastFront) = errandTown();
    final sim = CarTrafficSim();
    var seconds = 0.0;
    sim.update(seconds, state, carContent, twoLanePaint);
    expect(sim.actors, isEmpty, reason: 'new slots start in cooldown');

    void step(double dt) {
      for (var t = 0.0; t < dt; t += 0.1) {
        seconds += 0.1;
        sim.update(seconds, state, carContent, twoLanePaint);
      }
    }

    // Cooldown passes and a car appears, stopped on its start lane.
    step(3);
    expect(sim.actors, hasLength(1));
    final car = sim.actors.single;
    expect(car.dwelling, isTrue);
    // The seeded roll may run the errand either way — the car
    // starts at one front and parks at the other.
    final tripStart = car.from.cell;
    expect(tripStart, anyOf(westFront, eastFront));
    final tripEnd = tripStart == westFront ? eastFront : westFront;
    expect(car.type, anyOf('sedan', 'firetruck'));
    // Lane centring: the car sits at its 2-wide lane's centre, half
    // a subtile off the subtile it drives.
    expect(car.laneOffsetCol, 0);
    expect(
      car.laneOffsetRow.abs(),
      closeTo(0.0625, 0.001),
      reason: "centred between the band's two rows",
    );

    // The departure dwell passes and the car drives.
    step(2.6);
    expect(sim.actors.single.dwelling, isFalse);

    // Twenty cells at one cell per second — eight subtiles each.
    // Watch for the arrival rather than racing a fixed window: the
    // trip length varies a little with the painted front spots. At
    // arrival the car's leading spot `to` rests on the far front.
    var arrived = false;
    for (var i = 0; i < 300 && !arrived; i++) {
      step(0.1);
      final current = sim.actors.isEmpty ? null : sim.actors.single;
      if (current != null && current.dwelling && current.to.cell == tripEnd) {
        arrived = true;
      }
    }
    expect(arrived, isTrue, reason: 'the car parks at the far front');

    // The arrival dwell passes, the car despawns into cooldown...
    var gone = false;
    for (var i = 0; i < 60 && !gone; i++) {
      step(0.1);
      if (sim.actors.isEmpty) gone = true;
    }
    expect(gone, isTrue);

    // ...and a new errand begins after the respawn delay, stopped
    // on its curb. The cooldown is jittered, so watch for it rather
    // than racing a fixed window.
    var respawned = false;
    for (var i = 0; i < 60 && !respawned; i++) {
      step(0.1);
      if (sim.actors.isNotEmpty) {
        respawned = true;
        expect(
          sim.actors.single.dwelling,
          isTrue,
          reason: 'a fresh errand starts stopped on its lane',
        );
      }
    }
    expect(respawned, isTrue, reason: 'the slot respawns within ~6s');

    // The same state drives the same traffic: reloads replay.
    final replay = CarTrafficSim();
    var replaySeconds = 0.0;
    replay.update(replaySeconds, state, carContent, twoLanePaint);
    void replayStep(double dt) {
      for (var t = 0.0; t < dt; t += 0.1) {
        replaySeconds += 0.1;
        replay.update(replaySeconds, state, carContent, twoLanePaint);
      }
    }

    replayStep(3);
    expect(replay.actors.single.type, car.type);
    expect(replay.actors.single.variant, car.variant);
    expect(replay.actors.single.from.cell, tripStart);
  });

  test('towns too small for a trip stay foot-traffic only', () {
    // Population says one slot, but the buildings sit two cells
    // apart — under the ten-cell minimum — so no car ever appears.
    final state = carState(
      roads: [roadAt('a', 0, 0), roadAt('b', 1, 0), roadAt('c', 2, 0)],
      structures: [
        building('home', 0, 1, population: 1),
        building('shop', 2, 1),
      ],
      population: 10,
    );
    final sim = CarTrafficSim();
    sim.update(0, state, carContent, twoLanePaint);
    var seconds = 0.0;
    for (var i = 0; i < 200; i++) {
      seconds += 0.1;
      sim.update(seconds, state, carContent, twoLanePaint);
    }
    expect(sim.actors, isEmpty, reason: 'planning retries find no pair');

    // Unpainted roads idle their slots the same way.
    final unpainted = CarTrafficSim();
    final town = errandTown().$1;
    unpainted.update(0, town, carContent, (_) => null);
    var unpaintedSeconds = 0.0;
    for (var i = 0; i < 100; i++) {
      unpaintedSeconds += 0.1;
      unpainted.update(unpaintedSeconds, town, carContent, (_) => null);
    }
    expect(unpainted.actors, isEmpty);

    // And a town with nobody living in it runs no slots at all.
    final empty = CarTrafficSim();
    empty.update(0, state.copyWith(population: 0), carContent, twoLanePaint);
    expect(empty.actors, isEmpty);
  });

  test('car sort depth follows its deep end onto bridge tiles', () {
    final state = carState(
      roads: [
        roadAt('approach', 0, 0),
        roadAt('near-bank', 1, 0),
        roadAt('far-bank', 3, 0),
        roadAt('beyond', 4, 0),
      ],
      bridges: [
        CompletedBridge(
          id: 'bridge',
          waterCells: const [CellCoord(2, 0)],
          nearBank: const CellCoord(1, 0),
          farBank: const CellCoord(3, 0),
          pricePaid: 6,
          completedAtDay: 0,
        ),
      ],
      population: 10,
    );
    final sim = CarTrafficSim();
    sim.update(0, state, carContent, twoLanePaint);

    // The continuous depth formula: ground positions stay below
    // their cell's depth, bridge positions climb above the tile
    // pieces at +0.02/+0.05.
    expect(sim.lattice.depthAt(0.5, 0.5), closeTo(0.0, 0.001));
    expect(sim.lattice.depthAt(1.6, 0.5), greaterThan(1.05));

    // An eastbound car at the last ground subtile before the bank,
    // with a body long enough that its nose is over the bank: the
    // sort key must follow the nose onto the bridge formula and
    // clear the bank tile's pieces — the point depth alone sits
    // below them until the anchor crosses, which is the boundary
    // clip.
    final car = CarActor(
      type: 'sedan',
      variant: null,
      spot: const LatticeSpot(CellCoord(0, 0), 7, 4),
      headingDx: 1,
      headingDy: 0,
    );
    final base = sim.actorDepth(car);
    final deep = sim.actorDepth(car, halfDiagCells: 0.5);
    expect(base, lessThan(1.05));
    expect(deep, greaterThan(base));
    expect(deep, greaterThan(1.05));
    // The deep end is the front for eastbound travel and the rear
    // for westbound — same gain, opposite direction.
    final westbound = CarActor(
      type: 'sedan',
      variant: null,
      spot: const LatticeSpot(CellCoord(1, 0), 0, 2),
      headingDx: -1,
      headingDy: 0,
    );
    expect(
      sim.actorDepth(westbound, halfDiagCells: 0.5),
      greaterThan(sim.actorDepth(westbound)),
    );
  });

  test('cars pitch onto ramps from the lift gradient', () {
    final state = carState(
      roads: [
        roadAt('approach', 0, 0),
        roadAt('near-bank', 1, 0),
        roadAt('far-bank', 3, 0),
        roadAt('beyond', 4, 0),
      ],
      bridges: [
        CompletedBridge(
          id: 'bridge',
          waterCells: const [CellCoord(2, 0)],
          nearBank: const CellCoord(1, 0),
          farBank: const CellCoord(3, 0),
          pricePaid: 6,
          completedAtDay: 0,
        ),
      ],
      population: 10,
    );
    final sim = CarTrafficSim();
    sim.update(0, state, carContent, twoLanePaint, deckLift: 12);

    // The continuous lift field: the near ramp rises from ground
    // at its west edge to deck height at its east edge, the deck
    // sits flat, and ground is zero.
    expect(sim.lattice.liftAtGrid(1.0, 0.5), closeTo(0, 0.001));
    expect(sim.lattice.liftAtGrid(2.0, 0.5), closeTo(12, 0.001));
    expect(sim.lattice.liftAtGrid(2.5, 0.5), closeTo(12, 0.001));
    expect(sim.lattice.liftAtGrid(0.5, 0.5), 0);

    // The gradient: the ramp's full slope along the bridge axis
    // and none across it — the quarter-cell sampling stays on the
    // one-tile ramp strip; the deck and ground are level.
    final ramp = sim.lattice.liftGradient(1.5, 0.5);
    expect(ramp.$1, closeTo(12, 0.001));
    expect(ramp.$2, closeTo(0, 0.001));
    final deck = sim.lattice.liftGradient(2.5, 0.5);
    expect(deck.$1, closeTo(0, 0.001));
    expect(deck.$2, closeTo(0, 0.001));
    final ground = sim.lattice.liftGradient(0.5, 0.5);
    expect(ground.$1, 0);
    expect(ground.$2, 0);

    // The rotation: flat ground is zero, and the seeded 12-px ramp
    // pitches an eastbound car nose-up by the angle between its
    // flat trajectory (32, 16) per cell and the ramp trajectory
    // (32, 4) — about 19.4° counterclockwise on screen.
    expect(pitchRotation(0, 0, 1, 0), 0);
    expect(pitchRotation(12, 0, 1, 0), closeTo(-0.3393, 0.001));
    // Descending mirrors it nose-down, and a northbound climb
    // pitches by the iso-compressed angle of its own trajectory —
    // (32, −16) flattening to (32, −28) is a smaller turn.
    expect(pitchRotation(-12, 0, 1, 0), closeTo(0.2552, 0.001));
    expect(pitchRotation(0, -12, 0, -1), closeTo(-0.2552, 0.001));

    // A car shares one position between depth and shear: the
    // actor position is the anchor spot plus lane centring.
    final car = CarActor(
      type: 'sedan',
      variant: null,
      spot: const LatticeSpot(CellCoord(1, 0), 3, 4),
      headingDx: 1,
      headingDy: 0,
    );
    final (col, row) = sim.actorPosition(car);
    expect(col, closeTo(1 + (3 + 0.5) / 8, 0.001));
    expect(row, closeTo((4 + 0.5) / 8, 0.001));
  });

  test('contested cars re-order by their bodies, not their noses', () {
    // The passing moment: the sprites overlap, the depth spans
    // interleave, and the bus's far tail gives it the deeper
    // deep-corner key — exactly right at the leading ends, wrong
    // here at the sedan's tail against the bus's nose. The
    // sedan's centre is the deeper body, so it must draw in front.
    CarPainterSlot slot(
      int actor,
      double anchor,
      double halfDiag, {
      bool touchesBridge = false,
    }) => CarPainterSlot(
      actor: actor,
      anchor: anchor,
      halfDiag: halfDiag,
      touchesBridge: touchesBridge,
      left: 90,
      top: 5,
      right: 130,
      bottom: 45,
    );

    expect(
      resolveCarPainterOrder([slot(0, 4.75, 0.45), slot(1, 4.7, 0.65)])
          .map((s) => s.actor),
      [1, 0],
    );

    // Bodies whose spans clear each other keep the sort's order —
    // the deep-corner key is exactly right there — and equal
    // centres tie to the incoming order.
    expect(
      resolveCarPainterOrder([slot(0, 3.8, 0.45), slot(1, 4.75, 0.45)])
          .map((s) => s.actor),
      [0, 1],
    );
    expect(
      resolveCarPainterOrder([slot(0, 4.75, 0.45), slot(1, 4.75, 0.45)])
          .map((s) => s.actor),
      [0, 1],
    );

    // A third car ahead of the pass keeps its place: only the
    // contested inversion swaps.
    expect(
      resolveCarPainterOrder([
        slot(0, 4.2, 0.4),
        slot(1, 4.75, 0.45),
        slot(2, 4.7, 0.65),
      ]).map((s) => s.actor),
      [0, 2, 1],
    );

    // A car touching a bridge is exempt even from a contest it
    // would lose: near a bridge the deep-corner key is
    // load-bearing — it keeps a climbing car above the deck
    // pieces — so the key order stands exactly as sorted.
    expect(
      resolveCarPainterOrder([
        slot(0, 4.75, 0.45, touchesBridge: true),
        slot(1, 4.7, 0.65),
      ]).map((s) => s.actor),
      [0, 1],
    );
  });
}

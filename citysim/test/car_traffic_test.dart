import 'dart:math' as math;

import 'package:citysim/content/content_models.dart'
    show CarContent, CarTypeContent, RoadStyle, StructureKind;
import 'package:citysim/world/car_traffic.dart';
import 'package:citysim/world/coordinates.dart';
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
  worldId: 'test',
  seed: 1,
  generatorVersion: 1,
  rulesVersion: 1,
  contentVersion: 1,
  parcelSize: 8,
  builderCapacity: 1,
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
/// placed structures carry their households.
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

/// A long east-west road with a home at the west end and a shop at
/// the east end — twenty road cells apart.
(ParcelWorldState, CellCoord, CellCoord) errandTown({int population = 10}) {
  final roads = [
    for (var column = 0; column <= 20; column++) roadAt('r$column', column, 0),
  ];
  final state = carState(
    roads: roads,
    structures: [
      building('home', 0, 1, population: 1),
      building('shop', 20, 1),
    ],
    population: population,
  );
  return (state, const CellCoord(0, 0), const CellCoord(20, 0));
}

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

  test('car graphs drive roads and bridge decks', () {
    // An east-going bridge: approach, near bank, water, far bank,
    // continuing road. Banks are road tiles and decks are water —
    // cars drive both.
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
    );
    expect(carDrivableCells(state), {
      const CellCoord(0, 0),
      const CellCoord(1, 0),
      const CellCoord(2, 0),
      const CellCoord(3, 0),
      const CellCoord(4, 0),
    });
  });

  test('front cells border the building on the car graph', () {
    final state = carState(
      roads: [roadAt('a', 2, 0), roadAt('b', 3, 1), roadAt('c', 9, 9)],
    );
    final drivable = carDrivableCells(state);
    // A corner lot fronts two sides.
    expect(carFrontCells(building('corner', 2, 1), drivable), const [
      CellCoord(2, 0),
      CellCoord(3, 1),
    ]);
    // A building away from any road has no front.
    expect(carFrontCells(building('lonely', 5, 5), drivable), isEmpty);
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
    // No buildings, no trips.
    expect(
      planCarTrip(
        carState(roads: [for (var c = 0; c <= 20; c++) roadAt('r$c', c, 0)]),
        carContent,
        math.Random(1),
      ),
      isNull,
      reason: 'a town without buildings hosts no errands',
    );

    // Buildings two cells apart sit under the ten-cell minimum.
    final near = carState(
      roads: [roadAt('a', 0, 0), roadAt('b', 1, 0), roadAt('c', 2, 0)],
      structures: [
        building('home', 0, 1, population: 1),
        building('shop', 2, 1),
      ],
    );
    expect(planCarTrip(near, carContent, math.Random(1)), isNull);

    // Twenty cells apart: a full trip, pinned end to end.
    final (state, startFront, endFront) = errandTown();
    final trip = planCarTrip(state, carContent, math.Random(1));
    expect(trip, isNotNull);
    final path = trip!.path;
    expect(path.first, startFront);
    expect(path.last, endFront);
    expect(path.length, greaterThanOrEqualTo(11));
    // Shortest paths are simple, adjacent, and never double back.
    expect(path.toSet().length, path.length);
    for (var i = 1; i < path.length; i++) {
      expect(
        (path[i - 1].column - path[i].column).abs() +
            (path[i - 1].row - path[i].row).abs(),
        1,
      );
    }

    // Only homes: the cross-kind bias falls back to any pair.
    final homesOnly = carState(
      roads: [for (var c = 0; c <= 20; c++) roadAt('r$c', c, 0)],
      structures: [
        building('home-a', 0, 1, population: 1),
        building('home-b', 20, 1, population: 1),
      ],
    );
    expect(planCarTrip(homesOnly, carContent, math.Random(1)), isNotNull);
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
          pricePaid: 6,
          completedAtDay: 0,
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
    final trip = planCarTrip(state, content, math.Random(1));
    expect(trip, isNotNull);
    expect(
      trip!.path,
      contains(const CellCoord(2, 0)),
      reason: 'the errand crosses the deck over the water',
    );

    // The sim climbs the near ramp and sits flat on the deck.
    final sim = CarTrafficSim();
    sim.update(0, state, content, deckLift: 12);
    expect(sim.surfaceLift(const CellCoord(1, 0), -0.5, 0), 0);
    expect(sim.surfaceLift(const CellCoord(1, 0), 0.5, 0), 12);
    expect(sim.surfaceLift(const CellCoord(2, 0), 0, 0), 12);
    expect(sim.surfaceLift(const CellCoord(0, 0), 0.3, -0.2), 0);
  });

  test('slots run the errand lifecycle', () {
    final (state, startFront, endFront) = errandTown();
    final sim = CarTrafficSim();
    var seconds = 0.0;
    sim.update(seconds, state, carContent);
    expect(sim.actors, isEmpty, reason: 'new slots start in cooldown');

    void step(double dt) {
      for (var t = 0.0; t < dt; t += 0.1) {
        seconds += 0.1;
        sim.update(seconds, state, carContent);
      }
    }

    // Cooldown passes and a car appears, dwelling at its start curb.
    step(3);
    expect(sim.actors, hasLength(1));
    final car = sim.actors.single;
    expect(car.dwelling, isTrue);
    // The seeded roll may run the errand either way — the car
    // spawns at one front and parks at the other.
    final tripStart = CellCoord(car.gridColumn.floor(), car.gridRow.floor());
    expect(tripStart, anyOf(startFront, endFront));
    final tripEnd = tripStart == startFront ? endFront : startFront;
    expect(car.type, anyOf('sedan', 'firetruck'));

    // The departure dwell passes and the car drives.
    step(2.6);
    expect(sim.actors.single.dwelling, isFalse);

    // Twenty cells at one cell per second.
    step(20);
    final arrived = sim.actors.single;
    expect(arrived.dwelling, isTrue, reason: 'parked at the destination');
    expect(
      CellCoord(arrived.gridColumn.floor(), arrived.gridRow.floor()),
      tripEnd,
    );

    // The arrival dwell passes, the car despawns into cooldown...
    step(2.6);
    expect(sim.actors, isEmpty);

    // ...and a new errand begins after the respawn delay, parked at
    // its curb. The cooldown is jittered, so watch for it rather
    // than racing a fixed window.
    var respawned = false;
    for (var i = 0; i < 60 && !respawned; i++) {
      step(0.1);
      if (sim.actors.isNotEmpty) {
        respawned = true;
        expect(
          sim.actors.single.dwelling,
          isTrue,
          reason: 'a fresh errand starts parked at its curb',
        );
      }
    }
    expect(respawned, isTrue, reason: 'the slot respawns within ~6s');

    // The same state drives the same traffic: reloads replay.
    final replay = CarTrafficSim();
    var replaySeconds = 0.0;
    replay.update(replaySeconds, state, carContent);
    void replayStep(double dt) {
      for (var t = 0.0; t < dt; t += 0.1) {
        replaySeconds += 0.1;
        replay.update(replaySeconds, state, carContent);
      }
    }

    replayStep(3);
    expect(replay.actors.single.type, car.type);
    expect(replay.actors.single.variant, car.variant);
    expect(
      CellCoord(
        replay.actors.single.gridColumn.floor(),
        replay.actors.single.gridRow.floor(),
      ),
      tripStart,
      reason: 'the same seed replays the same errand',
    );
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
    sim.update(0, state, carContent);
    var seconds = 0.0;
    for (var i = 0; i < 200; i++) {
      seconds += 0.1;
      sim.update(seconds, state, carContent);
    }
    expect(sim.actors, isEmpty, reason: 'planning retries find no pair');

    // And a town with nobody living in it runs no slots at all.
    final empty = CarTrafficSim();
    empty.update(0, state.copyWith(population: 0), carContent);
    expect(empty.actors, isEmpty);
  });
}

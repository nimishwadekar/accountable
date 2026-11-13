import 'dart:math' as math;

import 'package:citysim/content/content_models.dart' show RoadStyle;
import 'package:citysim/world/coordinates.dart';
import 'package:citysim/world/pedestrian_lattice.dart';
import 'package:citysim/world/world_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// A minimal state carrying just roads and bridges — enough to ask
/// which cells the walkable ground surface covers.
ParcelWorldState stateWith({
  required List<RoadSegment> roads,
  List<CompletedBridge> bridges = const [],
  List<WorldConstruction> constructions = const [],
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
  structures: const [],
  props: const [],
  bridges: bridges,
  constructions: constructions,
  events: const [],
);

RoadSegment roadAt(String id, int column, int row) => RoadSegment(
  id: id,
  cell: CellCoord(column, row),
  style: RoadStyle.asphalt,
  pricePaid: 1,
  completedAtDay: 0,
);

void main() {
  test('blank masks walk nowhere', () {
    final cells = <CellCoord>{
      for (var column = 0; column < 5; column++) CellCoord(column, 0),
    };
    final lattice = PedestrianLattice(
      roadCells: cells,
      connectionCells: cells,
      maskFor: (_) => const [],
    );
    expect(lattice.walkableCount, 0);
    expect(lattice.randomSpawn(math.Random(1)), isNull);
  });

  test('painted lanes flow within tiles and across borders', () {
    // Five tiles make three straights — a 3-tile road would bracket
    // its single straight with end caps.
    final cells = <CellCoord>{
      for (var column = 0; column < 5; column++) CellCoord(column, 0),
    };
    // The north sidewalk ring: the lattice's top row, walkable along
    // the whole column axis.
    const mask = [255, 0, 0, 0, 0, 0, 0, 0];
    final lattice = PedestrianLattice(
      roadCells: cells,
      connectionCells: cells,
      maskFor: (role) => role == 'road.straight.se' ? mask : const [],
    );
    expect(lattice.walkableCount, 3 * 8);

    // Within a tile, one subtile east along the lane.
    expect(
      lattice.step(const LatticeSpot(CellCoord(1, 0), 0, 0), 1, 0),
      const LatticeSpot(CellCoord(1, 0), 1, 0),
    );
    // Off a tile's east edge, into the neighbour's matching subtile.
    expect(
      lattice.step(const LatticeSpot(CellCoord(1, 0), 7, 0), 1, 0),
      const LatticeSpot(CellCoord(2, 0), 0, 0),
    );
    // And back west across the same border.
    expect(
      lattice.step(const LatticeSpot(CellCoord(2, 0), 0, 0), -1, 0),
      const LatticeSpot(CellCoord(1, 0), 7, 0),
    );
    // Unpainted rows are closed: stepping south off the ring is null,
    // and the centre of the tile is not walkable at all.
    expect(
      lattice.step(const LatticeSpot(CellCoord(1, 0), 0, 0), 0, 1),
      isNull,
    );
    expect(lattice.isWalkable(const CellCoord(1, 0), 3, 3), isFalse);
    // Off the painted network: west of the first straight is an
    // unpainted end cap.
    expect(
      lattice.step(const LatticeSpot(CellCoord(1, 0), 0, 0), -1, 0),
      isNull,
    );

    // Neighbours only ever offer walkable spots.
    final spot = const LatticeSpot(CellCoord(2, 0), 3, 0);
    for (final next in lattice.neighborsOf(spot)) {
      expect(lattice.containsSpot(next), isTrue);
    }
    expect(
      lattice.neighborsOf(spot).length,
      2,
      reason: 'a lane runs east-west',
    );

    // Spawns land on painted subtiles.
    final spawn = lattice.randomSpawn(math.Random(7));
    expect(spawn, isNotNull);
    expect(lattice.containsSpot(spawn!), isTrue);
    expect(lattice.neighborsOf(spawn), isNotEmpty);
  });

  test('approach tiles beside a junction use the pelican mask', () {
    // A cross with stub arms; the junction sits at (0,-1) and the
    // straight approach south of it renders the crossing facing
    // north, so its walkable paint comes from road.pelican.ne.
    final cells = <CellCoord>{
      const CellCoord(0, -2),
      const CellCoord(0, -1),
      const CellCoord(1, -1),
      const CellCoord(-1, -1),
      const CellCoord(0, 0),
      const CellCoord(0, 1),
      const CellCoord(0, 2),
    };
    // The crossing band of road.pelican.ne: two rows across the tile
    // near its north end, where the art paints its stripes.
    const pelicanMask = [0, 255, 255, 0, 0, 0, 0, 0];
    final lattice = PedestrianLattice(
      roadCells: cells,
      connectionCells: cells,
      maskFor: (role) => role == 'road.pelican.ne' ? pelicanMask : const [],
    );
    // The approach south of the junction painted, near its north end.
    expect(lattice.isWalkable(const CellCoord(0, 0), 3, 1), isTrue);
    expect(lattice.isWalkable(const CellCoord(0, 0), 3, 2), isTrue);
    // The plain straight beyond it, the junction, and the stub arms
    // resolve to other roles and stay blank.
    expect(lattice.isWalkable(const CellCoord(0, 1), 3, 1), isFalse);
    expect(lattice.isWalkable(const CellCoord(0, -1), 3, 1), isFalse);
    expect(lattice.isWalkable(const CellCoord(0, -2), 3, 1), isFalse);
    expect(lattice.walkableCount, 16);
  });

  test('bridge banks are not walkable road cells', () {
    // An east-going bridge: approach road, near bank, one water span,
    // far bank, continuing road — plus a second bridge still under
    // construction with its own funded banks.
    final state = stateWith(
      roads: [
        roadAt('approach', 0, 0),
        roadAt('near-bank', 1, 0),
        roadAt('far-bank', 3, 0),
        roadAt('beyond', 4, 0),
        roadAt('building-bank', 10, 0),
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
      constructions: [
        WorldConstruction(
          id: 'building',
          kind: WorldConstructionKind.bridge,
          totalCostCoins: 6,
          coinsFunded: 3,
          builderSlot: 0,
          startedAtDay: 0,
          waterCells: const [CellCoord(11, 0)],
          nearBank: const CellCoord(10, 0),
          farBank: const CellCoord(12, 0),
        ),
      ],
    );
    // Banks drop out of the walkable surface — completed and
    // under-construction alike — while every plain road stays.
    expect(pedestrianRoadCells(state), {
      const CellCoord(0, 0),
      const CellCoord(4, 0),
    });

    // The completed bridge's cells carry their ramp and deck roles;
    // the under-construction one contributes nothing.
    expect(pedestrianBridgeRoles(state), {
      const CellCoord(1, 0): 'bridge.ramp.nw',
      const CellCoord(2, 0): 'bridge.body.se',
      const CellCoord(3, 0): 'bridge.ramp.se',
    });
  });

  test('bridge surface lift rises from the bank to the deck', () {
    const lift = 12.0;
    // Ramp roles are named for the screen quadrant their low end
    // faces: ramp.nw is low at west, high at east.
    expect(bridgeSurfaceLift('bridge.ramp.nw', -0.5, 0, lift), 0);
    expect(bridgeSurfaceLift('bridge.ramp.nw', 0.5, 0, lift), lift);
    expect(bridgeSurfaceLift('bridge.ramp.se', 0.5, 0, lift), 0);
    expect(bridgeSurfaceLift('bridge.ramp.se', -0.5, 0, lift), lift);
    // Row-axis ramps climb along the row axis instead.
    expect(bridgeSurfaceLift('bridge.ramp.ne', 0, 0.5, lift), lift);
    expect(bridgeSurfaceLift('bridge.ramp.sw', 0, 0.5, lift), 0);
    // Decks sit flat at full lift; roads lift nothing.
    expect(bridgeSurfaceLift('bridge.body.se', 0.25, -0.25, lift), lift);
    expect(bridgeSurfaceLift('bridge.straight.se', 0, 0, lift), 0);
  });

  test('painted lanes flow from the road onto ramps and decks', () {
    // An east-going bridge over one water cell: approach road, near
    // ramp, deck, far ramp, continuing road.
    final state = stateWith(
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
    // The north sidewalk ring on every straight, a matching lane on
    // the ramps, and a deck-side lane on the body — all at the
    // lattice's north edge, so the lane runs unbroken across the
    // whole crossing.
    const ring = [255, 0, 0, 0, 0, 0, 0, 0];
    final lattice = PedestrianLattice(
      roadCells: pedestrianRoadCells(state),
      connectionCells: {
        for (final road in state.roads) road.cell,
        for (final bridge in state.bridges) ...bridge.waterCells,
      },
      maskFor: (role) => switch (role) {
        'road.straight.se' || 'road.end.se' || 'road.end.nw' => ring,
        'bridge.ramp.nw' || 'bridge.ramp.se' => ring,
        'bridge.body.se' => ring,
        _ => const [],
      },
      bridgeRoles: pedestrianBridgeRoles(state),
      deckLift: 12,
    );
    // The lane crosses every tile of the bridge.
    expect(lattice.walkableCount, 5 * 8);
    expect(
      lattice.step(const LatticeSpot(CellCoord(0, 0), 7, 0), 1, 0),
      const LatticeSpot(CellCoord(1, 0), 0, 0),
      reason: 'the road flows onto the near ramp',
    );
    expect(
      lattice.step(const LatticeSpot(CellCoord(1, 0), 7, 0), 1, 0),
      const LatticeSpot(CellCoord(2, 0), 0, 0),
      reason: 'the ramp flows onto the deck',
    );
    expect(
      lattice.step(const LatticeSpot(CellCoord(3, 0), 0, 0), -1, 0),
      const LatticeSpot(CellCoord(2, 0), 7, 0),
      reason: 'the far ramp flows back onto the deck',
    );

    // The lift climbs across the near ramp and holds on the deck.
    expect(
      lattice.liftAt(const LatticeSpot(CellCoord(1, 0), 0, 0)),
      closeTo(12 * 0.0625, 0.001),
    );
    expect(
      lattice.liftAt(const LatticeSpot(CellCoord(1, 0), 7, 0)),
      closeTo(12 * 0.9375, 0.001),
    );
    expect(lattice.liftAt(const LatticeSpot(CellCoord(2, 0), 3, 3)), 12);
    expect(lattice.liftAt(const LatticeSpot(CellCoord(0, 0), 3, 3)), 0);
  });

  test('bridge walkers sort after their tile and the next one', () {
    // The same east-going bridge: road, near ramp, deck, far ramp.
    final state = stateWith(
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
    const ring = [255, 0, 0, 0, 0, 0, 0, 0];
    final lattice = PedestrianLattice(
      roadCells: pedestrianRoadCells(state),
      connectionCells: {
        for (final road in state.roads) road.cell,
        for (final bridge in state.bridges) ...bridge.waterCells,
      },
      maskFor: (role) => switch (role) {
        'road.end.se' || 'road.end.nw' => ring,
        'bridge.ramp.nw' || 'bridge.ramp.se' => ring,
        'bridge.body.se' => ring,
        _ => const [],
      },
      bridgeRoles: pedestrianBridgeRoles(state),
      deckLift: 12,
    );

    // Ground spots keep the plain ground depth: cell depth plus the
    // subtile offset (fx + fy).
    expect(
      lattice.walkerSortDepth(const LatticeSpot(CellCoord(0, 0), 3, 3)),
      closeTo(-0.125, 0.001),
    );
    expect(
      lattice.walkerSortDepth(const LatticeSpot(CellCoord(0, 0), 0, 0)),
      closeTo(-0.875, 0.001),
    );

    // Bridge spots bump past their own tile (integer depth) — even at
    // the tile's very back, where far-side lanes used to vanish
    // behind the art — and past the next tile along the span once a
    // subtile in, so boundary crossings never clip under the art.
    final rampBack = lattice.walkerSortDepth(
      const LatticeSpot(CellCoord(1, 0), 0, 0),
    );
    expect(rampBack, greaterThan(1));
    expect(rampBack, lessThan(2));
    expect(
      lattice.walkerSortDepth(const LatticeSpot(CellCoord(1, 0), 1, 1)),
      greaterThan(2),
      reason: 'one subtile in, already past the next tile',
    );
    // The far-side deck lane (y = 0) sits between the next tile and
    // the one beyond it.
    final farSide = lattice.walkerSortDepth(
      const LatticeSpot(CellCoord(2, 0), 7, 0),
    );
    expect(farSide, greaterThan(3));
    expect(farSide, lessThan(4));
    // And the front of a bridge tile never reaches two tiles ahead.
    expect(
      lattice.walkerSortDepth(const LatticeSpot(CellCoord(2, 0), 7, 7)),
      lessThan(4),
    );
  });

  test('malformed masks are ignored, not fatal', () {
    final cells = <CellCoord>{
      for (var column = 0; column < 5; column++) CellCoord(column, 0),
    };
    for (final mask in [
      <int>[255], // wrong length
      <int>[for (var i = 0; i < 8; i++) -1], // negative rows
      <int>[for (var i = 0; i < 8; i++) 256], // out of range
    ]) {
      final lattice = PedestrianLattice(
        roadCells: cells,
        connectionCells: cells,
        maskFor: (_) => mask,
      );
      expect(lattice.walkableCount, 0, reason: '$mask must not walk');
    }
  });
}

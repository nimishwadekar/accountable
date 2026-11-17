import 'package:citysim/content/content_models.dart' show RoadStyle;
import 'package:citysim/world/coordinates.dart';
import 'package:citysim/world/pedestrian_lattice.dart'
    show LatticeSpot, pedestrianRoadCells;
import 'package:citysim/world/road_sprite_resolver.dart'
    show roadEast, roadNorth, roadWest;
import 'package:citysim/world/vehicle_lattice.dart';
import 'package:citysim/world/world_state.dart';
import 'package:flutter_test/flutter_test.dart';

ParcelWorldState stateWith(List<RoadSegment> roads) => ParcelWorldState(
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
  structures: const [],
  props: const [],
  bridges: const [],
  constructions: const [],
  events: const [],
);

RoadSegment roadAt(String id, int column, int row) => RoadSegment(
  id: id,
  cell: CellCoord(column, row),
  style: RoadStyle.asphalt,
  pricePaid: 1,
  completedAtDay: 0,
);

/// A five-tile east-west road: three straights bracketed by end caps.
final roadRow = [
  for (var column = 0; column < 5; column++) roadAt('r$column', column, 0),
];

VehicleLattice latticeOver(
  List<RoadSegment> roads,
  Map<String, List<int>>? Function(String role) lanesFor,
) => VehicleLattice(
  roadCells: pedestrianRoadCells(stateWith(roads)),
  connectionCells: {for (final road in roads) road.cell},
  lanesFor: lanesFor,
);

/// Two-lane paint: an eastbound band on rows 4-5 (the south half,
/// right-hand traffic) and a westbound band on rows 2-3.
Map<String, List<int>> twoLanePaint(String role) => {
  'east-1': [for (var y = 0; y < 8; y++) y == 4 || y == 5 ? 255 : 0],
  'west-1': [for (var y = 0; y < 8; y++) y == 2 || y == 3 ? 255 : 0],
};

void main() {
  test('blank lanes drive nowhere', () {
    final lattice = latticeOver(roadRow, (_) => null);
    expect(lattice.isEmpty, isTrue);
    expect(lattice.dirsAt(const CellCoord(2, 0), 3, 4), 0);
    expect(lattice.surface.walkableCount, 0);
    expect(
      lattice.frontSpots(const [CellCoord(2, 1)]),
      isEmpty,
      reason: 'no paint, no fronts',
    );
  });

  test('lane paint carries its direction, crossings stack', () {
    final lattice = latticeOver(roadRow, twoLanePaint);
    expect(lattice.isEmpty, isFalse);
    // The westbound band on rows 2-3, eastbound on rows 4-5, and
    // nothing on the sidewalk rows.
    expect(lattice.dirsAt(const CellCoord(2, 0), 0, 2), roadWest);
    expect(lattice.dirsAt(const CellCoord(2, 0), 7, 5), roadEast);
    expect(lattice.dirsAt(const CellCoord(2, 0), 3, 0), 0);
    // The union surface steps within a band and across borders,
    // exactly like the pedestrian lattice.
    expect(
      lattice.surface.step(const LatticeSpot(CellCoord(1, 0), 7, 4), 1, 0),
      const LatticeSpot(CellCoord(2, 0), 0, 4),
    );
    expect(
      lattice.surface.step(const LatticeSpot(CellCoord(2, 0), 0, 2), 0, -1),
      isNull,
      reason: 'row 1 above the westbound band is not painted',
    );

    // A subtile painted for two directions is a crossing: cars
    // moving either way may pass through.
    final crossing = latticeOver(
      roadRow,
      (role) => {
        ...twoLanePaint(role),
        'north-1': [for (var y = 0; y < 8; y++) y == 4 ? 255 : 0],
      },
    );
    expect(crossing.dirsAt(const CellCoord(2, 0), 3, 4), roadEast | roadNorth);
  });

  test('front spots prefer the building-facing edge', () {
    // A building south of the road: its front is the road tile's
    // south edge, so paint there is preferred...
    final southPaint = latticeOver(
      roadRow,
      (role) => {
        'east-1': [for (var y = 0; y < 8; y++) y == 6 || y == 7 ? 255 : 0],
      },
    );
    final fronts = southPaint.frontSpots(const [CellCoord(2, 1)]);
    expect(fronts, isNotEmpty);
    expect(
      fronts.every((spot) => spot.cell == const CellCoord(2, 0) && spot.y >= 6),
      isTrue,
    );

    // ...and any lane subtile on a bordering cell serves when the
    // facing edge carries none.
    final northPaint = latticeOver(roadRow, twoLanePaint);
    final beside = northPaint.frontSpots(const [CellCoord(2, 1)]);
    expect(beside, isNotEmpty);
    expect(beside.every((spot) => spot.cell == const CellCoord(2, 0)), isTrue);
    expect(beside.any((spot) => spot.y >= 2 && spot.y <= 5), isTrue);
  });

  test('malformed lane masks are ignored, not fatal', () {
    final lattice = latticeOver(
      roadRow,
      (role) => role == 'road.straight.se'
          ? {
              'east-1': [255, 0, 0], // wrong length
              'west-1': [
                for (var y = 0; y < 8; y++) y == 2 || y == 3 ? 255 : 0,
              ],
            }
          : null,
    );
    expect(lattice.dirsAt(const CellCoord(2, 0), 3, 4), 0);
    expect(lattice.dirsAt(const CellCoord(2, 0), 3, 2), roadWest);
    // The union surface only carries the valid mask's subtiles on
    // the three straights — the end caps stay blank.
    expect(lattice.surface.walkableCount, 3 * 16);
  });

  test('lane indices are distinct bands of one direction', () {
    // Two eastbound lanes: east-1 on rows 1-2, east-2 on rows 4-5.
    final lattice = latticeOver(
      roadRow,
      (_) => {
        'east-1': [for (var y = 0; y < 8; y++) y == 1 || y == 2 ? 255 : 0],
        'east-2': [for (var y = 0; y < 8; y++) y == 4 || y == 5 ? 255 : 0],
      },
    );
    expect(lattice.laneIndexAt(const CellCoord(2, 0), 3, 1, roadEast), 1);
    expect(lattice.laneIndexAt(const CellCoord(2, 0), 3, 2, roadEast), 1);
    expect(lattice.laneIndexAt(const CellCoord(2, 0), 3, 4, roadEast), 2);
    expect(lattice.laneIndexAt(const CellCoord(2, 0), 3, 7, roadEast), isNull);
    // Both lanes accept eastbound steps — a direction is the OR of
    // its lanes.
    expect(lattice.dirsAt(const CellCoord(2, 0), 3, 1), roadEast);
    expect(lattice.dirsAt(const CellCoord(2, 0), 3, 5), roadEast);
  });

  test('cars centre on their lane, whatever its thickness', () {
    // A 2-wide lane: a car on either row sits half a subtile toward
    // the band's middle.
    final twoWide = latticeOver(roadRow, twoLanePaint);
    expect(
      twoWide.laneCenterOffset(
        const LatticeSpot(CellCoord(2, 0), 3, 4),
        roadEast,
      ),
      (0.0, 0.0625),
    );
    expect(
      twoWide.laneCenterOffset(
        const LatticeSpot(CellCoord(2, 0), 3, 5),
        roadEast,
      ),
      (0.0, -0.0625),
    );
    // A 1-wide lane centres on itself: no offset.
    final oneWide = latticeOver(
      roadRow,
      (_) => {
        'east-1': [for (var y = 0; y < 8; y++) y == 4 ? 255 : 0],
      },
    );
    expect(
      oneWide.laneCenterOffset(
        const LatticeSpot(CellCoord(2, 0), 3, 4),
        roadEast,
      ),
      (0.0, 0.0),
    );
    // Two same-direction lanes: the centre stops at the lane's own
    // extent, never across its sibling.
    final split = latticeOver(
      roadRow,
      (_) => {
        'east-1': [for (var y = 0; y < 8; y++) y == 1 || y == 2 ? 255 : 0],
        'east-2': [for (var y = 0; y < 8; y++) y == 4 || y == 5 ? 255 : 0],
      },
    );
    expect(
      split.laneCenterOffset(
        const LatticeSpot(CellCoord(2, 0), 3, 2),
        roadEast,
      ),
      (0.0, -0.0625),
      reason: 'east-1 centres between its own rows, ignoring east-2',
    );
    expect(
      split.laneCenterOffset(
        const LatticeSpot(CellCoord(2, 0), 3, 4),
        roadEast,
      ),
      (0.0, 0.0625),
      reason: 'east-2 centres between its own rows, ignoring east-1',
    );
  });
}

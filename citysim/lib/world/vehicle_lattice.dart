import 'dart:math' as math;

import 'coordinates.dart';
import 'pedestrian_lattice.dart'
    show LatticeSpot, PedestrianLattice, bridgeSurfaceLift;
import 'road_sprite_resolver.dart'
    show
        roadCrossingRole,
        roadEast,
        roadNeighborMask,
        roadNorth,
        roadSouth,
        roadSpriteRole,
        roadWest;
import 'world_state.dart' show propSubtilesPerAxis;

/// The direction a driving step moves, as connection bits: north is
/// row −1, east column +1, south row +1, west column −1.
int directionForDelta(int dx, int dy) => dy < 0
    ? roadNorth
    : dx > 0
    ? roadEast
    : dy > 0
    ? roadSouth
    : roadWest;

/// The grid step of a direction bit.
(int, int) deltaForDirection(int direction) => switch (direction) {
  roadNorth => (0, -1),
  roadEast => (1, 0),
  roadSouth => (0, 1),
  _ => (-1, 0),
};

/// The direction facing the other way — the one a car may never
/// step into, because cars do not reverse.
int oppositeDirection(int direction) =>
    (direction << 2 & 0x0F) | direction >> 2;

int _directionIndexOfName(String name) => switch (name) {
  'north' => 0,
  'east' => 1,
  'south' => 2,
  _ => 3,
};

int _directionIndexOfBit(int direction) => switch (direction) {
  roadNorth => 0,
  roadEast => 1,
  roadSouth => 2,
  _ => 3,
};

/// The surface cars may drive: every ground road cell's resolved
/// sprite role cut down to its authored lane subtiles — masks keyed
/// `direction-lane`, up to four lanes per direction — plus the
/// bridge cells as ramps and decks. Lane paint is the traffic
/// network the way walkable paint is the sidewalk network: nothing
/// drives until the editor paints lanes. A subtile painted for one
/// direction is a lane; one painted for several directions is a
/// crossing, where cars keep their heading until they step onto a
/// single-direction subtile again. Distinct lanes of one direction
/// are distinct bands: a car centres on whichever it drives and
/// never weaves between them, because a lateral step needs lateral
/// paint.
class VehicleLattice {
  /// Builds the lattice over the same cells the pedestrian lattice
  /// walks — ground roads minus bridge banks, which arrive through
  /// [bridgeRoles] as ramps instead. [lanesFor] looks up a sprite
  /// role's lane masks keyed `direction-lane`, or null when the
  /// role carries none.
  VehicleLattice({
    required Set<CellCoord> roadCells,
    required Set<CellCoord> connectionCells,
    required Map<String, List<int>>? Function(String role) lanesFor,
    this.bridgeRoles = const {},
    this.deckLift = 0,
  }) : surface = PedestrianLattice(
         roadCells: roadCells,
         connectionCells: connectionCells,
         maskFor: (role) => _unionMask(lanesFor(role)),
         bridgeRoles: bridgeRoles,
         deckLift: deckLift,
       ) {
    // Stepping, lift, and depth come from the union surface — every
    // subtile any lane paints. The lane identities stay here for
    // the driving rules, resolved per cell exactly as the surface
    // resolves its roles.
    for (final cell in roadCells) {
      final mask = roadNeighborMask(cell, connectionCells);
      final role =
          roadCrossingRole(mask, cell, connectionCells) ?? roadSpriteRole(mask);
      _addCellLanes(cell, lanesFor(role));
    }
    for (final entry in bridgeRoles.entries) {
      _addCellLanes(entry.key, lanesFor(entry.value));
    }
  }

  /// The union of every lane's paint — the surface a car may
  /// physically occupy, sharing the pedestrian lattice's stepping,
  /// lift, and depth.
  final PedestrianLattice surface;

  /// Bridge cells and their ramp/deck roles — the lift field's
  /// only providers today; any future elevation source joins here.
  final Map<CellCoord, String> bridgeRoles;

  /// The deck surface's height above the ground plane, world px.
  final double deckLift;

  /// Surface height at a continuous grid position, in world px —
  /// the lift field everything standing on the world reads: flat
  /// ground, a ramp's incline, a deck's full height, evaluated
  /// anywhere rather than only at lattice spots.
  double liftAtGrid(double col, double row) {
    final cell = CellCoord(col.floor(), row.floor());
    final role = bridgeRoles[cell];
    if (role == null) return 0;
    return bridgeSurfaceLift(
      role,
      col - cell.column - 0.5,
      row - cell.row - 0.5,
      deckLift,
    );
  }

  /// The lift field's gradient at a position, in world px per
  /// cell: (east-west, north-south). Central differences over a
  /// quarter cell — small enough to stay on a one-tile ramp strip
  /// when sampling across it, wide enough that seam crossings
  /// average, so tilts ease in and out instead of snapping.
  /// This is the elevation contract: anything that feeds
  /// [liftAtGrid] — bridges today, hills or overpasses tomorrow —
  /// tilts everything standing on the lattice with no further
  /// changes.
  (double, double) liftGradient(double col, double row) {
    const h = 0.25;
    return (
      (liftAtGrid(col + h, row) - liftAtGrid(col - h, row)) / (2 * h),
      (liftAtGrid(col, row + h) - liftAtGrid(col, row - h)) / (2 * h),
    );
  }

  /// Per cell, one packed int per subtile: for direction index i
  /// (N=0, E=1, S=2, W=3), bits 3i..3i+2 hold that direction's lane
  /// number, zero when unpainted.
  final Map<CellCoord, List<int>> _packed = {};

  /// Whether any cell carries lane paint at all.
  bool get isEmpty => _packed.isEmpty;

  /// The directions a subtile is painted for, as connection bits;
  /// zero means it is not a lane. A direction is painted when its
  /// lane nibble is non-zero — the lane number itself, one to four.
  int dirsAt(CellCoord cell, int x, int y) {
    final value = _packedAt(cell, x, y);
    return ((value & 7) != 0 ? 1 : 0) |
        ((value >> 3 & 7) != 0 ? 2 : 0) |
        ((value >> 6 & 7) != 0 ? 4 : 0) |
        ((value >> 9 & 7) != 0 ? 8 : 0);
  }

  /// The lane number a subtile carries for [direction], or null
  /// when it is not painted for that direction.
  int? laneIndexAt(CellCoord cell, int x, int y, int direction) {
    final lane =
        (_packedAt(cell, x, y) >> (3 * _directionIndexOfBit(direction))) & 7;
    return lane == 0 ? null : lane;
  }

  /// The lateral centre of the lane a car at [spot] driving
  /// [direction] occupies, as a grid offset in cell fractions: half
  /// the imbalance between how far its lane extends on either side.
  /// Cars sit at the centre of their lane whatever its painted
  /// thickness, and the run stops at other lanes of the same
  /// direction — a lane's centre is its own.
  (double, double) laneCenterOffset(LatticeSpot spot, int direction) {
    final lane = laneIndexAt(spot.cell, spot.x, spot.y, direction);
    if (lane == null) return (0, 0);
    final (dx, dy) = deltaForDirection(direction);
    // The two perpendicular subtile steps.
    final (p1x, p1y) = (-dy, dx);
    final (p2x, p2y) = (dy, -dx);
    var run1 = 0;
    var probe = spot;
    while (true) {
      final next = surface.step(probe, p1x, p1y);
      if (next == null ||
          laneIndexAt(next.cell, next.x, next.y, direction) != lane) {
        break;
      }
      run1++;
      probe = next;
    }
    var run2 = 0;
    probe = spot;
    while (true) {
      final next = surface.step(probe, p2x, p2y);
      if (next == null ||
          laneIndexAt(next.cell, next.x, next.y, direction) != lane) {
        break;
      }
      run2++;
      probe = next;
    }
    final steps = (run1 - run2) / 2;
    return (
      p1x * steps / propSubtilesPerAxis,
      p1y * steps / propSubtilesPerAxis,
    );
  }

  /// Painter's depth at a continuous grid position — the walker
  /// formula (bridge cells climb their per-cell ramp, staying
  /// above their tile's pieces and below the next tile's)
  /// evaluated where an extended body's deep end sits. Ground
  /// positions stay below their cell's depth, so ground actors
  /// never jump over the structures sharing their cell.
  double depthAt(double col, double row) {
    final cell = CellCoord(col.floor(), row.floor());
    final fx = col - cell.column;
    final fy = row - cell.row;
    final cellDepth = cell.column + cell.row;
    if (surface.isBridgeCell(cell)) {
      return cellDepth + 0.06 + (fx + fy) * 0.55;
    }
    return cellDepth + fx + fy - 1;
  }

  /// Lane spots that front a building: subtiles on the road cells
  /// bordering [footprint], preferring the building-facing edge —
  /// where a car stops closest to its door. Falls back to any lane
  /// subtile on a bordering cell when the facing edge carries none.
  List<LatticeSpot> frontSpots(Iterable<CellCoord> footprint) {
    final facing = <LatticeSpot>{};
    final beside = <LatticeSpot>{};
    for (final cell in footprint) {
      void collect(CellCoord road, bool Function(int x, int y) onFacingEdge) {
        if (!_packed.containsKey(road)) return;
        for (var y = 0; y < 8; y++) {
          for (var x = 0; x < 8; x++) {
            if (dirsAt(road, x, y) == 0) continue;
            (onFacingEdge(x, y) ? facing : beside).add(LatticeSpot(road, x, y));
          }
        }
      }

      // The road cell's edge shared with the building is the front.
      collect(cell.offset(1, 0), (x, y) => x == 0);
      collect(cell.offset(-1, 0), (x, y) => x == 7);
      collect(cell.offset(0, -1), (x, y) => y == 7);
      collect(cell.offset(0, 1), (x, y) => y == 0);
    }
    final pool = facing.isNotEmpty ? facing : beside;
    return pool.toList()..sort((a, b) {
      final cell = a.cell.compareTo(b.cell);
      if (cell != 0) return cell;
      if (a.y != b.y) return a.y.compareTo(b.y);
      return a.x.compareTo(b.x);
    });
  }

  int _packedAt(CellCoord cell, int x, int y) => _packed[cell]?[y * 8 + x] ?? 0;

  void _addCellLanes(CellCoord cell, Map<String, List<int>>? lanes) {
    if (lanes == null) return;
    final packed = List<int>.filled(64, 0);
    var any = false;
    for (final entry in lanes.entries) {
      final parts = entry.key.split('-');
      final laneNumber = parts.length == 2 ? int.tryParse(parts[1]) : null;
      if (parts.length != 2 ||
          laneNumber == null ||
          laneNumber < 1 ||
          laneNumber > 4) {
        continue;
      }
      final index = _directionIndexOfName(parts[0]);
      final mask = entry.value;
      if (mask.length != 8) continue;
      for (var y = 0; y < 8; y++) {
        final row = mask[y].clamp(0, 255).toInt();
        for (var x = 0; x < 8; x++) {
          if ((row >> x & 1) == 1) {
            packed[y * 8 + x] |= laneNumber << (3 * index);
            any = true;
          }
        }
      }
    }
    if (any) _packed[cell] = packed;
  }

  /// Every lane's paint OR-ed together — the union surface a car
  /// may stand on. Malformed masks are skipped, and the pedestrian
  /// lattice drops any all-zero result.
  static List<int> _unionMask(Map<String, List<int>>? lanes) {
    if (lanes == null || lanes.isEmpty) return const [];
    final rows = List<int>.filled(8, 0);
    for (final mask in lanes.values) {
      if (mask.length != 8) continue;
      for (var y = 0; y < 8; y++) {
        rows[y] |= mask[y].clamp(0, 255).toInt();
      }
    }
    return rows;
  }
}

/// The screen rotation that pitches a standing sprite onto a
/// slope, in radians for `Canvas.rotate`, from the lift gradient
/// in world px per cell and the sprite's grid heading: the angle
/// between the heading's flat-ground screen trajectory and its
/// trajectory on the tangent plane. A rigid rotation — lengths
/// and the silhouette are preserved — at the cost of banking the
/// lateral axis by the same angle, so the far wheel line floats
/// slightly on slopes. Flat ground is zero. (The alternative
/// affine shear plants both wheel lines exactly but compresses
/// screen verticals in proportion to the slope — 37.5% on the
/// seeded 12-px ramps — which playtesting found too drastic.)
double pitchRotation(
  double gradientCol,
  double gradientRow,
  int headingDx,
  int headingDy,
) {
  // The heading's screen trajectory per cell of travel, flat and
  // sloped: a cell east is (32, 16), a cell north (32, −16), and
  // the slope subtracts the lift gained along the heading.
  final du = 32.0 * (headingDx - headingDy);
  final flat = 16.0 * (headingDx + headingDy);
  final sloped = flat - (gradientCol * headingDx + gradientRow * headingDy);
  return math.atan2(sloped, du) - math.atan2(flat, du);
}

/// A blank lattice for the sim's first frame: nothing is drivable
/// until the first reconcile paints it.
final VehicleLattice blankVehicleLattice = VehicleLattice(
  roadCells: const {},
  connectionCells: const {},
  lanesFor: (_) => null,
);

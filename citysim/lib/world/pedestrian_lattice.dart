import 'dart:math' as math;

import '../content/content_models.dart' show PedestrianContent;
import 'coordinates.dart';
import 'road_sprite_resolver.dart';
import 'world_state.dart'
    show ParcelWorldState, WorldConstructionKind, propSubtilesPerAxis;

/// Ground road cells pedestrians may walk: every completed road except
/// bridge banks. Banks are genuine road tiles — the road network
/// continues onto them and the ramp art draws over the road tile — so
/// a bank resolves as a plain straight in the road-role pipeline and a
/// painted straight mask would put people under the ramps. Ramps and
/// decks are elevated bridge parts; people stay off them (until
/// bridge roles carry their own walkable paint).
Set<CellCoord> pedestrianRoadCells(ParcelWorldState state) {
  final rampCells = <CellCoord>{
    for (final bridge in state.bridges) ...[bridge.nearBank, bridge.farBank],
    for (final job in state.constructions)
      if (job.kind == WorldConstructionKind.bridge) ...[
        ?job.nearBank,
        ?job.farBank,
      ],
  };
  return {for (final road in state.roads) road.cell}.difference(rampCells);
}

/// Bridge cells and their sprite roles for the walkable lattice: ramps
/// at the banks, deck tiles over the water. Completed bridges only —
/// the far ramp exists on completion, and a half-built deck is a
/// construction site.
Map<CellCoord, String> pedestrianBridgeRoles(ParcelWorldState state) {
  final roles = <CellCoord, String>{};
  for (final bridge in state.bridges) {
    roles[bridge.nearBank] = bridgeRampRole(
      bridge.nearBank,
      bridge.waterCells.first,
    );
    roles[bridge.farBank] = bridgeRampRole(
      bridge.farBank,
      bridge.waterCells.last,
    );
    final body = bridgeBodyRole(bridge.nearBank, bridge.farBank);
    for (final cell in bridge.waterCells) {
      roles[cell] = body;
    }
  }
  return roles;
}

/// How many walkers a town of [population] carries: street life as
/// a percentage of the town's people, floored at one walker once
/// anyone lives there — streets fill as families arrive — and
/// bounded by the painted sidewalk that actually exists
/// ([walkableCount]), so an unpainted world stays empty no matter
/// how many people live in it. A zero percent turns pedestrians
/// off.
int pedestrianTargetCount(
  int population,
  PedestrianContent pedestrians,
  int walkableCount,
) {
  if (pedestrians.populationPercent <= 0 || population <= 0) return 0;
  return math.min(
    math.max(1, (population * pedestrians.populationPercent / 100).floor()),
    walkableCount,
  );
}

/// World-px lift of a point on a bridge tile's surface, by grid
/// fraction (both −0.5…0.5 from the cell centre). Ramp roles rise
/// linearly from their bank end to the deck's [deckLift] at the water
/// end — the incline measured straight off the art — with the high
/// end named by the role's screen quadrant (ramp.nw is low at west,
/// high at east, and so on). Deck roles sit flat at full lift; road
/// roles lift nothing.
double bridgeSurfaceLift(String role, double fx, double fy, double deckLift) =>
    switch (role) {
      'bridge.ramp.nw' => deckLift * (fx + 0.5),
      'bridge.ramp.se' => deckLift * (0.5 - fx),
      'bridge.ramp.ne' => deckLift * (fy + 0.5),
      'bridge.ramp.sw' => deckLift * (0.5 - fy),
      _ => role.startsWith('bridge.body') ? deckLift : 0,
    };

/// The four corners of a bridge tile's surface — north, east, south,
/// west — as grid fractions with their lifts. This is the plane
/// pedestrians walk and the line the renderer splits the sprite
/// along: flat at deck height for bodies, sheared from bank to deck
/// for ramps.
List<(double, double, double)> bridgeSurfaceCorners(
  String role,
  double deckLift,
) => [
  (0, -0.5, bridgeSurfaceLift(role, 0, -0.5, deckLift)),
  (0.5, 0, bridgeSurfaceLift(role, 0.5, 0, deckLift)),
  (0, 0.5, bridgeSurfaceLift(role, 0, 0.5, deckLift)),
  (-0.5, 0, bridgeSurfaceLift(role, -0.5, 0, deckLift)),
];

/// A pedestrian's position on the walkable lattice: a road cell plus a
/// subtile of its 8×8 grid. `x` indexes the column axis (0 = west
/// edge) and `y` the row axis (0 = north edge), exactly like the prop
/// subtile lattice.
class LatticeSpot {
  const LatticeSpot(this.cell, this.x, this.y);

  final CellCoord cell;
  final int x;
  final int y;

  @override
  bool operator ==(Object other) =>
      other is LatticeSpot &&
      other.cell == cell &&
      other.x == x &&
      other.y == y;

  @override
  int get hashCode => Object.hash(cell, x, y);

  @override
  String toString() => 'LatticeSpot(${cell.column},${cell.row} $x,$y)';
}

/// The surface pedestrians may walk: every ground road cell's resolved
/// sprite role cut down to its authored walkable subtiles, plus the
/// bridge cells — banks as ramps, water as decks. The mask a tile uses
/// is the one for the art it renders — a pelican crossing approach
/// uses the crossing role's mask, so the painted stripe band is the
/// only way across that road. Blank roles contribute nothing, which is
/// how the content ships: nothing walks until the editor paints
/// sidewalks and crossings.
class PedestrianLattice {
  /// Builds the lattice. [roadCells] is the ground walkable surface —
  /// roads minus bridge banks, which arrive through [bridgeRoles] as
  /// ramps instead. [connectionCells] is the set road roles resolve
  /// against — ground roads plus bridge water cells, matching the
  /// renderer. [maskFor] looks up a sprite role's eight row bytes.
  /// [bridgeRoles] maps bridge cells to their ramp/deck roles, and
  /// [deckLift] is the deck surface's height above ground, world px.
  PedestrianLattice({
    required Set<CellCoord> roadCells,
    required Set<CellCoord> connectionCells,
    required List<int> Function(String role) maskFor,
    Map<CellCoord, String> bridgeRoles = const {},
    this.deckLift = 0,
  }) {
    for (final cell in roadCells) {
      final mask = roadNeighborMask(cell, connectionCells);
      final role =
          roadCrossingRole(mask, cell, connectionCells) ?? roadSpriteRole(mask);
      _add(cell, role, maskFor(role));
    }
    for (final entry in bridgeRoles.entries) {
      _add(entry.key, entry.value, maskFor(entry.value));
    }
    _spots = [
      for (final entry in _masks.entries)
        for (var y = 0; y < 8; y++)
          for (var x = 0; x < 8; x++)
            if ((entry.value[y] >> x & 1) == 1) LatticeSpot(entry.key, x, y),
    ];
  }

  void _add(CellCoord cell, String role, List<int> rows) {
    if (rows.length != 8 ||
        rows.any((row) => row < 0 || row > 255) ||
        rows.every((row) => row == 0)) {
      return;
    }
    _masks[cell] = rows;
    _roles[cell] = role;
  }

  final Map<CellCoord, List<int>> _masks = {};
  final Map<CellCoord, String> _roles = {};

  /// The deck surface's height above the ground plane, world px.
  final double deckLift;

  /// Every walkable subtile, for spawn sampling.
  late final List<LatticeSpot> _spots;

  /// How many subtiles are walkable; zero means nobody walks.
  int get walkableCount => _spots.length;

  /// World-px lift at a spot: how far above the ground plane a person
  /// standing there renders — the deck's elevation on bridge tiles,
  /// the linear incline part-way across a ramp, nothing on roads.
  double liftAt(LatticeSpot spot) {
    final role = _roles[spot.cell];
    if (role == null) return 0;
    return bridgeSurfaceLift(
      role,
      (spot.x + 0.5) / propSubtilesPerAxis - 0.5,
      (spot.y + 0.5) / propSubtilesPerAxis - 0.5,
      deckLift,
    );
  }

  /// Whether the cell is part of a bridge — a ramp bank or a deck
  /// span — rather than plain ground.
  bool isBridgeCell(CellCoord cell) =>
      _roles[cell]?.startsWith('bridge.') ?? false;

  /// Painter's depth for a walker at [spot]. Ground spots keep their
  /// plain ground depth. Bridge spots climb a ramp through the cell:
  /// just above their own tile's surface piece (cell + 0.05) at the
  /// back, and past the next tile's pieces (cell + 1.02 posts,
  /// + 1.05 surface) before the front edge — so crossing a tile
  /// boundary never dips the walker under the next tile's art —
  /// while staying below the next cell's own back-corner walker, so
  /// walkers still order front-to-back across cells.
  double walkerSortDepth(LatticeSpot spot) {
    final cellDepth = spot.cell.column + spot.cell.row;
    // The ground-plane offset: fx + fy for the subtile centre.
    final ground = cellDepth + (spot.x + spot.y + 1) / propSubtilesPerAxis - 1;
    if (!isBridgeCell(spot.cell)) return ground;
    // Back corner: cell + 0.129, above the surface piece. Front
    // corner: cell + 1.091, above the next tile's surface (+ 1.05)
    // and below the next cell's back corner (+ 1.129).
    return cellDepth +
        0.06 +
        (spot.x + spot.y + 1) * 1.1 / (propSubtilesPerAxis * 2);
  }

  bool isWalkable(CellCoord cell, int x, int y) {
    final rows = _masks[cell];
    return rows != null &&
        x >= 0 &&
        x < 8 &&
        y >= 0 &&
        y < 8 &&
        (rows[y] >> x & 1) == 1;
  }

  bool containsSpot(LatticeSpot spot) => isWalkable(spot.cell, spot.x, spot.y);

  /// One step of lattice movement: [dx]/[dy] are −1, 0, or 1 along the
  /// column/row axes. Steps off a cell's edge flow into the matching
  /// subtile of the neighbouring cell, so painted lanes continue
  /// across tile borders. Returns null when the target is not
  /// walkable.
  LatticeSpot? step(LatticeSpot spot, int dx, int dy) {
    var cell = spot.cell;
    var x = spot.x + dx;
    var y = spot.y + dy;
    if (x < 0) {
      cell = cell.offset(-1, 0);
      x = 7;
    } else if (x > 7) {
      cell = cell.offset(1, 0);
      x = 0;
    }
    if (y < 0) {
      cell = cell.offset(0, -1);
      y = 7;
    } else if (y > 7) {
      cell = cell.offset(0, 1);
      y = 0;
    }
    return isWalkable(cell, x, y) ? LatticeSpot(cell, x, y) : null;
  }

  /// The walkable spots four-adjacent to [spot] — everywhere a
  /// pedestrian standing there may step next.
  List<LatticeSpot> neighborsOf(LatticeSpot spot) {
    final neighbors = <LatticeSpot>[];
    for (final delta in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final next = step(spot, delta.$1, delta.$2);
      if (next != null) neighbors.add(next);
    }
    return neighbors;
  }

  /// A random walkable spot with at least one walkable neighbour, or
  /// null when nothing is walkable. Pedestrians spawn on these.
  LatticeSpot? randomSpawn(math.Random random) {
    if (_spots.isEmpty) return null;
    for (var attempts = 0; attempts < 16; attempts++) {
      final spot = _spots[random.nextInt(_spots.length)];
      if (neighborsOf(spot).isNotEmpty) return spot;
    }
    return null;
  }

  /// A walkable spot in front of a building — a painted subtile in a
  /// road cell bordering [footprint], on the edge facing the
  /// building, so a walker appears at its doorstep. When the facing
  /// edge carries no paint (a road role may paint only one side),
  /// any painted subtile in a bordering cell still counts. Null
  /// when nothing walkable fronts the footprint.
  LatticeSpot? frontSpot(Iterable<CellCoord> footprint, math.Random random) {
    final facing = <LatticeSpot>{};
    final beside = <LatticeSpot>{};
    for (final cell in footprint) {
      void collect(CellCoord road, bool Function(int x, int y) isFacingEdge) {
        final rows = _masks[road];
        if (rows == null) return;
        for (var y = 0; y < 8; y++) {
          for (var x = 0; x < 8; x++) {
            if ((rows[y] >> x & 1) != 1) continue;
            final spot = LatticeSpot(road, x, y);
            (isFacingEdge(x, y) ? facing : beside).add(spot);
          }
        }
      }

      // The road cell's edge shared with the building is the front:
      // a road east of a footprint cell faces it with its west edge.
      collect(cell.offset(1, 0), (x, y) => x == 0);
      collect(cell.offset(-1, 0), (x, y) => x == 7);
      collect(cell.offset(0, -1), (x, y) => y == 7);
      collect(cell.offset(0, 1), (x, y) => y == 0);
    }
    // Only spots a walker can leave — a front without outlets would
    // strand a pedestrian mid-walk cycle.
    for (final pool in [facing, beside]) {
      final candidates = [
        for (final spot in pool)
          if (neighborsOf(spot).isNotEmpty) spot,
      ];
      if (candidates.isNotEmpty) {
        return candidates[random.nextInt(candidates.length)];
      }
    }
    return null;
  }
}

import 'coordinates.dart';
import 'terrain_provider.dart';
import 'world_state.dart';

import '../content/content_bundle.dart';

/// The road side a building faces by default: door-on-road sides win
/// over around-the-corner ones, and the camera-facing street facade
/// wins first — so the order is south, east, north, west. Falls back
/// to south, the left-variant default, when no road borders the
/// footprint yet (a placement preview before the roads exist).
String facingForRoadSides(Set<String> sides) {
  for (final side in const ['south', 'east', 'north', 'west']) {
    if (sides.contains(side)) return side;
  }
  return 'south';
}

/// The road side a door swap moves to: the best side that draws with
/// the other art variant, so every flip visibly turns the building —
/// sides sharing the current variant (south/north or east/west) are
/// never offered. Callers only offer the swap once roads border both
/// variants, so the fallback arm just keeps the flip total.
String flipFacing(String facing, Set<String> roadSides) {
  final goingLeft = facingArtKey(facing) == 'right';
  for (final side
      in goingLeft ? const ['south', 'north'] : const ['east', 'west']) {
    if (roadSides.contains(side)) return side;
  }
  return goingLeft ? 'south' : 'east';
}

class WorldQueries {
  WorldQueries(this.state, this.terrainProvider)
    : ownedParcels = state.parcelsByCoord,
      roadsByCell = state.roadsByCell,
      structuresByCell = state.structuresByCell,
      terrainByCell = {
        for (final parcel in state.parcels)
          for (final cell in parcel.terrain) cell.coord: cell,
      },
      roadChunks = _groupByChunks(state.roads, (road) => [road.cell]),
      structureChunks = _groupByChunks(
        state.structures,
        (structure) => structure.footprint,
      ),
      propChunks = _groupByChunks(state.props, (prop) => [prop.cell]),
      propsByCell = _groupByCell(state.props, (prop) => prop.cell),
      bridgeChunks = _groupByChunks(
        state.bridges,
        (bridge) => [...bridge.waterCells, bridge.nearBank, bridge.farBank],
      ),
      parcelChunks = _groupByChunks(
        state.parcels,
        (parcel) => parcel.terrain.map((cell) => cell.coord).toList(),
      );

  final ParcelWorldState state;
  final TerrainProvider terrainProvider;
  final Map<ParcelCoord, OwnedParcel> ownedParcels;
  final Map<CellCoord, RoadSegment> roadsByCell;
  final Map<CellCoord, PlacedStructure> structuresByCell;
  final Map<CellCoord, TerrainCell> terrainByCell;
  final Map<WorldChunkCoord, List<RoadSegment>> roadChunks;
  final Map<WorldChunkCoord, List<PlacedStructure>> structureChunks;
  final Map<WorldChunkCoord, List<PlacedProp>> propChunks;

  /// Several props may share a tile; the list holds them all.
  final Map<CellCoord, List<PlacedProp>> propsByCell;

  final Map<WorldChunkCoord, List<CompletedBridge>> bridgeChunks;
  final Map<WorldChunkCoord, List<OwnedParcel>> parcelChunks;

  late final Map<String, PlacedProp> propsById = {
    for (final prop in state.props) prop.id: prop,
  };

  /// One prop per subtile: the anchor key is (cell, subtileX, subtileY).
  late final Map<(CellCoord, int, int), PlacedProp> propsByAnchor = {
    for (final prop in state.props)
      (prop.cell, prop.subtileX, prop.subtileY): prop,
  };

  /// Completed bridge deck cells — valid ground for props.
  late final Set<CellCoord> bridgeDeckCells = Set.unmodifiable({
    for (final bridge in state.bridges) ...bridge.waterCells,
  });

  /// Cells reserved by PENDING construction only. Unlike
  /// [reservedCells] — which also folds in completed bridge decks so
  /// new construction avoids them — this is the set new props must
  /// avoid, because a prop may stand on a completed deck.
  late final Set<CellCoord> constructionReservedCells = Set.unmodifiable(
    state.reservedCells,
  );

  late final Set<CellCoord> _reservedCells = Set.unmodifiable({
    ...state.reservedCells,
    ...state.bridges.expand((bridge) => bridge.waterCells),
    for (final bridge in state.bridges) bridge.nearBank,
    for (final bridge in state.bridges) bridge.farBank,
  });
  late final Set<CellCoord> _reachableLandCells = Set.unmodifiable(
    _computeReachableLandCells(),
  );

  bool ownsParcel(ParcelCoord coord) => ownedParcels.containsKey(coord);

  bool ownsCell(CellCoord coord) => ownedParcels.containsKey(
    parcelForCell(coord, parcelSize: state.parcelSize),
  );

  TerrainCell terrainAt(CellCoord coord) =>
      terrainByCell[coord] ?? terrainProvider.sample(coord, state.seed);

  Set<CellCoord> get reservedCells => _reservedCells;

  Set<CellCoord> get reachableLandCells => _reachableLandCells;

  Set<CellCoord> _computeReachableLandCells() {
    final start = CellCoord(state.parcelSize ~/ 2, state.parcelSize ~/ 2);
    if (!ownsCell(start) || !terrainAt(start).isLand) return <CellCoord>{};
    final bridgeLinks = <CellCoord, Set<CellCoord>>{};
    for (final bridge in state.bridges) {
      bridgeLinks
          .putIfAbsent(bridge.nearBank, () => <CellCoord>{})
          .add(bridge.farBank);
      bridgeLinks
          .putIfAbsent(bridge.farBank, () => <CellCoord>{})
          .add(bridge.nearBank);
    }
    final reached = <CellCoord>{start};
    final queue = <CellCoord>[start];
    for (var cursor = 0; cursor < queue.length; cursor++) {
      final current = queue[cursor];
      final candidates = <CellCoord>[
        ...current.neighbors,
        ...?bridgeLinks[current],
      ];
      for (final next in candidates) {
        if (reached.contains(next) ||
            !ownsCell(next) ||
            !terrainAt(next).isLand) {
          continue;
        }
        reached.add(next);
        queue.add(next);
      }
    }
    return reached;
  }

  bool isLandReachable(CellCoord cell) =>
      reachableLandCells.contains(cell) && terrainAt(cell).isLand;

  bool footprintIsVacant(Iterable<CellCoord> cells) {
    final occupied = <CellCoord>{
      ...roadsByCell.keys,
      ...structuresByCell.keys,
      ...propsByCell.keys,
      ...reservedCells,
    };
    return cells.every((cell) => !occupied.contains(cell));
  }

  /// The prop placement surface: ground and completed roads. Bridge
  /// decks were briefly part of it (2026-11-11), but aiming the fine
  /// subtile lattice on raised, art-covered decks felt finicky —
  /// placing objects on bridges is future work (see the prop plan's
  /// future notes).
  bool cellAcceptsProps(CellCoord cell) =>
      terrainAt(cell).isLand || roadsByCell.containsKey(cell);

  /// The prop standing at a subtile, if any.
  PlacedProp? propAt(CellCoord cell, int subtileX, int subtileY) =>
      propsByAnchor[(cell, subtileX, subtileY)];

  /// A building's road frontage must run along a whole side of its
  /// footprint: every cell on one edge of the footprint has a
  /// completed ground road beside it — connectivity to the starter
  /// road is not required, any road counts. Bridge banks are roads;
  /// elevated decks are not, so a door never opens onto a bridge.
  /// Footprints larger than 1×1 therefore need a road along an
  /// entire side, not a single touching corner; for a 1×1 footprint
  /// the rule is exactly "any adjacent road".
  bool buildingHasRoadAccess(Iterable<CellCoord> footprint) {
    final cells = footprint.toSet();
    if (cells.isEmpty) return false;
    var minColumn = cells.first.column;
    var maxColumn = cells.first.column;
    var minRow = cells.first.row;
    var maxRow = cells.first.row;
    for (final cell in cells) {
      if (cell.column < minColumn) minColumn = cell.column;
      if (cell.column > maxColumn) maxColumn = cell.column;
      if (cell.row < minRow) minRow = cell.row;
      if (cell.row > maxRow) maxRow = cell.row;
    }
    bool sideIsLined(
      bool Function(CellCoord cell) onSide,
      CellCoord Function(CellCoord cell) roadNeighbor,
    ) {
      for (final cell in cells) {
        if (!onSide(cell)) continue;
        if (!roadsByCell.containsKey(roadNeighbor(cell))) return false;
      }
      return true;
    }

    return sideIsLined(
          (cell) => cell.row == minRow,
          (cell) => CellCoord(cell.column, cell.row - 1),
        ) ||
        sideIsLined(
          (cell) => cell.row == maxRow,
          (cell) => CellCoord(cell.column, cell.row + 1),
        ) ||
        sideIsLined(
          (cell) => cell.column == minColumn,
          (cell) => CellCoord(cell.column - 1, cell.row),
        ) ||
        sideIsLined(
          (cell) => cell.column == maxColumn,
          (cell) => CellCoord(cell.column + 1, cell.row),
        );
  }

  /// Road sides bordering a footprint, as compass names. The projection
  /// maps grid north/east to the screen-right half of the diamond
  /// (up-right and down-right) and grid south/west to the screen-left
  /// half, so a road on the north or east side means the door can face
  /// right, and one on the south or west side means it can face left. A
  /// road behind the building still counts: the door goes on the visible
  /// facade around the corner from it, on the same screen side.
  Set<String> adjacentRoadSides(Iterable<CellCoord> footprint) {
    const sideNames = ['north', 'east', 'south', 'west'];
    final footprintSet = footprint.toSet();
    final sides = <String>{};
    for (final cell in footprintSet) {
      final neighbors = cell.neighbors; // north, east, south, west.
      for (var side = 0; side < 4; side++) {
        if (footprintSet.contains(neighbors[side]) ||
            !roadsByCell.containsKey(neighbors[side])) {
          continue;
        }
        sides.add(sideNames[side]);
      }
    }
    return sides;
  }

  /// The completed-road section containing [cell]: the maximal
  /// straight run between junctions (3+ road neighbours), elbows, or
  /// dead ends — the stretch a road tap selects. Returns an empty
  /// list when the cell holds no completed road.
  List<CellCoord> roadSectionAt(CellCoord cell) {
    if (!roadsByCell.containsKey(cell)) return const [];
    bool isRoad(CellCoord candidate) => roadsByCell.containsKey(candidate);
    int roadNeighbourCount(CellCoord candidate) =>
        candidate.neighbors.where(isRoad).length;
    // The run's axis: a cell with an east or west road neighbour is
    // part of a horizontal run (junctions and elbows pick horizontal
    // by convention).
    final horizontal = isRoad(cell.offset(1, 0)) || isRoad(cell.offset(-1, 0));
    final dx = horizontal ? 1 : 0;
    final dy = horizontal ? 0 : 1;

    List<CellCoord> walk(int stepX, int stepY) {
      final run = <CellCoord>[];
      var current = cell;
      while (true) {
        final next = current.offset(stepX, stepY);
        if (!isRoad(next) || roadNeighbourCount(next) >= 3) break;
        // A turn: the next tile's road continues perpendicular to
        // this run — the section ends before it.
        if (isRoad(next.offset(dy, dx)) || isRoad(next.offset(-dy, -dx))) {
          break;
        }
        run.add(next);
        current = next;
      }
      return run;
    }

    final before = walk(-dx, -dy);
    final after = walk(dx, dy);
    return [...before.reversed, cell, ...after];
  }

  List<RoadSegment> roadsInBounds({
    required int left,
    required int right,
    required int top,
    required int bottom,
  }) => _itemsInBounds(roadChunks, left, right, top, bottom);

  List<PlacedStructure> structuresInBounds({
    required int left,
    required int right,
    required int top,
    required int bottom,
  }) => _itemsInBounds(structureChunks, left, right, top, bottom);

  List<PlacedProp> propsInBounds({
    required int left,
    required int right,
    required int top,
    required int bottom,
  }) => _itemsInBounds(propChunks, left, right, top, bottom);

  List<CompletedBridge> bridgesInBounds({
    required int left,
    required int right,
    required int top,
    required int bottom,
  }) => _itemsInBounds(bridgeChunks, left, right, top, bottom);

  List<OwnedParcel> parcelsInBounds({
    required int left,
    required int right,
    required int top,
    required int bottom,
  }) => _itemsInBounds(parcelChunks, left, right, top, bottom);
}

Map<WorldChunkCoord, List<T>> _groupByChunks<T>(
  Iterable<T> values,
  Iterable<CellCoord> Function(T value) cellsFor,
) {
  final result = <WorldChunkCoord, List<T>>{};
  for (final value in values) {
    for (final cell in cellsFor(value)) {
      result.putIfAbsent(WorldChunkCoord.fromCell(cell), () => []).add(value);
    }
  }
  return {
    for (final entry in result.entries)
      entry.key: List.unmodifiable(entry.value),
  };
}

Map<CellCoord, List<T>> _groupByCell<T>(
  Iterable<T> values,
  CellCoord Function(T value) cellFor,
) {
  final result = <CellCoord, List<T>>{};
  for (final value in values) {
    result.putIfAbsent(cellFor(value), () => []).add(value);
  }
  return {
    for (final entry in result.entries)
      entry.key: List.unmodifiable(entry.value),
  };
}

List<T> _itemsInBounds<T>(
  Map<WorldChunkCoord, List<T>> chunks,
  int left,
  int right,
  int top,
  int bottom,
) {
  final found = <T>{};
  for (
    var y = floorDivide(top, worldRenderChunkSize);
    y <= floorDivide(bottom, worldRenderChunkSize);
    y++
  ) {
    for (
      var x = floorDivide(left, worldRenderChunkSize);
      x <= floorDivide(right, worldRenderChunkSize);
      x++
    ) {
      found.addAll(chunks[WorldChunkCoord(x, y)] ?? const []);
    }
  }
  return found.toList();
}

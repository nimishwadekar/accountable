import 'coordinates.dart';
import 'terrain_provider.dart';
import 'world_state.dart';

/// Door side for a building plan from its road frontage halves: any
/// frontage on the screen-right half faces the door right, any on the
/// left half faces it left. Both halves default to right — the player can
/// swap while the plan is unfinished.
String doorFacingForSides(Set<String> sides) =>
    sides.contains('right') ? 'right' : 'left';

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
  final Map<WorldChunkCoord, List<CompletedBridge>> bridgeChunks;
  final Map<WorldChunkCoord, List<OwnedParcel>> parcelChunks;

  late final Set<CellCoord> _reservedCells = Set.unmodifiable({
    ...state.reservedCells,
    ...state.bridges.expand((bridge) => bridge.waterCells),
    for (final bridge in state.bridges) bridge.nearBank,
    for (final bridge in state.bridges) bridge.farBank,
  });
  late final Set<CellCoord> _reachableLandCells = Set.unmodifiable(
    _computeReachableLandCells(),
  );
  late final Set<CellCoord> _connectedRoadCells = Set.unmodifiable(
    _computeConnectedRoadCells(),
  );
  late final Set<CellCoord> _completedRoadCells = Set.unmodifiable({
    ...roadsByCell.keys,
    ...state.bridges.expand((bridge) => bridge.waterCells),
  });

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

  Set<CellCoord> get connectedRoadCells => _connectedRoadCells;

  Set<CellCoord> get completedRoadCells => _completedRoadCells;

  Set<CellCoord> _computeConnectedRoadCells() {
    final roads = <CellCoord>{
      ...roadsByCell.keys,
      ...state.bridges.expand((bridge) => bridge.waterCells),
    };
    CellCoord? start;
    for (final road in state.roads) {
      if (road.id == 'road-start') {
        start = road.cell;
        break;
      }
    }
    if (start == null) return <CellCoord>{};
    final reached = <CellCoord>{start};
    final queue = <CellCoord>[start];
    for (var cursor = 0; cursor < queue.length; cursor++) {
      final current = queue[cursor];
      for (final next in current.neighbors) {
        if (!roads.contains(next) || !reached.add(next)) continue;
        queue.add(next);
      }
    }
    return reached;
  }

  bool isLandReachable(CellCoord cell) =>
      reachableLandCells.contains(cell) && terrainAt(cell).isLand;

  bool isRoadConnected(CellCoord cell) => connectedRoadCells.contains(cell);

  bool footprintIsVacant(Iterable<CellCoord> cells) {
    final occupied = <CellCoord>{
      ...roadsByCell.keys,
      ...structuresByCell.keys,
      ...reservedCells,
    };
    return cells.every((cell) => !occupied.contains(cell));
  }

  /// A building's road frontage must run along a whole side of its
  /// footprint: every cell on one edge of the footprint has a
  /// connected road beside it. Footprints larger than 1×1 therefore
  /// need a road along an entire side, not a single touching corner;
  /// for a 1×1 footprint the rule is exactly "any adjacent road".
  bool buildingHasRoadAccess(Iterable<CellCoord> footprint) {
    final cells = footprint.toSet();
    if (cells.isEmpty) return false;
    final connectedRoads = connectedRoadCells;
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
        if (!connectedRoads.contains(roadNeighbor(cell))) return false;
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

  /// Door halves with road frontage for a footprint. The projection maps
  /// grid north/east to the screen-right half of the diamond (up-right and
  /// down-right) and grid south/west to the screen-left half, so a road on
  /// the north or east side means the door can face right, and one on the
  /// south or west side means it can face left. A road behind the
  /// building still counts: the door goes on the visible facade around
  /// the corner from it, on the same screen side.
  Set<String> adjacentDoorSides(Iterable<CellCoord> footprint) {
    final connectedRoads = connectedRoadCells;
    final footprintSet = footprint.toSet();
    final sides = <String>{};
    for (final cell in footprintSet) {
      final neighbors = cell.neighbors; // north, east, south, west.
      for (var side = 0; side < 4; side++) {
        if (footprintSet.contains(neighbors[side]) ||
            !connectedRoads.contains(neighbors[side])) {
          continue;
        }
        sides.add(side < 2 ? 'right' : 'left');
      }
    }
    return sides;
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

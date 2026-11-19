const defaultParcelSize = 8;
const worldRenderChunkSize = 16;

/// Whether a square [hallSize]×[hallSize] hall — the city hall, per
/// content's root model — with its front road, one cell out from the
/// middle of one face, fits entirely on [parcel]'s dry land (per
/// [isLand]). The founding claim's buildability bar: a claimed
/// parcel must be able to host its hall, or the city could never
/// found itself there and the claim would seal the game shut. A game
/// rule, like [defaultParcelSize], not tunable content; content
/// validation runs it too, so the authored map always offers at
/// least one parcel that clears it.
bool parcelCanHostHall({
  required ParcelCoord parcel,
  required int parcelSize,
  required int hallSize,
  required bool Function(CellCoord) isLand,
}) {
  final northWest = parcel.origin(parcelSize);
  bool cellFits(CellCoord cell) =>
      parcelForCell(cell, parcelSize: parcelSize) == parcel && isLand(cell);
  for (var dy = 0; dy + hallSize <= parcelSize; dy++) {
    for (var dx = 0; dx + hallSize <= parcelSize; dx++) {
      final origin = northWest.offset(dx, dy);
      var hallFits = true;
      for (var fy = 0; fy < hallSize && hallFits; fy++) {
        for (var fx = 0; fx < hallSize && hallFits; fx++) {
          hallFits = cellFits(origin.offset(fx, fy));
        }
      }
      if (!hallFits) continue;
      // The front road: one cell off the middle of any one face.
      final mid = hallSize ~/ 2;
      if (cellFits(origin.offset(mid, -1)) ||
          cellFits(origin.offset(mid, hallSize)) ||
          cellFits(origin.offset(hallSize, mid)) ||
          cellFits(origin.offset(-1, mid))) {
        return true;
      }
    }
  }
  return false;
}

/// Physical ground size of one tile's edge, in metres. The world
/// renders 64 px wide per tile with walkers 9 px tall at the seeded
/// 0.6 sprite scale, so 12 m tiles read people at ~1.69 m — the
/// human average — while a road tile matches a complete street and
/// a one-tile cottage a 144 m² footprint. City limits, built-up
/// area, and population density all derive from this; it is world
/// geometry, like [defaultParcelSize], not tunable content.
const double tileEdgeMetres = 12;

/// Ground area of one tile, in square metres.
const double tileAreaSquareMetres = tileEdgeMetres * tileEdgeMetres;

class CellCoord implements Comparable<CellCoord> {
  const CellCoord(this.column, this.row);

  final int column;
  final int row;

  String get key => '$column,$row';

  List<CellCoord> get neighbors => [
    CellCoord(column, row - 1),
    CellCoord(column + 1, row),
    CellCoord(column, row + 1),
    CellCoord(column - 1, row),
  ];

  CellCoord offset(int dx, int dy) => CellCoord(column + dx, row + dy);

  Map<String, Object> toJson() => {'column': column, 'row': row};

  factory CellCoord.fromJson(Map<String, Object?> json) =>
      CellCoord(json['column']! as int, json['row']! as int);

  @override
  int compareTo(CellCoord other) {
    final byRow = row.compareTo(other.row);
    return byRow != 0 ? byRow : column.compareTo(other.column);
  }

  @override
  bool operator ==(Object other) =>
      other is CellCoord && other.column == column && other.row == row;

  @override
  int get hashCode => Object.hash(column, row);

  @override
  String toString() => 'CellCoord($column, $row)';
}

class ParcelCoord implements Comparable<ParcelCoord> {
  const ParcelCoord(this.x, this.y);

  final int x;
  final int y;

  String get key => '$x,$y';

  CellCoord origin([int size = defaultParcelSize]) =>
      CellCoord(x * size, y * size);

  List<ParcelCoord> get neighbors => [
    ParcelCoord(x, y - 1),
    ParcelCoord(x + 1, y),
    ParcelCoord(x, y + 1),
    ParcelCoord(x - 1, y),
  ];

  Iterable<CellCoord> cells([int size = defaultParcelSize]) sync* {
    for (var row = 0; row < size; row++) {
      for (var column = 0; column < size; column++) {
        yield CellCoord(x * size + column, y * size + row);
      }
    }
  }

  Map<String, Object> toJson() => {'x': x, 'y': y};

  factory ParcelCoord.fromJson(Map<String, Object?> json) =>
      ParcelCoord(json['x']! as int, json['y']! as int);

  @override
  int compareTo(ParcelCoord other) {
    final byY = y.compareTo(other.y);
    return byY != 0 ? byY : x.compareTo(other.x);
  }

  @override
  bool operator ==(Object other) =>
      other is ParcelCoord && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'ParcelCoord($x, $y)';
}

class WorldChunkCoord implements Comparable<WorldChunkCoord> {
  const WorldChunkCoord(this.x, this.y);

  final int x;
  final int y;

  factory WorldChunkCoord.fromCell(
    CellCoord cell, {
    int chunkSize = worldRenderChunkSize,
  }) => WorldChunkCoord(
    floorDivide(cell.column, chunkSize),
    floorDivide(cell.row, chunkSize),
  );

  @override
  int compareTo(WorldChunkCoord other) {
    final byY = y.compareTo(other.y);
    return byY != 0 ? byY : x.compareTo(other.x);
  }

  @override
  bool operator ==(Object other) =>
      other is WorldChunkCoord && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

int floorDivide(int value, int divisor) {
  if (divisor <= 0) throw ArgumentError.value(divisor, 'divisor');
  if (value >= 0) return value ~/ divisor;
  return -((-value + divisor - 1) ~/ divisor);
}

ParcelCoord parcelForCell(
  CellCoord cell, {
  int parcelSize = defaultParcelSize,
}) => ParcelCoord(
  floorDivide(cell.column, parcelSize),
  floorDivide(cell.row, parcelSize),
);

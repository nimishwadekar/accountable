import '../content/content_bundle.dart';
import '../world/coordinates.dart';
import 'sheet_tables.dart';

/// What the current save occupies — the lock data for the map editor
/// and the server's save-time validation.
///
/// Occupied means every cell held by a completed or planned tile, with
/// structure footprints expanded from the catalogue and bridge-project
/// spans derived from their bank targets — so plans reserve exactly
/// what they would block.
class WorldUsage {
  const WorldUsage({required this.occupiedCells, required this.ownedParcels});

  final Set<CellCoord> occupiedCells;
  final Set<ParcelCoord> ownedParcels;

  Map<String, Object?> toJson() => {
    'occupiedCells': [
      for (final cell in occupiedCells) [cell.column, cell.row],
    ],
    'ownedParcels': [
      for (final parcel in ownedParcels) [parcel.x, parcel.y],
    ],
  };

  static WorldUsage fromJson(Map<String, Object?> json) => WorldUsage(
    occupiedCells: {
      for (final pair in (json['occupiedCells'] as List? ?? const []))
        CellCoord((pair as List)[0] as int, pair[1] as int),
    },
    ownedParcels: {
      for (final pair in (json['ownedParcels'] as List? ?? const []))
        ParcelCoord((pair as List)[0] as int, pair[1] as int),
    },
  );
}

WorldUsage computeWorldUsage(SheetTables tables, ContentBundle content) {
  final occupied = <CellCoord>{};
  for (final row in tables.tiles) {
    final cell = _cell(row[0], row[1]);
    if (cell == null) continue;
    if (row[2] == 'structure') {
      // Structures occupy their whole catalogue footprint; both planned
      // and complete rows sit at the origin.
      final model = content.structure(row[4]);
      if (model == null) continue;
      for (var dy = 0; dy < model.footprintRows; dy++) {
        for (var dx = 0; dx < model.footprintColumns; dx++) {
          occupied.add(cell.offset(dx, dy));
        }
      }
    } else {
      // Roads and bridges occupy their tile, planned or complete.
      occupied.add(cell);
    }
  }
  for (final row in tables.projects) {
    // Bridge spans are not tile rows until completion; derive the
    // reserved water cells from the bank targets.
    if (row[1] != 'bridge') continue;
    final target = row[3].split(':');
    if (target.length != 4) continue;
    final near = _cell(target[0], target[1]);
    final far = _cell(target[2], target[3]);
    if (near == null || far == null) continue;
    final step = CellCoord(
      (far.column - near.column).sign,
      (far.row - near.row).sign,
    );
    final distance =
        (far.column - near.column).abs() + (far.row - near.row).abs();
    for (var index = 1; index < distance; index++) {
      occupied.add(near.offset(step.column * index, step.row * index));
    }
  }
  // Props occupy their tile — the map editor treats a propped tile as
  // locked exactly like a roaded or built one.
  for (final row in tables.props) {
    final cell = _cell(row[0], row[1]);
    if (cell != null) occupied.add(cell);
  }
  return WorldUsage(
    occupiedCells: occupied,
    ownedParcels: {
      for (final row in tables.ownedParcels)
        if (_cell(row[0], row[1]) case final parcel?)
          ParcelCoord(parcel.column, parcel.row),
    },
  );
}

CellCoord? _cell(String? x, String? y) {
  final column = x == null ? null : int.tryParse(x.trim());
  final row = y == null ? null : int.tryParse(y.trim());
  if (column == null || row == null) return null;
  return CellCoord(column, row);
}

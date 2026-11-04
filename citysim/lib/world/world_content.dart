/// Logical world content types and footprint math.
///
/// The catalogue, sprite manifest, economy, and ambience values themselves
/// live in the JSON content layer (`assets/content/`) and are loaded as a
/// [ContentBundle]; this module keeps only the pure type definitions they
/// parse into (re-exported from the content models for existing imports)
/// and the grid-geometry helpers used by rules and rendering.
library;

import '../content/content_models.dart';
import 'coordinates.dart';

export '../content/content_models.dart'
    show RoadStyle, StructureKind, StructureDefinition, SpriteDefinition;

CellCoord cellFromFootprintOrigin(
  CellCoord origin,
  int dx,
  int dy,
  int quarterTurns,
) {
  return switch (quarterTurns % 4) {
    0 => origin.offset(dx, dy),
    1 => origin.offset(-dy, dx),
    2 => origin.offset(-dx, -dy),
    _ => origin.offset(dy, -dx),
  };
}

/// Decodes a JSON value that the codec stored as `Map<dynamic, dynamic>`
/// back into a typed `Map<String, Object?>`.
Map<String, Object?> worldJsonMap(Object? value) =>
    (value as Map).map((key, value) => MapEntry(key as String, value));

List<CellCoord> structureFootprint(
  StructureDefinition definition,
  CellCoord origin, {
  int quarterTurns = 0,
}) {
  final cells = <CellCoord>[];
  for (var dy = 0; dy < definition.footprintRows; dy++) {
    for (var dx = 0; dx < definition.footprintColumns; dx++) {
      cells.add(cellFromFootprintOrigin(origin, dx, dy, quarterTurns));
    }
  }
  return cells;
}

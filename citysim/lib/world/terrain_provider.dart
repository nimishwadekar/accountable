import '../content/content_models.dart'
    show GroundStyle, TerrainContent, TerrainKind;
import 'coordinates.dart';

export '../content/content_models.dart' show TerrainKind, GroundStyle;

/// One sampled world cell. `groundStyle` is always grass until the
/// detail layers land; water cells ignore it.
class TerrainCell {
  const TerrainCell({
    required this.coord,
    required this.kind,
    this.groundStyle = GroundStyle.grass,
  });

  final CellCoord coord;
  final TerrainKind kind;
  final GroundStyle groundStyle;

  bool get isLand => kind == TerrainKind.grass;
}

/// Deterministic terrain sampling. The [seed] is the hook for future
/// cell-level detail layers (puddles and friends); authored parcel
/// terrain itself is seed-independent.
abstract interface class TerrainProvider {
  int get generatorVersion;

  TerrainCell sample(CellCoord coord, int seed);
}

/// Samples the authored `terrain.json` map. Authored parcels return
/// their base terrain; any parcel without an entry is open ocean —
/// unbuyable, unbridgeable, rendered as sea with natural coastlines.
class ContentTerrainProvider implements TerrainProvider {
  const ContentTerrainProvider(this.content);

  final TerrainContent content;

  @override
  int get generatorVersion => content.generatorVersion;

  @override
  TerrainCell sample(CellCoord coord, int seed) {
    final kind = content.parcels[parcelForCell(coord)] ?? TerrainKind.water;
    return TerrainCell(coord: coord, kind: kind);
  }
}

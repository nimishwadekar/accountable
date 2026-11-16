import '../content/content_models.dart'
    show GroundStyle, TerrainContent, TerrainKind, TerrainProp;
import 'coordinates.dart';

export '../content/content_models.dart'
    show TerrainKind, GroundStyle, TerrainProp;

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

  /// Authored nature props, raw from the terrain map. The provider
  /// hands them over unfiltered: ownership is a save's business, so
  /// queries drop rows on owned parcels (the save is the truth there)
  /// and purchase materializes exactly these rows. Test providers
  /// with no authored nature return an empty list.
  List<TerrainProp> get natureProps;
}

/// Samples the authored `terrain.json` map. Authored parcels return
/// their base terrain, cut by any per-tile paint the map carries; any
/// parcel without an entry is fog — the uncharted cloud deck around
/// the known world, rendered from the fog sprites. Authoring a parcel
/// (editing the map) is what clears the fog.
class ContentTerrainProvider implements TerrainProvider {
  const ContentTerrainProvider(this.content);

  final TerrainContent content;

  @override
  int get generatorVersion => content.generatorVersion;

  @override
  List<TerrainProp> get natureProps => content.props;

  @override
  TerrainCell sample(CellCoord coord, int seed) {
    final base = content.parcels[parcelForCell(coord)];
    if (base == null) return TerrainCell(coord: coord, kind: TerrainKind.fog);
    return TerrainCell(coord: coord, kind: content.tiles[coord] ?? base);
  }
}

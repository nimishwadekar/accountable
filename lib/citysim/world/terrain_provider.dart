import 'coordinates.dart';

enum TerrainKind { grass, river, lake, ocean }

enum GroundStyle { grass, grassPuddle, dirt, asphalt, concrete }

class TerrainCell {
  const TerrainCell({
    required this.coord,
    required this.kind,
    required this.groundStyle,
    this.waterBodyId,
  });

  final CellCoord coord;
  final TerrainKind kind;
  final GroundStyle groundStyle;
  final String? waterBodyId;

  bool get isLand =>
      kind != TerrainKind.river &&
      kind != TerrainKind.lake &&
      kind != TerrainKind.ocean;

  Map<String, Object?> toJson() => {
    'coord': coord.toJson(),
    'kind': kind.name,
    'groundStyle': groundStyle.name,
    'waterBodyId': waterBodyId,
  };

  factory TerrainCell.fromJson(Map<String, Object?> json) {
    final kindName = json['kind']! as String;
    final groundName = json['groundStyle']! as String;
    return TerrainCell(
      coord: CellCoord.fromJson(_map(json['coord'])),
      kind: TerrainKind.values.firstWhere((value) => value.name == kindName),
      groundStyle: GroundStyle.values.firstWhere(
        (value) => value.name == groundName,
      ),
      waterBodyId: json['waterBodyId'] as String?,
    );
  }
}

abstract interface class TerrainProvider {
  int get generatorVersion;

  TerrainCell sample(CellCoord coord, int seed);
}

/// Stable authored geography for the first parcel-world slice.
///
/// The river, lake, and ocean patch are global-coordinate features, so asking
/// for neighboring parcels in a different order cannot change their shores.
/// Unauthored land outside these fixtures remains expandable in every direction.
class DemoTerrainProvider implements TerrainProvider {
  const DemoTerrainProvider();

  @override
  int get generatorVersion => 1;

  @override
  TerrainCell sample(CellCoord coord, int seed) {
    final kind = _waterKindAt(coord);
    final bodyId = switch (kind) {
      TerrainKind.river => 'river-main-v1',
      TerrainKind.lake => 'lake-willow-v1',
      TerrainKind.ocean => 'ocean-east-v1',
      TerrainKind.grass => null,
    };
    final style = _groundStyle(coord, seed);
    return TerrainCell(
      coord: coord,
      kind: kind,
      groundStyle: style,
      waterBodyId: bodyId,
    );
  }

  TerrainKind _waterKindAt(CellCoord cell) {
    // The ocean is a large coast feature; it can be routed around at its ends
    // but never bridged. This rectangle is deliberately broad enough to make
    // a visible coast while leaving deterministic expansion around it.
    if (cell.column >= 24 &&
        cell.column <= 31 &&
        cell.row >= -8 &&
        cell.row <= 23) {
      return TerrainKind.ocean;
    }

    // A four-cell river runs through the first eastern parcel. A parcel may
    // own both banks without granting access to the far bank.
    if (cell.column == 12) return TerrainKind.river;

    // A small natural lake in the western neighboring parcel.
    if (cell.column >= -5 &&
        cell.column <= -2 &&
        cell.row >= 1 &&
        cell.row <= 4) {
      return TerrainKind.lake;
    }
    return TerrainKind.grass;
  }

  GroundStyle _groundStyle(CellCoord cell, int seed) {
    // Keep the ground readable as grass with a subtle puddle accent. Full
    // dirt or concrete tiles read as unplaced roads/pavement, so they stay
    // out of the generated variation.
    final seedOffset = seed % 1000003;
    final variation = cell.column * 31 + cell.row * 17 + seedOffset;
    if (variation % 61 == 0) return GroundStyle.grassPuddle;
    return GroundStyle.grass;
  }
}

Map<String, Object?> _map(Object? value) =>
    (value as Map).map((key, value) => MapEntry(key as String, value));

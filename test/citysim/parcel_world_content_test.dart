import 'package:accountable/citysim/world/coordinates.dart';
import 'package:accountable/citysim/world/road_sprite_resolver.dart';
import 'package:accountable/citysim/world/terrain_provider.dart';
import 'package:accountable/citysim/world/world_content.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'all logical catalogue and road-mask roles resolve to supplied art',
    () async {
      final roles = <String>{
        ...structureCatalogue.map((definition) => definition.assetRole),
        for (var mask = 0; mask < 16; mask++) roadSpriteRole(mask),
        'terrain.grass',
        'terrain.grass.puddle',
        'terrain.dirt',
        'terrain.water',
        'shore.grass.edge.n',
        'shore.dirt.edge.n',
        'shore.grass.corner.n',
        'shore.dirt.corner.w',
        'shore.grass.quarter.ne',
        'shore.grass.quarter.sw',
        'shore.dirt.quarter.se',
        'shore.dirt.quarter.nw',
        'bridge.body.se',
        'bridge.body.sw',
        'bridge.ramp.ne',
        'bridge.ramp.nw',
        'bridge.ramp.se',
        'bridge.ramp.sw',
      };
      for (final role in roles) {
        final definition = spriteManifest[role];
        expect(definition, isNotNull, reason: role);
        expect(
          await rootBundle.load(citysimAssetPath(role)),
          isNotNull,
          reason: role,
        );
      }
    },
  );

  test('negative cell coordinates map to the correct neighboring parcels', () {
    expect(parcelForCell(const CellCoord(-1, 0)), const ParcelCoord(-1, 0));
    expect(parcelForCell(const CellCoord(-8, -8)), const ParcelCoord(-1, -1));
    expect(parcelForCell(const CellCoord(-9, -9)), const ParcelCoord(-2, -2));
  });

  test('road sprite roles keep their openings facing connected neighbours', () {
    // End caps are named for the capped side, so a single connection to the
    // north needs the cap facing away from it.
    expect(roadSpriteRole(roadNorth), 'road.end.sw');
    expect(roadSpriteRole(roadEast), 'road.end.nw');
    expect(roadSpriteRole(roadSouth), 'road.end.ne');
    expect(roadSpriteRole(roadWest), 'road.end.se');
    // Corners are named for the elbow, opposite the two open edges.
    expect(roadSpriteRole(roadNorth | roadEast), 'road.corner.w');
    expect(roadSpriteRole(roadEast | roadSouth), 'road.corner.n');
    expect(roadSpriteRole(roadSouth | roadWest), 'road.corner.e');
    expect(roadSpriteRole(roadWest | roadNorth), 'road.corner.s');
    // Straights are named for their axis.
    expect(roadSpriteRole(roadNorth | roadSouth), 'road.straight.sw');
    expect(roadSpriteRole(roadEast | roadWest), 'road.straight.se');
  });

  test('terrain stays fixed for a seed and agrees across parcel edges', () {
    const provider = DemoTerrainProvider();
    const seed = 145;
    final westEdge = provider.sample(const CellCoord(7, 4), seed);
    final eastEdge = provider.sample(const CellCoord(8, 4), seed);
    expect(provider.sample(const CellCoord(7, 4), seed).kind, westEdge.kind);
    expect(provider.sample(const CellCoord(8, 4), seed).kind, eastEdge.kind);
    expect(
      provider.sample(const CellCoord(12, 4), seed).kind,
      TerrainKind.river,
    );
    expect(
      provider.sample(const CellCoord(-4, 2), seed).kind,
      TerrainKind.lake,
    );
    expect(
      provider.sample(const CellCoord(24, 2), seed).kind,
      TerrainKind.ocean,
    );
  });
}

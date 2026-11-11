/// Pins the layered draw order of the flat ground: terrain chunks
/// (ocean parcels beneath land parcels), then roads as a per-frame
/// layer, then the shore banks.
///
/// The ground tiles carry ~2 world px opaque skirts past their
/// diamonds (see ground_skirt_seam_test.dart). Skirts are only
/// invisible when the thing they overlap is drawn later, so the draw
/// order must be layered — the standard tilemap order (Tiled layers,
/// Godot tilemap layers, Unity sorting layers):
///
/// - Roads must draw after every ground tile. Baking them into the
///   chunk pictures, interleaved per cell with terrain, let later
///   cells' terrain skirts (and later chunks' terrain at parcel
///   boundaries) paint grass over road art.
/// - Water parcels must blit before land parcels. The bank overlay
///   only reaches ~1 world px past the shared shore edge, so a water
///   tile's 2 px skirt would otherwise show as a water-coloured line
///   on the land side of west- and north-facing shores.
library;

import 'dart:typed_data' show ByteData;
import 'dart:ui' as ui;

import 'package:citysim/content/asset_content_source.dart';
import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/rendering/parcel_world_view.dart';
import 'package:citysim/storage/sheet_tables.dart';
import 'package:citysim/storage/world_sheet_codec.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:citysim/world/terrain_provider.dart';
import 'package:citysim/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';

/// Grass parcels (0,0), (0,1), (1,0), (1,1); everything else ocean.
/// The shore between land cell (15, 4) and water cell (16, 4) faces
/// west, the direction whose water skirt used to show.
class _ShoreTerrain implements TerrainProvider {
  const _ShoreTerrain();

  @override
  int get generatorVersion => 1;

  @override
  TerrainCell sample(CellCoord coord, int seed) {
    final parcel = ParcelCoord(
      (coord.column / defaultParcelSize).floor(),
      (coord.row / defaultParcelSize).floor(),
    );
    final land =
        (parcel.x == 0 || parcel.x == 1) && (parcel.y == 0 || parcel.y == 1);
    return TerrainCell(
      coord: coord,
      kind: land ? TerrainKind.grass : TerrainKind.water,
    );
  }
}

ParcelWorldState _world(ContentBundle content) => sheetTablesToWorld(
  SheetTables(
    userData: const {
      'seed': '7',
      'coins': '10',
      'coins_earned': '10',
      'coins_spent': '0',
      'simulated_date': '2026-11-05',
      'high_water_date': '2026-11-05',
      'construction_day': '0',
    },
    ownedParcels: const [],
    // A vertical road down column 4, rows 4..7: (4,4)'s east
    // neighbour (5,4) is same-chunk grass; (4,7)'s south
    // neighbour (4,8) is grass in the next parcel's chunk.
    tiles: const [
      ['4', '4', 'road', 'complete', 'asphalt', '', '', ''],
      ['4', '5', 'road', 'complete', 'asphalt', '', '', ''],
      ['4', '6', 'road', 'complete', 'asphalt', '', '', ''],
      ['4', '7', 'road', 'complete', 'asphalt', '', '', ''],
    ],
    projects: const [],
  ),
  content: content,
  terrainProvider: const _ShoreTerrain(),
);

Offset _screenCenterOf(CellCoord cell) {
  final world = Offset(
    (cell.column - cell.row) * 32.0,
    (cell.column + cell.row) * 16.0,
  );
  const start = Offset(0, 128); // world centre of cell (4, 4).
  return const Offset(400, 300) + (world - start);
}

int _pixel(ui.Image image, ByteData bytes, Offset point) {
  final x = point.dx.round().clamp(0, image.width - 1);
  final y = point.dy.round().clamp(0, image.height - 1);
  return bytes.getUint32((y * image.width + x) * 4);
}

bool _isGrassLike(int rgba) {
  final g = (rgba >> 16) & 0xFF, b = (rgba >> 8) & 0xFF;
  return g > 130 && g - b > 40;
}

bool _isWaterLike(int rgba) {
  final g = (rgba >> 16) & 0xFF, b = (rgba >> 8) & 0xFF;
  return b > 150 && b >= g;
}

void main() {
  late ContentBundle content;
  setUpAll(() async {
    content = await loadContentBundle(const AssetContentSource());
  });

  testWidgets('terrain skirts stay under roads and land covers water', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final world = _world(content);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: RepaintBoundary(
            key: boundaryKey,
            child: ParcelWorldView(
              state: world,
              content: content,
              terrainProvider: const _ShoreTerrain(),
              parcelMode: false,
              showTileGrid: false,
              onCellTap: (cell, structureId, subtileX, subtileY) {},
            ),
          ),
        ),
      ),
    );
    for (var attempt = 0; attempt < 8; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    final image = await tester.runAsync(() async {
      final boundary =
          tester.renderObject(find.byKey(boundaryKey)) as RenderRepaintBoundary;
      return boundary.toImage(pixelRatio: 1);
    });
    final bytes = await tester.runAsync<ByteData?>(() => image!.toByteData());
    expect(bytes, isNotNull);

    int px(Offset point) => _pixel(image!, bytes!, point);

    // Sanity anchors.
    expect(
      _isGrassLike(px(_screenCenterOf(const CellCoord(10, 4)))),
      isTrue,
      reason: 'open land reads grass',
    );
    final roadCentre = px(_screenCenterOf(const CellCoord(4, 5)));
    expect(
      _isGrassLike(roadCentre),
      isFalse,
      reason: 'road centre reads asphalt, not grass',
    );

    // 1. Road (4,4)'s east edge, under same-chunk grass (5,4)'s
    //    skirt zone: must stay road, not grass.
    final roadEast = px(
      _screenCenterOf(const CellCoord(4, 4)).translate(28, 1),
    );
    expect(
      _isGrassLike(roadEast),
      isFalse,
      reason:
          'same-chunk terrain skirt must not paint over road '
          'art (layered draw order)',
    );

    // 2. Road (4,7)'s south edge, under next-parcel grass (4,8)'s
    //    skirt zone: must stay road, not grass.
    final roadSouth = px(
      _screenCenterOf(const CellCoord(4, 7)).translate(-2, 14),
    );
    expect(
      _isGrassLike(roadSouth),
      isFalse,
      reason:
          'terrain skirts from a later chunk must not paint '
          'over road art',
    );

    // 3. Land (15,4) ~1.8 world px west of the shore edge shared
    //    with water (16,4): must read land, not water. The bank's
    //    own bleed only reaches ~1 px past the edge, so this is
    //    exactly where the water skirt used to show.
    final shoreEdgeMid = _screenCenterOf(const CellCoord(15, 4))
        .translate(16, 8);
    final onLand = px(shoreEdgeMid.translate(-2, -1));
    expect(
      _isWaterLike(onLand),
      isFalse,
      reason:
          'water skirt must not show on the land side of a '
          'shore (ocean parcels blit first)',
    );
    expect(
      _isGrassLike(onLand),
      isTrue,
      reason: 'the shore line on the land side reads grass',
    );
  });
}

/// Regression tests for the ground-tile skirt (edge extrusion).
///
/// The six ground tiles carry an opaque skirt a couple of pixels past
/// their diamonds (2026-11-10; see ASSET_NOTICE.md) so that bilinear
/// resampling at any zoom leaves neighbouring tiles' combined
/// coverage fully opaque. Without it the mint map background bled
/// through hairlines along tile edges (zoomed out) and along parcel
/// boundaries (zoomed in) — the classic texture-bleeding problem;
/// the skirt is the standard fix (extrusion / edge padding).
///
/// 1. Isolation: a patch of grass tiles over the mint map background,
///    drawn at 1:1, 2:1, and 4:1 — the art→texture scales the chunk
///    cache uses — must show no mint-blended pixels along interior
///    seams.
/// 2. Full app: the world rendered at the cache's detail buckets
///    (dpr 1 → factor 1, dpr 2 and 3 → factor 2) must show no
///    mint-blended pixels on tile boundaries, parcel boundaries, or
///    anywhere else.
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
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

/// A pixel that reads as grass blended with the mint map background:
/// 15–90% mint by the blue channel. The grass art's own blue channel
/// maxes at 96, so anything above 100 involves the background.
bool _isMintBlend(int r, int g, int b) => b > 100 && b < 195 && g > 170;

class _PatchPainter extends CustomPainter {
  _PatchPainter(this.image, this.tileW);

  final ui.Image image;
  final double tileW;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFB5DCCF),
    );
    const origin = Offset(350, 40);
    for (var r = 0; r < 6; r++) {
      for (var c = 0; c < 6; c++) {
        final center =
            origin + Offset((c - r) * tileW / 2, (c + r) * tileW / 4);
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, 128, 64),
          Rect.fromCenter(center: center, width: tileW, height: tileW / 2),
          Paint()..filterQuality = FilterQuality.medium,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PatchPainter old) => old.tileW != tileW;
}

class _AllGrass implements TerrainProvider {
  const _AllGrass();

  @override
  int get generatorVersion => 1;

  @override
  TerrainCell sample(CellCoord coord, int seed) =>
      TerrainCell(coord: coord, kind: TerrainKind.grass);
}

ParcelWorldState _grassWorld(ContentBundle content) => sheetTablesToWorld(
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
    // Nothing owned: no white frontier outline to confuse the
    // mint-bleed scan.
    ownedParcels: const [],
    tiles: const [],
    projects: const [],
  ),
  content: content,
  terrainProvider: const _AllGrass(),
);

void main() {
  late ui.Image grassArt;
  late ContentBundle content;
  setUpAll(() async {
    final data = await rootBundle.load(
      'assets/sprites/ground/grass/tile_ground_grass.png',
    );
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    grassArt = (await codec.getNextFrame()).image;
    content = await loadContentBundle(const AssetContentSource());
  });

  testWidgets('tile skirt keeps interior seams opaque at every draw scale', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(700, 420);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final key = GlobalKey();

    for (final tileW in [128.0, 64.0, 32.0]) {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: RepaintBoundary(
              key: key,
              child: CustomPaint(
                painter: _PatchPainter(grassArt, tileW),
                size: const Size(700, 420),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final image = await tester.runAsync(() async {
        final boundary =
            tester.renderObject(find.byKey(key)) as RenderRepaintBoundary;
        return boundary.toImage(pixelRatio: 1);
      });
      final bytes = await tester.runAsync<ByteData?>(() => image!.toByteData());
      expect(bytes, isNotNull);

      // Inner-cell diamonds in screen space at this scale.
      final diamonds = [
        for (var r = 1; r < 5; r++)
          for (var c = 1; c < 5; c++)
            (
              Offset(350, 40) +
                  Offset((c - r) * tileW / 2, (c + r) * tileW / 4),
              tileW / 2,
              tileW / 4,
            ),
      ];
      var leaks = 0;
      for (var y = 0; y < image!.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final inside = diamonds.any(
            (d) => (x - d.$1.dx).abs() / d.$2 + (y - d.$1.dy).abs() / d.$3 <= 1,
          );
          if (!inside) continue;
          final v = bytes!.getUint32((y * image.width + x) * 4);
          if (_isMintBlend(
            (v >> 24) & 0xFF,
            (v >> 16) & 0xFF,
            (v >> 8) & 0xFF,
          )) {
            leaks++;
          }
        }
      }
      // ignore: avoid_print
      print('isolation tileW $tileW: $leaks mint-blend px');
      expect(
        leaks,
        lessThan(10),
        reason: 'tile seams must stay opaque at draw scale $tileW',
      );
    }
  });

  testWidgets('no background bleed at any chunk detail bucket', (tester) async {
    final world = _grassWorld(content);
    final boundaryKey = GlobalKey();
    Widget app() => MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: RepaintBoundary(
          key: boundaryKey,
          child: ParcelWorldView(
            state: world,
            content: content,
            terrainProvider: const _AllGrass(),
            parcelMode: false,
            showTileGrid: false,
            onCellTap: (cell, structureId) {},
          ),
        ),
      ),
    );

    // Parcel boundaries lie on x + 2y = 64k - 32 (columns) and
    // x - 2y = 64k + 32 (rows); tile boundaries are the same
    // congruences mod 64 instead of mod 512.
    double distToLattice(double v, double period) {
      final m = (v % period + period) % period;
      return m < period / 2 ? m : period - m;
    }

    for (final dpr in [1.0, 2.0, 3.0]) {
      tester.view.devicePixelRatio = dpr;
      tester.view.physicalSize = const Size(800, 600);
      await tester.pumpWidget(app());
      for (var attempt = 0; attempt < 6; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      final image = await tester.runAsync(() async {
        final boundary = tester.renderObject(
          find.byKey(boundaryKey),
        ) as RenderRepaintBoundary;
        return boundary.toImage(pixelRatio: dpr);
      });
      final bytes = await tester.runAsync<ByteData?>(() => image!.toByteData());
      expect(bytes, isNotNull);

      final w = image!.width, h = image.height;
      final lw = w / dpr, lh = h / dpr;
      final cx = lw / 2, cy = lh / 2;
      var onParcel = 0, onTile = 0, elsewhere = 0;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final v = bytes!.getUint32((y * w + x) * 4);
          if (!_isMintBlend(
            (v >> 24) & 0xFF,
            (v >> 16) & 0xFF,
            (v >> 8) & 0xFF,
          )) {
            continue;
          }
          final wx = x / dpr - cx;
          final wy = y / dpr - cy + 128;
          final dCol = distToLattice(wx + 2 * wy + 32, 64) / 2.236;
          final dRow = distToLattice(wx - 2 * wy - 32, 64) / 2.236;
          final dTile = dCol < dRow ? dCol : dRow;
          final pCol = distToLattice(wx + 2 * wy + 32, 512) / 2.236;
          final pRow = distToLattice(wx - 2 * wy - 32, 512) / 2.236;
          final dParcel = pCol < pRow ? pCol : pRow;
          if (dParcel <= 2.0) {
            onParcel++;
          } else if (dTile <= 2.0) {
            onTile++;
          } else {
            elsewhere++;
          }
        }
      }
      // ignore: avoid_print
      print(
        'dpr $dpr: parcel $onParcel, tile $onTile, '
        'elsewhere $elsewhere mint-blend px',
      );
      expect(
        onParcel,
        lessThan(10),
        reason: 'parcel-boundary bleed at dpr $dpr',
      );
      expect(onTile, lessThan(10), reason: 'tile-boundary bleed at dpr $dpr');
      expect(
        elsewhere,
        lessThan(10),
        reason: 'background bleed away from boundaries at dpr $dpr',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });
}

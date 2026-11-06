/// Rendering-correctness tests for the chunked terrain layer.
///
/// The chunk cache has two draw paths — rasterized textures (the
/// production path) and world-space picture replay (the fallback) —
/// and both must place content at exactly the screen position the
/// world→camera transform dictates. These tests verify that at the
/// pixel level:
///
/// 1. Anchor test: sample the rendered pixels at the screen positions
///    of known cells (road, water, grass) computed from first
///    principles of the world→screen math. A shifted chunk layer
///    lights this up immediately.
/// 2. A/B test: render the same frozen frame through textures and
///    through picture replay, then require the pixels to match. The
///    ambient clock is muted for the captures so water shimmer and
///    pedestrians cannot move between them.
///
/// The world is small and controlled on purpose: three asphalt road
/// cells, no bridges, no structures — clean anchors, no overhanging
/// art.
library;

import 'dart:typed_data' show ByteData;
import 'dart:ui' as ui;

import 'package:citysim/content/asset_content_source.dart';
import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/rendering/parcel_world_view.dart';
import 'package:citysim/rendering/perf_probe.dart';
import 'package:citysim/storage/sheet_tables.dart';
import 'package:citysim/storage/world_sheet_codec.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:citysim/world/terrain_provider.dart';
import 'package:citysim/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';

ParcelWorldState _anchorWorld(ContentBundle content) => sheetTablesToWorld(
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
    ownedParcels: const [
      ['0', '0'],
    ],
    tiles: const [
      ['4', '4', 'road', 'complete', 'asphalt', '', '', ''],
      ['5', '4', 'road', 'complete', 'asphalt', '', '', ''],
      ['6', '4', 'road', 'complete', 'asphalt', '', '', ''],
    ],
    projects: const [],
  ),
  content: content,
  terrainProvider: ContentTerrainProvider(content.terrain),
);

/// Screen position of a cell's centre for the test's fixed camera:
/// an 800x600 view, scale 1, centred on the starter cell (4, 4) —
/// the camera ParcelWorldView initializes itself with. Derived from
/// the same world→screen math the renderer uses.
Offset _screenCenterOf(CellCoord cell) {
  final world = Offset(
    (cell.column - cell.row) * 32.0,
    (cell.column + cell.row) * 16.0,
  );
  const start = Offset(0, 128); // world centre of cell (4, 4).
  return const Offset(400, 300) + (world - start);
}

Future<ui.Image?> _capture(WidgetTester tester, GlobalKey boundaryKey) =>
    tester.runAsync(() async {
      final boundary =
          tester.renderObject(find.byKey(boundaryKey)) as RenderRepaintBoundary;
      return boundary.toImage(pixelRatio: 1);
    });

void main() {
  testWidgets(
    'terrain chunks render at their world positions through both draw '
    'paths',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 600);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => debugDrawChunksViaPictures = false);

      final content = await loadContentBundle(const AssetContentSource());
      final world = _anchorWorld(content);
      ParcelWorldProbe.recording = true;
      ParcelWorldProbe.reset();

      final boundaryKey = GlobalKey();
      Widget app({bool disableAnimations = false}) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: RepaintBoundary(
            key: boundaryKey,
            child: ParcelWorldView(
              state: world,
              content: content,
              terrainProvider: ContentTerrainProvider(content.terrain),
              onCellTap: (cell, structureId) {},
            ),
          ),
        ),
      );
      // MediaQuery wraps only the frozen captures below.
      Widget animatedApp = app();
      await tester.pumpWidget(animatedApp);

      // Settle: decode sprites, record and rasterize chunks.
      var settled = false;
      for (var attempt = 0; attempt < 10 && !settled; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        ParcelWorldProbe.reset();
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        settled =
            ParcelWorldProbe.samples.isNotEmpty &&
            ParcelWorldProbe.samples.every((s) => s.chunkRecords == 0);
      }
      expect(settled, isTrue, reason: 'chunks should finish recording');

      // Freeze the ambient clock so the two captures cannot differ
      // through shimmer phase or pedestrian positions.
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: app(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: app(),
        ),
      );

      // ---- Capture A: the production texture path ------------------
      final imageA = (await _capture(tester, boundaryKey))!;
      final bytesA = await tester.runAsync(() => imageA.toByteData());
      expect(bytesA, isNotNull);

      int pixel(ui.Image image, ByteData bytes, Offset point) {
        final x = point.dx.round().clamp(0, image.width - 1);
        final y = point.dy.round().clamp(0, image.height - 1);
        final index = (y * image.width + x) * 4;
        return bytes.getUint32(index);
      }

      // Anchor assertions: known cells must show their terrain at the
      // world-derived screen positions. Sample three cells per
      // category and require at least two hits, so a stray pedestrian
      // or sub-pixel seam cannot flake the test.
      // getUint32 reads big-endian: bytes are R, G, B, A in memory,
      // so red is the high byte and alpha the low one.
      bool isAsphalt(int rgba) {
        final r = rgba >> 24, g = (rgba >> 16) & 0xFF, b = (rgba >> 8) & 0xFF;
        return r < 90 && g < 90 && b < 90;
      }

      bool isWater(int rgba) {
        final r = rgba >> 24, b = (rgba >> 8) & 0xFF;
        return b > 130 && b - r > 25;
      }

      bool isGrass(int rgba) {
        final g = (rgba >> 16) & 0xFF, b = (rgba >> 8) & 0xFF;
        return g > 100 && g - b > 20;
      }

      int hits(List<CellCoord> cells, bool Function(int) match) => cells
          .map((cell) => pixel(imageA, bytesA!, _screenCenterOf(cell)))
          .where(match)
          .length;

      // Terrain.json puts water at parcels (1, 0) and (-1, 0); the
      // owned starter parcel (0, 0) is grass with an asphalt road on
      // row 4.
      expect(
        hits(const [
          CellCoord(4, 4),
          CellCoord(5, 4),
          CellCoord(6, 4),
        ], isAsphalt),
        greaterThanOrEqualTo(2),
        reason:
            'road cells must render as asphalt at their world '
            'positions',
      );
      expect(
        hits(const [
          CellCoord(12, 4),
          CellCoord(10, 2),
          CellCoord(14, 6),
        ], isWater),
        greaterThanOrEqualTo(2),
        reason:
            'water cells must render as water at their world '
            'positions',
      );
      expect(
        hits(const [
          CellCoord(2, 2),
          CellCoord(1, 5),
          CellCoord(6, 6),
        ], isGrass),
        greaterThanOrEqualTo(2),
        reason:
            'grass cells must render as grass at their world '
            'positions',
      );

      // ---- Capture B: the picture-replay path ----------------------
      debugDrawChunksViaPictures = true;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: app(),
        ),
      );
      final imageB = (await _capture(tester, boundaryKey))!;
      final bytesB = await tester.runAsync(() => imageB.toByteData());
      expect(bytesB, isNotNull);

      // The two paths sample the same art through different filter
      // chains, so allow small per-channel deltas; a placement bug
      // displaces nearly every pixel and dwarfs this budget.
      var differing = 0;
      final total = imageA.width * imageA.height;
      for (var i = 0; i < total; i++) {
        final a = bytesA!.getUint32(i * 4);
        final b = bytesB!.getUint32(i * 4);
        for (final shift in [0, 8, 16]) {
          if (((a >> shift) & 0xFF) - ((b >> shift) & 0xFF) > 32 ||
              ((b >> shift) & 0xFF) - ((a >> shift) & 0xFF) > 32) {
            differing++;
            break;
          }
        }
      }
      expect(differing / total, lessThan(0.02));

      imageA.dispose();
      imageB.dispose();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// Parity test for the water shimmer's two draw paths.
///
/// The shimmer renders either through the fragment shader (one
/// textured quad per water chunk, band pattern computed per pixel) or
/// through merged world-space paths (the fallback). Both must produce
/// the same picture: the shader replicates the path version's exact
/// band formula — band = (column - row) % bands, brightness = a
/// phased sine over time — so with the ambient clock frozen, the two
/// captures should match except for anti-aliasing at water edges.
library;

import 'dart:ui' as ui;

import 'package:citysim/content/asset_content_source.dart';
import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/rendering/parcel_world_view.dart';
import 'package:citysim/rendering/perf_probe.dart';
import 'package:citysim/storage/sheet_tables.dart';
import 'package:citysim/storage/world_sheet_codec.dart';
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

Future<ui.Image?> _capture(WidgetTester tester, GlobalKey boundaryKey) =>
    tester.runAsync(() async {
      final boundary =
          tester.renderObject(find.byKey(boundaryKey)) as RenderRepaintBoundary;
      return boundary.toImage(pixelRatio: 1);
    });

void main() {
  testWidgets('shader shimmer and path shimmer render the same picture', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => debugDrawShimmerViaPaths = false);

    final content = await loadContentBundle(const AssetContentSource());
    final world = _anchorWorld(content);
    ParcelWorldProbe.recording = true;
    ParcelWorldProbe.reset();

    final boundaryKey = GlobalKey();
    Widget app({bool disableAnimations = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: MaterialApp(
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
      ),
    );
    await tester.pumpWidget(app());

    // Settle: decode sprites, record and rasterize chunks. The
    // ambient clock runs during settle so frames keep painting;
    // freezing happens only for the captures below.
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

    // The shader must have loaded and engaged — otherwise this test
    // would compare the fallback against itself.
    expect(
      ParcelWorldProbe.samples.any((s) => s.shimmerQuads > 0),
      isTrue,
      reason: 'the fragment shader must drive the shimmer',
    );

    // Freeze the ambient clock so shimmer phase and pedestrian
    // positions stay identical across both captures.
    await tester.pumpWidget(app(disableAnimations: true));
    await tester.pump(const Duration(milliseconds: 100));

    // ---- Capture A: shader ----------------------------------------
    await tester.pumpWidget(app(disableAnimations: true));
    final imageA = (await _capture(tester, boundaryKey))!;
    final bytesA = await tester.runAsync(() => imageA.toByteData());
    expect(bytesA, isNotNull);

    // ---- Capture B: merged paths ----------------------------------
    debugDrawShimmerViaPaths = true;
    await tester.pumpWidget(app(disableAnimations: true));
    final imageB = (await _capture(tester, boundaryKey))!;
    final bytesB = await tester.runAsync(() => imageB.toByteData());
    expect(bytesB, isNotNull);

    // Both paths implement the same formula; differences should be
    // confined to anti-aliased water edges and 8-bit alpha
    // quantization. A formula or placement bug repaints entire
    // water regions and dwarfs this budget.
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
    debugPrint(
      'shimmer parity: ${(differing / total * 100).toStringAsFixed(2)}% '
      'of pixels differ beyond tolerance',
    );
    expect(differing / total, lessThan(0.03));

    imageA.dispose();
    imageB.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
}

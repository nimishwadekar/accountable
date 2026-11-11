/// Pins the draw order of the selected-bridge wash.
///
/// Selecting a bridge repaints its deck and ramps through the
/// selection colour filter so the crossing itself reads as picked.
/// That repaint runs in a per-frame pass above the actors, so it
/// must replay the pieces in the actor pass's own back-to-front
/// order (base-cell column + row). The original version painted all
/// deck bodies, then the near ramp, then the far ramp — and since
/// the near bank is the deterministically smaller end, the visually
/// far ramp repainted on top of the deck tile that occludes it: the
/// far end of the bridge drew over the bridge.
///
/// The test renders the crossing unselected and selected (same
/// frame clock, so the world beneath is pixel-identical) and checks
/// that the selected frame equals the unselected frame washed in
/// the selection colour — which holds only where each pixel's
/// topmost sprite is the same piece in both frames. Around the seam
/// where the far ramp meets the first deck tile, a reordered
/// repaint shows washed ramp art instead of washed deck art.
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

/// Row 4 crosses a pond: dry land banks at (10,4) and (14,4), water
/// at (11..13,4). The codec rebuilds an east-going bridge whose near
/// bank — the deterministically smaller end — is the WEST bank, the
/// visually far end of the crossing.
class _BridgeTerrain implements TerrainProvider {
  const _BridgeTerrain();

  @override
  int get generatorVersion => 1;

  @override
  TerrainCell sample(CellCoord coord, int seed) => TerrainCell(
    coord: coord,
    kind: coord.row == 4 && coord.column >= 11 && coord.column <= 13
        ? TerrainKind.water
        : TerrainKind.grass,
  );
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
    tiles: const [
      ['10', '4', 'road', 'complete', 'asphalt', '', '', ''],
      ['11', '4', 'bridge', 'complete', '', '', '', ''],
      ['12', '4', 'bridge', 'complete', '', '', '', ''],
      ['13', '4', 'bridge', 'complete', '', '', '', ''],
      ['14', '4', 'road', 'complete', 'asphalt', '', '', ''],
    ],
    projects: const [],
  ),
  content: content,
  terrainProvider: const _BridgeTerrain(),
);

Future<(ui.Image, ByteData)> _capture(
  WidgetTester tester,
  GlobalKey key,
) async {
  final image = await tester.runAsync(() async {
    final boundary =
        tester.renderObject(find.byKey(key)) as RenderRepaintBoundary;
    return boundary.toImage(pixelRatio: 1);
  });
  expect(image, isNotNull);
  final bytes = await tester.runAsync<ByteData?>(() => image!.toByteData());
  expect(bytes, isNotNull);
  return (image!, bytes!);
}

/// The selection wash over opaque art: the colour filter composites
/// 0x664BC69B over the sprite srcATop, leaving 60% of the original
/// colour blended with 40% of the wash colour.
bool _washedMatches(int before, int after) {
  int delta(int beforeChannel, int afterChannel, int washChannel) =>
      (afterChannel - (0.6 * beforeChannel + 0.4 * washChannel).round()).abs();
  return delta(before >> 24 & 0xFF, after >> 24 & 0xFF, 0x4B) <= 3 &&
      delta(before >> 16 & 0xFF, after >> 16 & 0xFF, 0xC6) <= 3 &&
      delta(before >> 8 & 0xFF, after >> 8 & 0xFF, 0x9B) <= 3;
}

void main() {
  late ContentBundle content;
  setUpAll(() async {
    content = await loadContentBundle(const AssetContentSource());
  });

  testWidgets('selection wash repaints bridge pieces in draw order', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final world = _world(content);
    final boundaryKey = GlobalKey();
    Widget frame(CellCoord? selected) => MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: RepaintBoundary(
          key: boundaryKey,
          child: ParcelWorldView(
            state: world,
            content: content,
            terrainProvider: const _BridgeTerrain(),
            parcelMode: false,
            showTileGrid: false,
            selectedCell: selected,
            onCellTap: (cell, structureId) {},
          ),
        ),
      ),
    );

    await tester.pumpWidget(frame(null));
    for (var attempt = 0; attempt < 8; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    final (beforeImage, beforeBytes) = await _capture(tester, boundaryKey);

    // Selecting is a per-frame layer above the actors; the frame
    // clock does not advance, so everything beneath the wash holds
    // still.
    await tester.pumpWidget(frame(const CellCoord(12, 4)));
    await tester.pump();
    final (afterImage, afterBytes) = await _capture(tester, boundaryKey);

    int px(ui.Image image, ByteData bytes, int x, int y) =>
        bytes.getUint32((y * image.width + x) * 4);

    // The seam probe sits inside the overlap between the west
    // ramp's art and the first deck tile's art — screen layout at
    // scale 1: the west ramp at (10,4) centres at (592, 396), deck
    // cell (11,4) at (624, 412) with its elevated surface running
    // up from y≈384. In the actor pass the deck draws after the
    // ramp and occludes it there; a reordered repaint shows washed
    // ramp surface instead of washed deck asphalt. The probe stays
    // clear of the selection outline strokes over grass west of the
    // ramp and of the ~2px alpha-edge artefacts along the deck
    // railing's top, both of which legitimately differ.
    const probeLeft = 600, probeRight = 620, probeTop = 390, probeBottom = 406;
    var mismatched = 0;
    final runs = <String>[];
    for (var y = probeTop; y <= probeBottom; y++) {
      var runStart = -1;
      for (var x = probeLeft; x <= probeRight + 1; x++) {
        final beforePx = px(beforeImage, beforeBytes, x, y);
        final afterPx = px(afterImage, afterBytes, x, y);
        final bad = x <= probeRight && !_washedMatches(beforePx, afterPx);
        if (bad && runStart < 0) runStart = x;
        if (!bad && runStart >= 0) {
          mismatched += x - runStart;
          final midX = (runStart + x - 1) ~/ 2;
          runs.add(
            'y=$y x=$runStart..${x - 1} '
            'before=${px(beforeImage, beforeBytes, midX, y).toRadixString(16)} '
            'after=${px(afterImage, afterBytes, midX, y).toRadixString(16)}',
          );
          runStart = -1;
        }
      }
    }
    debugPrint('washed-mismatch runs: ${runs.length}');
    for (final run in runs.take(20)) {
      debugPrint('  $run');
    }
    expect(
      mismatched,
      lessThanOrEqualTo(2),
      reason:
          'selecting the bridge must wash the crossing in place, not '
          'reorder it: $mismatched px around the far-ramp/deck seam show '
          'a different topmost sprite once selected',
    );
  });
}

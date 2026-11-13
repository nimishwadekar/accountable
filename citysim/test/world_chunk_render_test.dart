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
///    ambient clock is muted for the captures so pedestrians cannot
///    move between them.
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
import 'package:flutter/gestures.dart' show PointerHoverEvent;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';

/// Reads one big-endian RGBA pixel from a captured image.
int _pixelAt(ui.Image image, ByteData bytes, Offset point) {
  final x = point.dx.round().clamp(0, image.width - 1);
  final y = point.dy.round().clamp(0, image.height - 1);
  return bytes.getUint32((y * image.width + x) * 4);
}

ParcelWorldState _anchorWorld(
  ContentBundle content, {
  List<List<String>> ownedParcels = const [
    ['0', '0'],
  ],
}) => sheetTablesToWorld(
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
    ownedParcels: ownedParcels,
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
  // Content loads in setUpAll (real async): asset reads inside a
  // testWidgets body run in fake-async, where they are unreliable —
  // see the note in parcel_city_widget_test.dart.
  late ContentBundle content;
  setUpAll(() async {
    content = await loadContentBundle(const AssetContentSource());
  });

  testWidgets(
    'terrain chunks render at their world positions through both draw '
    'paths',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 600);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => debugDrawChunksViaPictures = false);

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
              onCellTap: (cell, structureId, subtileX, subtileY) {},
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

      // The composed shore bands chain after the materials decode,
      // every engine round-trip (byte reads, image decoding) needs a
      // real-async window — wait until the bank actually renders
      // before freezing the captures.
      var bandDrawn = false;
      final bandPoint = _screenCenterOf(const CellCoord(8, 4))
          .translate(-16, -4);
      for (var attempt = 0; attempt < 15 && !bandDrawn; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        final probe = await _capture(tester, boundaryKey);
        if (probe == null) continue;
        final probeBytes = await tester.runAsync(() => probe.toByteData());
        if (probeBytes != null) {
          final x = bandPoint.dx.round().clamp(0, probe.width - 1);
          final y = bandPoint.dy.round().clamp(0, probe.height - 1);
          final rgba = probeBytes.getUint32((y * probe.width + x) * 4);
          final g = (rgba >> 16) & 0xFF, b = (rgba >> 8) & 0xFF;
          bandDrawn = g > 100 && g - b > 20;
        }
        probe.dispose();
      }
      expect(
        bandDrawn,
        isTrue,
        reason: 'the composed shore band should render before capture',
      );

      // Freeze the ambient clock so the two captures cannot differ
      // through pedestrian positions.
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: app(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      // The composed shore bands chain after the materials decode; give
      // that async stage a real-async window to finish before the
      // captures freeze the frame.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
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

      // The shore lives on the water side of the boundary: (8,4) is an
      // outermost water tile with grass land to its west, so its
      // north-west half carries the shore band toward the land while
      // the open half stays water, and the land tile (7,4) stays dry
      // right up to the tile edge where the overflow water used to
      // lap.
      Offset screenHalf(CellCoord cell, int dx, int dy) => _screenCenterOf(cell)
          .translate(((dx - dy) * 16).toDouble(), ((dx + dy) * 8).toDouble());
      expect(
        isGrass(
          pixel(
            imageA,
            bytesA!,
            _screenCenterOf(const CellCoord(8, 4)).translate(-16, -4),
          ),
        ),
        isTrue,
        reason: 'the outermost water tile carries the shore band',
      );
      expect(
        isWater(pixel(imageA, bytesA, screenHalf(const CellCoord(8, 4), 1, 0))),
        isTrue,
        reason: 'the open half of the boundary water tile stays water',
      );
      // The dry-land sample sits in the tile's south-east interior —
      // the boundary itself now carries the dashed owned outline.
      expect(
        isGrass(
          pixel(
            imageA,
            bytesA,
            _screenCenterOf(const CellCoord(7, 4)).translate(8, 4),
          ),
        ),
        isTrue,
        reason: 'land next to water stays dry up to the tile edge',
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
        final a = bytesA.getUint32(i * 4);
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

  testWidgets('parcel mode swaps the cell grid for the parcel grid', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Three owned parcels: (0,0) grass, plus the adjacent pair
    // (−1,0) water and (−1,1) grass, whose shared boundary is an edge
    // *inside* the owned region — the strong parcel grid must not draw
    // there.
    final world = _anchorWorld(
      content,
      ownedParcels: const [
        ['0', '0'],
        ['-1', '0'],
        ['-1', '1'],
      ],
    );
    // The live ambience content is dashboard-tunable (the grid alpha
    // may be set to 0 while tuning), so this test pins its own grid.
    final gridContent = ContentBundle(
      manifest: content.manifest,
      catalogue: content.catalogue,
      sprites: content.sprites,
      economy: content.economy,
      ambience: AmbienceContent(
        ambientTimeScale: content.ambience.ambientTimeScale,
        vegetationSway: content.ambience.vegetationSway,
        pedestrians: content.ambience.pedestrians,
        unownedLandWash: content.ambience.unownedLandWash,
        tileGrid: const TileGridContent(alpha: 55, colorRgb: [30, 101, 82]),
      ),
      terrain: content.terrain,
    );
    ParcelWorldProbe.recording = true;
    ParcelWorldProbe.reset();

    final boundaryKey = GlobalKey();
    Widget view({
      bool parcelMode = false,
      ParcelCoord? selectedParcel,
      bool showTileGrid = true,
    }) => ParcelWorldView(
      state: world,
      content: gridContent,
      terrainProvider: ContentTerrainProvider(content.terrain),
      onCellTap: (cell, structureId, subtileX, subtileY) {},
      parcelMode: parcelMode,
      selectedParcel: selectedParcel,
      showTileGrid: showTileGrid,
    );
    Widget app({
      bool parcelMode = false,
      ParcelCoord? selectedParcel,
      bool showTileGrid = true,
      bool frozen = false,
    }) => MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: RepaintBoundary(
          key: boundaryKey,
          // The MediaQuery stays in the tree for every variant so
          // toggling the freeze never restructures it — only the data
          // flips, which mutes the ambient ticker without recreating
          // the view state or its loaded art.
          child: MediaQuery(
            data: MediaQueryData(disableAnimations: frozen),
            child: view(
              parcelMode: parcelMode,
              selectedParcel: selectedParcel,
              showTileGrid: showTileGrid,
            ),
          ),
        ),
      ),
    );

    // Settle normal mode first — decode art, record and rasterize
    // chunks — with the ambient clock running so pumps produce frames.
    await tester.pumpWidget(app());
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
    expect(settled, isTrue, reason: 'normal-mode chunks should settle');

    // Freeze the clock here so every capture below shares one
    // pedestrian phase.
    await tester.pumpWidget(app(frozen: true));
    await tester.pump(const Duration(milliseconds: 100));

    final normal = (await _capture(tester, boundaryKey))!;
    final normalBytes = (await tester.runAsync(() => normal.toByteData()))!;

    // Switch to parcel mode and let the chunks re-record for it.
    await tester.pumpWidget(app(parcelMode: true, frozen: true));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    }
    final parcel = (await _capture(tester, boundaryKey))!;
    final parcelBytes = (await tester.runAsync(() => parcel.toByteData()))!;
    int parcelPixel(Offset point) => _pixelAt(parcel, parcelBytes, point);

    int brightness(ui.Image image, ByteData bytes, Offset point) {
      final rgba = _pixelAt(image, bytes, point);
      return ((rgba >> 24) & 0xFF) +
          ((rgba >> 16) & 0xFF) +
          ((rgba >> 8) & 0xFF);
    }

    // Unowned water shades in parcel mode only: the wash tints the
    // unowned parcel (1,0) toward the map background.
    final openWater = _screenCenterOf(const CellCoord(12, 4));
    expect(
      brightness(parcel, parcelBytes, openWater) -
          brightness(normal, normalBytes, openWater),
      greaterThan(15),
      reason: 'unowned water washes in parcel mode',
    );

    // The faint tile grid is the one renderer-owned lattice. The art's
    // own edge shading darkens cell edges too, so the grid is measured
    // as the difference between grid-on and grid-off renders of the
    // same frozen frame.
    final grassEdge = _screenCenterOf(const CellCoord(2, 2)).translate(-16, -8);
    final grassCentre = _screenCenterOf(const CellCoord(2, 2));
    await tester.pumpWidget(app(showTileGrid: false, frozen: true));
    await tester.pump(const Duration(milliseconds: 100));
    final inspect = (await _capture(tester, boundaryKey))!;
    final inspectBytes = (await tester.runAsync(() => inspect.toByteData()))!;
    expect(
      brightness(inspect, inspectBytes, grassEdge) -
          brightness(normal, normalBytes, grassEdge),
      greaterThan(8),
      reason: 'the faint tile grid tints cell edges',
    );
    expect(
      (brightness(inspect, inspectBytes, grassCentre) -
              brightness(normal, normalBytes, grassCentre))
          .abs(),
      lessThan(5),
      reason: 'the tile grid leaves cell centres alone',
    );

    // Parcel mode replaces the tile grid with its own parcel grid: its
    // cell edges match the grid-off render exactly.
    expect(
      (brightness(parcel, parcelBytes, grassEdge) -
              brightness(inspect, inspectBytes, grassEdge))
          .abs(),
      lessThan(5),
      reason: 'parcel mode hides the tile grid',
    );
    inspect.dispose();

    // The owned region's boundary is a thick dashed white line, on the
    // frontier between owned (0,0) and unowned (1,0).
    bool isWhiteDash(int rgba) {
      final r = rgba >> 24, g = (rgba >> 16) & 0xFF, b = (rgba >> 8) & 0xFF;
      return r + g + b > 600;
    }

    final frontier = [
      for (final cell in [const CellCoord(8, 4), const CellCoord(8, 5)])
        for (final t in [0.2, 0.5, 0.8])
          _screenCenterOf(cell).translate(-32.0 * t, -16.0 + 16.0 * t),
    ];
    expect(
      frontier.map(parcelPixel).any(isWhiteDash),
      isTrue,
      reason: 'the dashed white outline marks the owned frontier',
    );

    // The strong parcel grid lives only in the unowned region: it
    // draws along the southern boundary of unowned (1,0)...
    bool isParcelStroke(int rgba) {
      final r = rgba >> 24, g = (rgba >> 16) & 0xFF, b = (rgba >> 8) & 0xFF;
      return g - r > 18 && r + g + b < 340;
    }

    final unownedBoundary = [
      for (final cell in [const CellCoord(10, 8), const CellCoord(12, 8)])
        _screenCenterOf(cell).translate(16, -8),
    ];
    expect(
      unownedBoundary.map(parcelPixel).any(isParcelStroke),
      isTrue,
      reason: 'the strong parcel grid draws in the unowned region',
    );
    // ...and never inside the owned region, along the shared edge of
    // owned (−1,0) and owned (−1,1) — no stroke, no white dash.
    final ownedInterior = [
      for (final cell in [
        const CellCoord(-4, 8),
        const CellCoord(-3, 8),
        const CellCoord(-2, 8),
      ])
        _screenCenterOf(cell).translate(16, -8),
    ];
    expect(
      ownedInterior
          .map(parcelPixel)
          .any((rgba) => isParcelStroke(rgba) || isWhiteDash(rgba)),
      isFalse,
      reason: 'no parcel boundaries inside the owned region',
    );

    // Hovering the pointer over an unowned parcel highlights it —
    // desktop hover events only. The highlight fill greens the washed
    // water under the pointer.
    await tester.sendEventToBinding(PointerHoverEvent(position: openWater));
    await tester.pumpWidget(app(parcelMode: true, frozen: true));
    await tester.pump(const Duration(milliseconds: 100));
    final hovered = (await _capture(tester, boundaryKey))!;
    final hoveredBytes = (await tester.runAsync(() => hovered.toByteData()))!;
    final before = parcelPixel(openWater);
    final after = _pixelAt(hovered, hoveredBytes, openWater);
    expect(
      ((before >> 24) & 0xFF) - ((after >> 24) & 0xFF),
      greaterThan(4),
      reason: 'hover fills the unowned parcel under the pointer',
    );

    // Hovering an owned parcel highlights nothing.
    await tester.sendEventToBinding(
      PointerHoverEvent(position: _screenCenterOf(const CellCoord(2, 2))),
    );
    await tester.pumpWidget(app(parcelMode: true, frozen: true));
    await tester.pump(const Duration(milliseconds: 100));
    final ownedHover = (await _capture(tester, boundaryKey))!;
    final ownedHoverBytes = await tester.runAsync(
      () => ownedHover.toByteData(),
    );
    final grassPoint = _screenCenterOf(const CellCoord(2, 2));
    final hoveredOwned = _pixelAt(ownedHover, ownedHoverBytes!, grassPoint);
    final plainOwned = parcelPixel(grassPoint);
    for (final shift in [0, 8, 16]) {
      expect(
        (((hoveredOwned >> shift) & 0xFF) - ((plainOwned >> shift) & 0xFF))
            .abs(),
        lessThan(4),
        reason: 'owned parcels get no hover highlight',
      );
    }

    // Selecting a parcel fills it at parcel scale — owned land gets a
    // light selection wash just like cells do in other tools.
    await tester.pumpWidget(
      app(parcelMode: true, frozen: true, selectedParcel: ParcelCoord(0, 0)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final selected = (await _capture(tester, boundaryKey))!;
    final selectedBytes = await tester.runAsync(() => selected.toByteData());
    final selectedPixel = _pixelAt(selected, selectedBytes!, grassPoint);
    expect(
      ((plainOwned >> 24) & 0xFF) - ((selectedPixel >> 24) & 0xFF),
      greaterThan(4),
      reason: 'the selected owned parcel fills with the selection wash',
    );

    normal.dispose();
    parcel.dispose();
    hovered.dispose();
    ownedHover.dispose();
    selected.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
  testWidgets('mixed parcels blit in painter order across chunk seams', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // An island painted into the east water parcel (a water-origin
    // chunk) with river water painted just north of it in the grass
    // parcel (a land-origin chunk). The old water-before-land chunk
    // grouping blitted the island's chunk first, so the northern
    // water tile's bottom skirt painted over the island — the exact
    // bug seen on the river island at the map's corner.
    final terrain = TerrainContent(
      generatorVersion: content.terrain.generatorVersion,
      parcels: content.terrain.parcels,
      tiles: {
        ...content.terrain.tiles,
        const CellCoord(12, -1): TerrainKind.water,
        const CellCoord(12, 0): TerrainKind.grass,
      },
    );
    final modified = ContentBundle(
      manifest: content.manifest,
      catalogue: content.catalogue,
      sprites: content.sprites,
      economy: content.economy,
      ambience: content.ambience,
      terrain: terrain,
    );
    final world = _anchorWorld(modified);
    ParcelWorldProbe.recording = true;
    ParcelWorldProbe.reset();

    final boundaryKey = GlobalKey();
    Widget app() => MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: RepaintBoundary(
          key: boundaryKey,
          child: ParcelWorldView(
            state: world,
            content: modified,
            terrainProvider: ContentTerrainProvider(modified.terrain),
            onCellTap: (cell, structureId, subtileX, subtileY) {},
          ),
        ),
      ),
    );

    await tester.pumpWidget(app());
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

    final image = (await _capture(tester, boundaryKey))!;
    final bytes = (await tester.runAsync(() => image.toByteData()))!;

    bool isGrass(int rgba) {
      final g = (rgba >> 16) & 0xFF, b = (rgba >> 8) & 0xFF;
      return g > 100 && g - b > 20;
    }

    // The island renders as land, and the water tile north of it
    // keeps its skirt under the island instead of painting over it.
    // The northern tile's bottom skirt lands along the island's
    // north-east edge (screen (784,348)→(816,364)); these samples
    // walk that band a few pixels inside the island.
    final island = _screenCenterOf(const CellCoord(12, 0));
    expect(isGrass(_pixelAt(image, bytes, island)), isTrue);
    for (final delta in const [
      Offset(5, -13),
      Offset(9, -11),
      Offset(13, -9),
      Offset(6, -12),
      Offset(10, -10),
      Offset(14, -8),
    ]) {
      expect(
        isGrass(_pixelAt(image, bytes, island.translate(delta.dx, delta.dy))),
        isTrue,
        reason: 'the northern water tile must not skirt over the island',
      );
    }
    image.dispose();
  });
}

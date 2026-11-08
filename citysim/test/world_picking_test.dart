import 'dart:ui' as ui;

import 'package:citysim/content/asset_content_source.dart';
import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/parcel_city_app.dart';
import 'package:citysim/rendering/parcel_world_view.dart';
import 'package:citysim/rendering/sprite_picking.dart';
import 'package:citysim/storage/sheet_tables.dart';
import 'package:citysim/storage/world_sheet_codec.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:citysim/world/terrain_provider.dart';
import 'package:citysim/world/world_save_store.dart';
import 'package:citysim/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryParcelStore implements ParcelWorldStore {
  _MemoryParcelStore(this.state);

  ParcelWorldState? state;

  @override
  Future<ParcelWorldState?> load() async => state;

  @override
  Future<void> save(ParcelWorldState state) async => this.state = state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ContentBundle content;
  late ContentTerrainProvider terrain;

  setUpAll(() async {
    content = await loadContentBundle(const AssetContentSource());
    terrain = ContentTerrainProvider(content.terrain);
  });

  // A starter road, one asphalt tile east, and a 2×2 tall office at
  // (6,3) facing south. The office's screen rectangle reaches high
  // above its footprint, covering ground tiles behind it — the region
  // whose taps used to be stolen by bounding-box picking.
  ParcelWorldState worldWithTallOffice({
    List<List<String>> extraTiles = const [],
  }) => sheetTablesToWorld(
    SheetTables(
      userData: const {
        'seed': '7',
        'coins': '50',
        'coins_earned': '50',
        'coins_spent': '0',
        'simulated_date': '2026-11-05',
        'high_water_date': '2026-11-05',
        'construction_day': '10',
      },
      ownedParcels: const [
        ['0', '0'],
      ],
      tiles: [
        const ['4', '4', 'road', 'complete', 'dirt', '', '', ''],
        const ['5', '4', 'road', 'complete', 'asphalt', '', '', ''],
        const [
          '6',
          '3',
          'structure',
          'complete',
          'tall-office',
          'office-tall-blue',
          'south',
          '',
        ],
        ...extraTiles,
      ],
      projects: const [],
    ),
    content: content,
    terrainProvider: terrain,
  );

  /// Decodes a sprite's alpha through real async — the same art the
  /// app loads — so tap points derive from actual pixels. [cells] is
  /// the footprint the sprite stands on, for the renderer's anchor
  /// math.
  Future<Art> loadArt(
    String assetPath,
    String role,
    List<(int, int)> cells,
  ) async {
    final data = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    final bytes = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    final art = Art.forFootprint(
      frame.image.width,
      frame.image.height,
      bytes!,
      content.sprite(role)!,
      cells,
    );
    frame.image.dispose();
    codec.dispose();
    return art;
  }

  final officeCells = [(6, 3), (7, 3), (6, 4), (7, 4)];
  final pineCells = [(6, 2)];

  /// Pumps the map view standalone with a tap recorder, so tests can
  /// assert exactly which (cell, structure) each tap dispatched.
  Future<void> pumpView(
    WidgetTester tester,
    ParcelWorldState world, {
    required void Function(CellCoord cell, String? structureId) onTap,
    bool structurePicking = true,
    bool dimStructures = false,
    GlobalKey? boundaryKey,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: RepaintBoundary(
            key: boundaryKey,
            child: ParcelWorldView(
              state: world,
              content: content,
              terrainProvider: terrain,
              onCellTap: onTap,
              structurePicking: structurePicking,
              dimStructures: dimStructures,
            ),
          ),
        ),
      ),
    );
  }

  Future<ui.Image?> captureView(WidgetTester tester, GlobalKey key) =>
      tester.runAsync(() async {
        final boundary =
            tester.renderObject(find.byKey(key)) as RenderRepaintBoundary;
        return boundary.toImage(pixelRatio: 1);
      });

  /// The nearest cell to a world point — the renderer's picking math.
  (int, int) nearestCellOf(Offset world) {
    final gx = world.dx / 32;
    final gy = world.dy / 16;
    return (((gx + gy) / 2).round(), ((gy - gx) / 2).round());
  }

  Future<void> pumpUntilArtLoads(WidgetTester tester) async {
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1000)),
    );
    await tester.pump();
  }

  testWidgets('tapping the office roof selects the office', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final art = (await tester.runAsync(
      () => loadArt(
        'assets/sprites/buildings/offices/bld_office_tall_blue_a.png',
        'office-tall-blue',
        officeCells,
      ),
    ))!;
    // The roof: the first opaque pixel scanning from the top.
    final roof = art.firstOpaque();
    expect(roof, isNotNull, reason: 'the sprite has art');

    await tester.pumpWidget(
      ParcelCityApp(
        store: _MemoryParcelStore(worldWithTallOffice()),
        content: content,
      ),
    );
    await pumpUntilArtLoads(tester);

    final tap = art.screenTap(
      tester.getRect(find.byType(ParcelWorldView)).center,
      roof!,
    );
    await tester.tapAt(tap);
    await tester.pump();
    expect(find.textContaining('Tall Office'), findsOneWidget);
  });

  testWidgets(
    'tapping inside the office box but on transparent art selects the ground',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final art = (await tester.runAsync(
        () => loadArt(
          'assets/sprites/buildings/offices/bld_office_tall_blue_a.png',
          'office-tall-blue',
          officeCells,
        ),
      ))!;
      // A transparent pixel in the sprite's top quarter — inside the
      // bounding box (where rect picking used to steal the tap) but
      // above the roof, over ground behind the building.
      final empty = art.firstTransparent(art.height ~/ 4);
      expect(
        empty,
        isNotNull,
        reason: 'the sprite has transparent art above the roof',
      );

      await tester.pumpWidget(
        ParcelCityApp(
          store: _MemoryParcelStore(worldWithTallOffice()),
          content: content,
        ),
      );
      await pumpUntilArtLoads(tester);

      final worldPoint = art.worldPoint(empty!);
      await tester.tapAt(
        tester.getRect(find.byType(ParcelWorldView)).center +
            worldPoint -
            const Offset(0, 128),
      );
      await tester.pump();

      // The office must not be selected; the ground diamond wins. The
      // tapped ground cell is the iso inverse of the world point.
      final gx = worldPoint.dx / 32;
      final gy = worldPoint.dy / 16;
      final column = ((gx + gy) / 2).round();
      final row = ((gy - gx) / 2).round();
      expect(
        find.textContaining('Tall Office'),
        findsNothing,
        reason: 'transparent art no longer captures taps',
      );
      expect(
        find.text('Tile $column,$row'),
        findsOneWidget,
        reason: 'the ground cell behind the office is selected',
      );
    },
  );

  testWidgets('repeated taps at the same spot cycle through occluded targets', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // A pine at (6,2) stands behind the office; its depth (8) is
    // lower than the office's (11), so the office paints in front.
    final office = (await tester.runAsync(
      () => loadArt(
        'assets/sprites/buildings/offices/bld_office_tall_blue_a.png',
        'office-tall-blue',
        officeCells,
      ),
    ))!;
    final pine = (await tester.runAsync(
      () => loadArt(
        'assets/sprites/props/trees/prop_tree_pine_medium.png',
        'pine-medium',
        pineCells,
      ),
    ))!;
    final overlap = overlapPixel(back: pine, front: office);
    expect(overlap, isNotNull, reason: 'the office covers part of the pine');

    final taps = <(CellCoord, String?)>[];
    await pumpView(
      tester,
      worldWithTallOffice(
        extraTiles: [
          [
            '6',
            '2',
            'structure',
            'complete',
            'pine-tree',
            'pine-medium',
            '',
            '',
          ],
        ],
      ),
      onTap: (cell, structureId) => taps.add((cell, structureId)),
    );
    await pumpUntilArtLoads(tester);

    final tap = pine.screenTap(
      tester.getRect(find.byType(ParcelWorldView)).center,
      overlap!,
    );
    for (var i = 0; i < 4; i++) {
      await tester.tapAt(tap);
      await tester.pump();
    }

    final ground = nearestCellOf(pine.worldPoint(overlap));
    expect(taps, [
      (const CellCoord(6, 3), 'structure:6,3'), // front: the office
      (const CellCoord(6, 2), 'structure:6,2'), // hidden: the pine
      (CellCoord(ground.$1, ground.$2), null), // the ground diamond
      (const CellCoord(6, 3), 'structure:6,3'), // wraps to the front
    ]);
  });

  testWidgets('repeated taps at a different spot restart the cycle', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final office = (await tester.runAsync(
      () => loadArt(
        'assets/sprites/buildings/offices/bld_office_tall_blue_a.png',
        'office-tall-blue',
        officeCells,
      ),
    ))!;
    final roof = office.firstOpaque()!;
    final base = office.firstOpaqueFromBottom()!;
    // The sprite's bottom art is far below the roof — well beyond the
    // quarter-tile cycle radius.
    expect((base.$2 - roof.$2) * office.sprite.renderScale, greaterThan(16));

    final taps = <(CellCoord, String?)>[];
    await pumpView(
      tester,
      worldWithTallOffice(),
      onTap: (cell, structureId) => taps.add((cell, structureId)),
    );
    await pumpUntilArtLoads(tester);

    final center = tester.getRect(find.byType(ParcelWorldView)).center;
    // Two taps well apart (beyond the quarter-tile cycle radius): each
    // starts the chain at the front target again.
    await tester.tapAt(office.screenTap(center, roof));
    await tester.pump();
    await tester.tapAt(office.screenTap(center, base));
    await tester.pump();

    expect(taps, [
      (const CellCoord(6, 3), 'structure:6,3'),
      (const CellCoord(6, 3), 'structure:6,3'),
    ], reason: 'taps apart from each other each pick the front target');
  });

  testWidgets('non-inspect tools target the tapped cell, not the structure', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final office = (await tester.runAsync(
      () => loadArt(
        'assets/sprites/buildings/offices/bld_office_tall_blue_a.png',
        'office-tall-blue',
        officeCells,
      ),
    ))!;
    final roof = office.firstOpaque()!;

    final taps = <(CellCoord, String?)>[];
    await pumpView(
      tester,
      worldWithTallOffice(),
      onTap: (cell, structureId) => taps.add((cell, structureId)),
      structurePicking: false,
    );
    await pumpUntilArtLoads(tester);

    await tester.tapAt(
      office.screenTap(
        tester.getRect(find.byType(ParcelWorldView)).center,
        roof,
      ),
    );
    await tester.pump();

    final expected = nearestCellOf(office.worldPoint(roof));
    expect(taps, hasLength(1));
    expect(taps.single.$2, isNull, reason: 'no structure is picked');
    expect(
      taps.single.$1,
      CellCoord(expected.$1, expected.$2),
      reason: 'the tap targets the cell under the cursor',
    );
    expect(
      taps.single.$1,
      isNot(const CellCoord(6, 3)),
      reason:
          'a road planned over a roof must not land on the '
          "building's origin cell",
    );
  });

  testWidgets('road and bridge tools dim standing structures', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final office = (await tester.runAsync(
      () => loadArt(
        'assets/sprites/buildings/offices/bld_office_tall_blue_a.png',
        'office-tall-blue',
        officeCells,
      ),
    ))!;
    final roof = office.firstOpaque()!;
    final world = worldWithTallOffice();
    final boundaryKey = GlobalKey();

    await pumpView(
      tester,
      world,
      onTap: (cell, structureId) {},
      dimStructures: false,
      boundaryKey: boundaryKey,
    );
    await pumpUntilArtLoads(tester);
    final imageA = (await captureView(tester, boundaryKey))!;
    final bytesA = await tester.runAsync(() => imageA.toByteData());

    await pumpView(
      tester,
      world,
      onTap: (cell, structureId) {},
      dimStructures: true,
      boundaryKey: boundaryKey,
    );
    final imageB = (await captureView(tester, boundaryKey))!;
    final bytesB = await tester.runAsync(() => imageB.toByteData());

    int pixel(ui.Image image, ByteData bytes, Offset point) => bytes.getUint32(
      (point.dy.round().clamp(0, image.height - 1) * image.width +
              point.dx.round().clamp(0, image.width - 1)) *
          4,
    );
    int maxChannelDiff(int a, int b) {
      var diff = 0;
      for (final shift in [24, 16, 8]) {
        final d = ((a >> shift) & 0xFF) - ((b >> shift) & 0xFF);
        if (d.abs() > diff) diff = d.abs();
      }
      return diff;
    }

    final center = tester.getRect(find.byType(ParcelWorldView)).center;
    final roofScreen = office.screenTap(center, roof);
    // A grass cell south of the office, away from water and art.
    final groundScreen = center + const Offset(0, 72);

    expect(
      maxChannelDiff(
        pixel(imageA, bytesA!, roofScreen),
        pixel(imageB, bytesB!, roofScreen),
      ),
      greaterThan(20),
      reason: 'the office dims while the road tool is active',
    );
    expect(
      maxChannelDiff(
        pixel(imageA, bytesA, groundScreen),
        pixel(imageB, bytesB, groundScreen),
      ),
      lessThanOrEqualTo(8),
      reason: 'terrain is untouched by structure dimming',
    );

    imageA.dispose();
    imageB.dispose();
  });

  testWidgets('the app dims structures when the road tool is active', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ParcelCityApp(
        store: _MemoryParcelStore(worldWithTallOffice()),
        content: content,
      ),
    );
    await pumpUntilArtLoads(tester);

    await tester.tap(find.text('Roads').first);
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
  });
}

/// A sprite's decoded alpha plus the renderer's anchor math, replicated
/// so tests can map sprite pixels to screen tap points and back.
class Art {
  Art(this.width, this.height, ByteData bytes, this.sprite, this.worldRect)
    : alpha = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );

  Art.forFootprint(
    this.width,
    this.height,
    ByteData bytes,
    this.sprite,
    List<(int, int)> cells,
  ) : worldRect = _footprintRect(sprite, width, height, cells),
      alpha = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );

  static Rect _footprintRect(
    SpriteDefinition sprite,
    int width,
    int height,
    List<(int, int)> cells,
  ) {
    final drawnWidth = width * sprite.renderScale;
    final drawnHeight = height * sprite.renderScale;
    final anchorX =
        cells.map((c) => (c.$1 - c.$2) * 32.0).reduce((a, b) => a + b) /
        cells.length;
    final bottomY =
        cells.map((c) => (c.$1 + c.$2) * 16.0).reduce((a, b) => a > b ? a : b) +
        16;
    return Rect.fromLTWH(
      anchorX - drawnWidth * sprite.groundAnchorX,
      bottomY - drawnHeight * sprite.groundAnchorY,
      drawnWidth,
      drawnHeight,
    );
  }

  final int width;
  final int height;
  final Uint8List alpha;
  final SpriteDefinition sprite;
  final Rect worldRect;

  bool opaque(int x, int y) =>
      alpha[(y * width + x) * 4 + 3] >= SpriteMask.alphaThreshold;

  (int, int)? firstOpaque() {
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (opaque(x, y)) return (x, y);
      }
    }
    return null;
  }

  (int, int)? firstOpaqueFromBottom() {
    for (var y = height - 1; y >= 0; y--) {
      for (var x = width - 1; x >= 0; x--) {
        if (opaque(x, y)) return (x, y);
      }
    }
    return null;
  }

  (int, int)? firstTransparent(int withinRows) {
    for (var y = 0; y < withinRows; y++) {
      for (var x = 0; x < width; x++) {
        if (!opaque(x, y)) return (x, y);
      }
    }
    return null;
  }

  Offset worldPoint((int, int) pixel) =>
      worldRect.topLeft +
      Offset(
        (pixel.$1 + 0.5) * worldRect.width / width,
        (pixel.$2 + 0.5) * worldRect.height / height,
      );

  /// The art pixel covering a world point, or null when the point sits
  /// outside this sprite's rectangle.
  (int, int)? pixelAt(Offset world) {
    final fx = ((world.dx - worldRect.left) / worldRect.width * width).floor();
    final fy = ((world.dy - worldRect.top) / worldRect.height * height).floor();
    if (fx < 0 || fx >= width || fy < 0 || fy >= height) return null;
    return (fx, fy);
  }

  Offset screenTap(Offset viewCenter, (int, int) pixel) =>
      viewCenter + worldPoint(pixel) - const Offset(0, 128);
}

/// Finds a pixel of [back] that is opaque AND covered by opaque art of
/// [front] — a tap point where both structures are valid targets.
(int, int)? overlapPixel({required Art back, required Art front}) {
  for (var y = 0; y < back.height; y++) {
    for (var x = 0; x < back.width; x++) {
      if (!back.opaque(x, y)) continue;
      final world = back.worldPoint((x, y));
      final frontPixel = front.pixelAt(world);
      if (frontPixel == null) continue;
      if (front.opaque(frontPixel.$1, frontPixel.$2)) return (x, y);
    }
  }
  return null;
}

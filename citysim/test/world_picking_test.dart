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
    List<List<String>> props = const [],
    bool includeOffice = true,
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
        if (includeOffice)
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
      props: props,
      projects: const [],
    ),
    content: content,
    terrainProvider: terrain,
  );

  /// Decodes a sprite's alpha through real async — the same art the
  /// app loads — so tap points derive from actual pixels. [cells] is
  /// the footprint the sprite stands on, for the renderer's anchor
  /// math; [tileFit] uses the tile-fit anchor (bridge decks and
  /// ramps) instead of the structure anchor.
  Future<Art> loadArt(
    String assetPath,
    String role,
    List<(int, int)> cells, {
    bool tileFit = false,
  }) async {
    final data = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    final bytes = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    final art = tileFit
        ? Art.forTileFit(
            frame.image.width,
            frame.image.height,
            bytes!,
            content.sprite(role)!,
            cells.first,
          )
        : Art.forFootprint(
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

  /// A bridge world in the codec test's shape: a road to the river,
  /// the eight-tile crossing over the east water parcel, and a road
  /// on the far bank. No structures — bridges are the subject.
  ParcelWorldState worldWithBridge({List<List<String>> props = const []}) =>
      sheetTablesToWorld(
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
            ['1', '0'],
            ['2', '0'],
          ],
          tiles: [
            const ['4', '4', 'road', 'complete', 'dirt', '', '', ''],
            const ['5', '4', 'road', 'complete', 'asphalt', '', '', ''],
            const ['6', '4', 'road', 'complete', 'asphalt', '', '', ''],
            const ['7', '4', 'road', 'complete', 'asphalt', '', '', ''],
            for (var column = 8; column <= 15; column++)
              ['$column', '4', 'bridge', 'complete', '', '', '', ''],
            const ['16', '4', 'road', 'complete', 'asphalt', '', '', ''],
          ],
          props: props,
          projects: const [],
        ),
        content: content,
        terrainProvider: terrain,
      );

  /// Pumps the map view standalone with a tap recorder, so tests can
  /// assert exactly which (cell, structure) each tap dispatched.
  Future<void> pumpView(
    WidgetTester tester,
    ParcelWorldState world, {
    required void Function(
      CellCoord cell,
      String? structureId,
      int subtileX,
      int subtileY,
    )
    onTap,
    bool structurePicking = true,
    bool dimStructures = false,
    GlobalKey? boundaryKey,
    Key? viewKey,
    String? selectedPropId,
    CellCoord? selectedCell,
    String? selectedCatalogueId,
    int selectedSubtileX = propFrontSubtile,
    int selectedSubtileY = propFrontSubtile,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: RepaintBoundary(
            key: boundaryKey,
            child: ParcelWorldView(
              key: viewKey,
              state: world,
              content: content,
              terrainProvider: terrain,
              onCellTap: onTap,
              structurePicking: structurePicking,
              dimStructures: dimStructures,
              selectedCell: selectedCell,
              selectedPropId: selectedPropId,
              selectedCatalogueId: selectedCatalogueId,
              selectedSubtileX: selectedSubtileX,
              selectedSubtileY: selectedSubtileY,
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

  /// A capture plus its bytes, for pixel assertions.
  Future<(ui.Image, ByteData)> captureBytes(
    WidgetTester tester,
    GlobalKey key,
  ) async {
    final image = (await captureView(tester, key))!;
    final bytes = await tester.runAsync<ByteData?>(() => image.toByteData());
    expect(bytes, isNotNull);
    return (image, bytes!);
  }

  /// The captured pixel at a screen point, as big-endian R,G,B,A —
  /// the same layout [Art.rgba] reads from decoded sprites.
  int pixelAt((ui.Image, ByteData) capture, Offset screen) {
    final (image, bytes) = capture;
    final x = screen.dx.round().clamp(0, image.width - 1);
    final y = screen.dy.round().clamp(0, image.height - 1);
    return bytes.getUint32((y * image.width + x) * 4);
  }

  /// Largest per-channel gap between two captured pixels.
  int channelGap(int a, int b) {
    var worst = 0;
    for (var shift = 24; shift >= 8; shift -= 8) {
      final gap = (((a >> shift) & 0xFF) - ((b >> shift) & 0xFF)).abs();
      if (gap > worst) worst = gap;
    }
    return worst;
  }

  /// Finds a pixel of [back] that sits under opaque art of [front],
  /// interior to both — the pixel and its neighbours are near-solid
  /// in each sprite, so resampling and anti-aliased edges cannot
  /// fake a match. Null when the two sprites never overlap like that.
  (int, int)? overlapInteriorPixel({required Art back, required Art front}) {
    bool solid3x3(Art art, int x, int y) {
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final px = x + dx;
          final py = y + dy;
          if (px < 0 || px >= art.width || py < 0 || py >= art.height) {
            return false;
          }
          if (art.alpha[(py * art.width + px) * 4 + 3] < 200) return false;
        }
      }
      return true;
    }

    for (var y = 1; y < back.height - 1; y++) {
      for (var x = 1; x < back.width - 1; x++) {
        if (!solid3x3(back, x, y)) continue;
        final world = back.worldPoint((x, y));
        final frontPixel = front.pixelAt(world);
        if (frontPixel == null) continue;
        if (!solid3x3(front, frontPixel.$1, frontPixel.$2)) continue;
        return (x, y);
      }
    }
    return null;
  }

  /// Any near-solid interior pixel of [art].
  (int, int)? interiorPixel(Art art) {
    for (var y = 1; y < art.height - 1; y++) {
      for (var x = 1; x < art.width - 1; x++) {
        var solid = true;
        for (var dy = -1; dy <= 1 && solid; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if (art.alpha[((y + dy) * art.width + (x + dx)) * 4 + 3] < 200) {
              solid = false;
              break;
            }
          }
        }
        if (solid) return (x, y);
      }
    }
    return null;
  }

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
    'tapping inside the office box but on transparent art selects nothing',
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

      // The office must not be selected — and under the
      // objects-only inspect rule, neither is anything else: the
      // transparent art lets the tap fall through to plain ground,
      // which highlights nothing (the ground cell is still resolved
      // for tools that need it, but inspect shows no panel).
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
        findsNothing,
        reason: 'plain terrain selects nothing in inspect mode',
      );
      expect(
        find.textContaining('Tile '),
        findsNothing,
        reason: 'no ground panel at all',
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
        props: const [
          ['6', '2', '7', '7', 'pine-tree', 'pine-medium', ''],
        ],
      ),
      onTap: (cell, structureId, subtileX, subtileY) =>
          taps.add((cell, structureId)),
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
      (const CellCoord(6, 2), 'prop:6,2:7.7'), // hidden: the pine
      (CellCoord(ground.$1, ground.$2), null), // the ground diamond
      (const CellCoord(6, 3), 'structure:6,3'), // wraps to the front
    ]);
  });

  testWidgets('taps report the subtile under the point', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final taps = <(CellCoord, int, int)>[];
    await pumpView(
      tester,
      worldWithTallOffice(),
      onTap: (cell, structureId, subtileX, subtileY) =>
          taps.add((cell, subtileX, subtileY)),
    );
    await pumpUntilArtLoads(tester);

    // Screen points around cell (5,5)'s world centre (0, 160); the
    // default camera centres world (0, 128) at the viewport centre
    // (400, 300) at scale 1. Points stay off the diamond's vertices,
    // where cell rounding is ambiguous.
    Offset screenFor(Offset world) =>
        const Offset(400, 300) + (world - const Offset(0, 128));
    // Dead centre of the tile — the corner shared by the four middle
    // subtiles; the floor picks the south-east one.
    await tester.tapAt(screenFor(const Offset(0, 160)));
    await tester.pump();
    // A quarter tile east along the column axis.
    await tester.tapAt(screenFor(const Offset(8, 164)));
    await tester.pump();
    // East and a little south.
    await tester.tapAt(screenFor(const Offset(4, 166)));
    await tester.pump();
    expect(taps, [
      (const CellCoord(5, 5), 4, 4),
      (const CellCoord(5, 5), 6, 4),
      (const CellCoord(5, 5), 6, 5),
    ]);
  });

  testWidgets('a front-corner prop draws behind the structure in front', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // A street-lamp prop at (6,2)'s front subtile — depth 8.94 —
    // under the 2×2 tall office at (6,3)–(7,4) — depth 11. The prop
    // must draw behind the office where their art overlaps.
    final lamp = (await tester.runAsync(
      () => loadArt(
        'assets/sprites/props/streetside/prop_lightpole_a.png',
        'lightpole-a',
        [(6, 2)],
      ),
    ))!;
    final office = (await tester.runAsync(
      () => loadArt(
        'assets/sprites/buildings/offices/bld_office_tall_blue_a.png',
        'office-tall-blue',
        officeCells,
      ),
    ))!;
    final overlap = overlapInteriorPixel(back: lamp, front: office);
    expect(overlap, isNotNull, reason: 'the office covers part of the lamp');
    final officePixel = office.pixelAt(lamp.worldPoint(overlap!))!;
    expect(
      channelGap(
        lamp.rgba(overlap.$1, overlap.$2),
        office.rgba(officePixel.$1, officePixel.$2),
      ),
      greaterThan(20),
      reason: 'the overlap pixel discriminates lamp from office',
    );

    final boundaryKey = GlobalKey();
    Future<(ui.Image, ByteData)> render(bool withProp) async {
      await pumpView(
        tester,
        worldWithTallOffice(
          props: withProp
              ? const [
                  ['6', '2', '7', '7', 'street-lamp', 'lightpole-a', ''],
                ]
              : const [],
        ),
        onTap: (cell, structureId, subtileX, subtileY) {},
        boundaryKey: boundaryKey,
      );
      await pumpUntilArtLoads(tester);
      return captureBytes(tester, boundaryKey);
    }

    final withProp = await render(true);
    final officeOnly = await render(false);
    final center = tester.getRect(find.byType(ParcelWorldView)).center;
    final point = lamp.screenTap(center, overlap);
    expect(
      channelGap(pixelAt(withProp, point), pixelAt(officeOnly, point)),
      lessThanOrEqualTo(3),
      reason:
          'the structure on the tiles in front paints over the '
          'front-corner prop',
    );
  });

  testWidgets('a prop draws in front of the structure behind it', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // A street-lamp prop mid-tile at (6,2) — depth 8.5 — over a tall
    // office behind at (4,0)–(5,1) — depth 6. The prop must paint
    // over the office where their art overlaps. (The front office is
    // left out of this world so nothing stands between them.)
    final lampBytes = (await tester.runAsync(() async {
      final data = await rootBundle.load(
        'assets/sprites/props/streetside/prop_lightpole_a.png',
      );
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      final frame = await codec.getNextFrame();
      final bytes = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      final size = (frame.image.width, frame.image.height);
      frame.image.dispose();
      codec.dispose();
      return (size.$1, size.$2, bytes);
    }))!;
    final lamp = Art.forProp(
      lampBytes.$1,
      lampBytes.$2,
      lampBytes.$3!,
      content.sprite('lightpole-a')!,
      cell: (6, 2),
      subtileX: 4,
      subtileY: 4,
    );
    final officeBehindCells = [(4, 0), (5, 0), (4, 1), (5, 1)];
    final office = (await tester.runAsync(
      () => loadArt(
        'assets/sprites/buildings/offices/bld_office_tall_blue_a.png',
        'office-tall-blue',
        officeBehindCells,
      ),
    ))!;
    final overlap = overlapInteriorPixel(back: office, front: lamp);
    expect(overlap, isNotNull, reason: 'the lamp covers part of the office');
    final lampPixel = lamp.pixelAt(office.worldPoint(overlap!))!;
    expect(
      channelGap(
        office.rgba(overlap.$1, overlap.$2),
        lamp.rgba(lampPixel.$1, lampPixel.$2),
      ),
      greaterThan(20),
      reason: 'the overlap pixel discriminates office from lamp',
    );

    final boundaryKey = GlobalKey();
    Future<(ui.Image, ByteData)> render(bool withOffice) async {
      await pumpView(
        tester,
        worldWithTallOffice(
          includeOffice: false,
          extraTiles: withOffice
              ? [
                  const [
                    '4',
                    '0',
                    'structure',
                    'complete',
                    'tall-office',
                    'office-tall-blue',
                    'south',
                    '',
                  ],
                ]
              : const [],
          props: const [
            ['6', '2', '4', '4', 'street-lamp', 'lightpole-a', ''],
          ],
        ),
        onTap: (cell, structureId, subtileX, subtileY) {},
        boundaryKey: boundaryKey,
      );
      await pumpUntilArtLoads(tester);
      return captureBytes(tester, boundaryKey);
    }

    final withOffice = await render(true);
    final lampOnly = await render(false);
    final center = tester.getRect(find.byType(ParcelWorldView)).center;
    final point = office.screenTap(center, overlap);
    expect(
      channelGap(pixelAt(withOffice, point), pixelAt(lampOnly, point)),
      lessThanOrEqualTo(3),
      reason: 'the prop paints over the structure on the tiles behind',
    );
  });

  test('prop depths stay inside their tile slot', () {
    PlacedProp prop(int column, int row, int subtileX, int subtileY) =>
        PlacedProp(
          id: 'prop:$column,$row:$subtileX.$subtileY',
          catalogueId: 'street-lamp',
          cell: CellCoord(column, row),
          subtileX: subtileX,
          subtileY: subtileY,
          pricePaid: 3,
          placedAtDay: 0,
        );
    // The half-weight subtile depth keeps every prop strictly between
    // its own tile's depth (8) and the next tile's (9): a
    // front-corner prop stays behind whatever stands on the tile in
    // front, exactly like the 1×1 structures props used to be.
    // Pedestrian-weight fractions would reach 9.875 and flip this.
    final frontCorner = prop(6, 2, 7, 7);
    expect(propDepth(frontCorner), greaterThan(8));
    expect(propDepth(frontCorner), lessThan(9));
    // A back-corner prop on the tile in front sorts ahead of it.
    expect(propDepth(prop(6, 3, 0, 0)), greaterThan(propDepth(frontCorner)));
    // Same-tile subtiles order back to front.
    expect(propDepth(prop(6, 2, 0, 0)), lessThan(propDepth(frontCorner)));
  });

  testWidgets('the decor ghost previews the pending subtile', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // A pine model selected with cell (5,5) and subtile (2,3) tapped
    // (the touch path — no hover in tests): the ghost draws the
    // sprite translucent at that subtile, plus the small filled
    // diamond centred on it.
    final role = content.structure('pine-tree')!.assetRoles.first;
    final sprite = content.sprite(role)!;
    final path = content.tryAssetPathFor(role, null)!;
    final (width, height, raw) = (await tester.runAsync(() async {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      final frame = await codec.getNextFrame();
      final bytes = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      final size = (frame.image.width, frame.image.height);
      frame.image.dispose();
      codec.dispose();
      return (size.$1, size.$2, bytes);
    }))!;
    final pine = Art.forProp(
      width,
      height,
      raw!,
      sprite,
      cell: (5, 5),
      subtileX: 2,
      subtileY: 3,
    );
    final pixel = interiorPixel(pine);
    expect(pixel, isNotNull, reason: 'the ghost art has interior pixels');

    final boundaryKey = GlobalKey();
    Future<(ui.Image, ByteData)> render(bool selected) async {
      await pumpView(
        tester,
        worldWithTallOffice(),
        onTap: (cell, structureId, subtileX, subtileY) {},
        boundaryKey: boundaryKey,
        selectedCatalogueId: selected ? 'pine-tree' : null,
        selectedCell: selected ? const CellCoord(5, 5) : null,
        selectedSubtileX: 2,
        selectedSubtileY: 3,
      );
      await pumpUntilArtLoads(tester);
      return captureBytes(tester, boundaryKey);
    }

    final plain = await render(false);
    final ghost = await render(true);
    final center = tester.getRect(find.byType(ParcelWorldView)).center;
    final point = pine.screenTap(center, pixel!);

    // The ghost is the sprite at 45% opacity (0x73) over whatever was
    // there — the plain render's grass.
    final grassPx = pixelAt(plain, point);
    final ghostPx = pixelAt(ghost, point);
    final artPx = pine.rgba(pixel.$1, pixel.$2);
    int blended(int art, int grass) => (0.451 * art + 0.549 * grass).round();
    expect(
      ((ghostPx >> 24) & 0xFF) -
          blended((artPx >> 24) & 0xFF, (grassPx >> 24) & 0xFF),
      lessThanOrEqualTo(8),
      reason: 'ghost red channel',
    );
    expect(
      ((ghostPx >> 16) & 0xFF) -
          blended((artPx >> 16) & 0xFF, (grassPx >> 16) & 0xFF),
      lessThanOrEqualTo(8),
      reason: 'ghost green channel',
    );
    expect(
      ((ghostPx >> 8) & 0xFF) -
          blended((artPx >> 8) & 0xFF, (grassPx >> 8) & 0xFF),
      lessThanOrEqualTo(8),
      reason: 'ghost blue channel',
    );

    // The subtile diamond marker: the wash colour over the trunk or
    // grass reads strongly green.
    final fx = (2 + 0.5) / propSubtilesPerAxis - 0.5;
    final fy = (3 + 0.5) / propSubtilesPerAxis - 0.5;
    final markerWorld = Offset(
      (5 - 5) * 32.0 + (fx - fy) * 32,
      (5 + 5) * 16.0 + (fx + fy) * 16,
    );
    final markerScreen = center + markerWorld - const Offset(0, 128);
    final markerPx = pixelAt(ghost, markerScreen);
    expect(
      ((markerPx >> 16) & 0xFF) - ((markerPx >> 24) & 0xFF),
      greaterThan(25),
      reason: 'the wash-coloured marker shows on the target subtile',
    );
  });

  testWidgets('taps on a raised bridge deck resolve to the deck cell', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // The west-most deck tile at (8,4): its top railing sits well
    // above the cell, so the ground projection of a railing tap
    // lands on a different tile — the old bug that made half the
    // bridge unclickable. The sprite hit must report the deck cell.
    final deck = (await tester.runAsync(
      () => loadArt(
        'assets/sprites/bridges/body/tile_road_bridge_body_SE_normal.png',
        'bridge.body.se',
        [(8, 4)],
        tileFit: true,
      ),
    ))!;
    final pixel = deck.firstOpaque();
    expect(pixel, isNotNull, reason: 'the deck art has opaque pixels');
    final projected = nearestCellOf(deck.worldPoint(pixel!));
    expect(
      CellCoord(projected.$1, projected.$2),
      isNot(const CellCoord(8, 4)),
      reason: 'the railing tap ground-projects off the deck cell',
    );

    for (final picking in [true, false]) {
      final taps = <(CellCoord, String?)>[];
      // A fresh view per round: the tap-cycle state (same-spot
      // window) must not carry across rounds.
      await pumpView(
        tester,
        worldWithBridge(),
        onTap: (cell, structureId, subtileX, subtileY) =>
            taps.add((cell, structureId)),
        structurePicking: picking,
        viewKey: UniqueKey(),
      );
      await pumpUntilArtLoads(tester);
      await tester.tapAt(
        deck.screenTap(
          tester.getRect(find.byType(ParcelWorldView)).center,
          pixel,
        ),
      );
      await tester.pump();
      expect(taps.single, (
        const CellCoord(8, 4),
        null,
      ), reason: 'picking=$picking: the deck hit corrects the projection');
    }
  });

  testWidgets('taps on a bridge ramp resolve to its bank cell', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ramp = (await tester.runAsync(
      () => loadArt(
        'assets/sprites/bridges/ramp/tile_road_bridge_ramp_NW_normal.png',
        'bridge.ramp.nw',
        [(7, 4)],
        tileFit: true,
      ),
    ))!;
    final deck = (await tester.runAsync(
      () => loadArt(
        'assets/sprites/bridges/body/tile_road_bridge_body_SE_normal.png',
        'bridge.body.se',
        [(8, 4)],
        tileFit: true,
      ),
    ))!;
    // An elevated ramp pixel — its ground projection lands off the
    // bank cell — that the deck in front does not cover.
    (int, int)? pixel;
    for (var y = 0; y < ramp.height && pixel == null; y++) {
      for (var x = 0; x < ramp.width && pixel == null; x++) {
        if (!ramp.opaque(x, y)) continue;
        final world = ramp.worldPoint((x, y));
        final projected = nearestCellOf(world);
        if (CellCoord(projected.$1, projected.$2) == const CellCoord(7, 4)) {
          continue;
        }
        final deckPixel = deck.pixelAt(world);
        if (deckPixel != null && deck.opaque(deckPixel.$1, deckPixel.$2)) {
          continue;
        }
        pixel = (x, y);
      }
    }
    expect(pixel, isNotNull, reason: 'the ramp has exposed elevated art');

    final taps = <(CellCoord, String?)>[];
    await pumpView(
      tester,
      worldWithBridge(),
      onTap: (cell, structureId, subtileX, subtileY) =>
          taps.add((cell, structureId)),
      structurePicking: false,
    );
    await pumpUntilArtLoads(tester);
    await tester.tapAt(
      ramp.screenTap(
        tester.getRect(find.byType(ParcelWorldView)).center,
        pixel!,
      ),
    );
    await tester.pump();
    expect(taps.single, (
      const CellCoord(7, 4),
      null,
    ), reason: 'the ramp hit reports its bank cell');
  });

  testWidgets('props on a bridge deck stand on the deck surface', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // The same lamp at the front subtile of a grass cell (5,5) and a
    // deck cell (10,4). The two anchors differ by the pure cell
    // delta — x: 192, y: 64 — minus the deck's surface lift, so the
    // lamp's diff bounding boxes must sit 58 px apart vertically.
    final (width, height, raw) = (await tester.runAsync(() async {
      final data = await rootBundle.load(
        'assets/sprites/props/streetside/prop_lightpole_a.png',
      );
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      final frame = await codec.getNextFrame();
      final bytes = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      final size = (frame.image.width, frame.image.height);
      frame.image.dispose();
      codec.dispose();
      return (size.$1, size.$2, bytes);
    }))!;
    final sprite = content.sprite('lightpole-a')!;
    final grassLamp = Art.forProp(
      width,
      height,
      raw!,
      sprite,
      cell: (5, 5),
      subtileX: 7,
      subtileY: 7,
    );
    final deckLamp = Art.forProp(
      width,
      height,
      raw,
      sprite,
      cell: (10, 4),
      subtileX: 7,
      subtileY: 7,
    );

    final boundaryKey = GlobalKey();
    Future<(ui.Image, ByteData)> render(
      List<List<String>> props,
      CellCoord? selectedCell,
      String? selectedPropId,
    ) async {
      await pumpView(
        tester,
        worldWithBridge(props: props),
        onTap: (cell, structureId, subtileX, subtileY) {},
        boundaryKey: boundaryKey,
        selectedCell: selectedCell,
        selectedPropId: selectedPropId,
      );
      await pumpUntilArtLoads(tester);
      return captureBytes(tester, boundaryKey);
    }

    // Both lamps render selected: the selection wash guarantees a
    // strong colour shift on every sprite pixel (the raw lamp greys
    // sit too close to the deck art to diff reliably), and a
    // selected prop holds still, so sway cannot shift the boxes.
    final reference = await render(const [], null, null);
    final onGrass = await render(
      const [
        ['5', '5', '7', '7', 'street-lamp', 'lightpole-a', ''],
      ],
      const CellCoord(5, 5),
      'prop:5,5:7.7',
    );
    final onDeck = await render(
      const [
        ['10', '4', '7', '7', 'street-lamp', 'lightpole-a', ''],
      ],
      const CellCoord(10, 4),
      'prop:10,4:7.7',
    );

    final center = tester.getRect(find.byType(ParcelWorldView)).center;
    Rect screenWindow(Art art) => Rect.fromLTRB(
      center.dx + art.worldRect.left - 4,
      center.dy + art.worldRect.top - 4 - 128,
      center.dx + art.worldRect.right + 4,
      center.dy + art.worldRect.bottom + 4 - 128,
    );
    Rect diffBBox(
      (ui.Image, ByteData) scene,
      (ui.Image, ByteData) ref,
      Rect window,
    ) {
      final (image, _) = scene;
      var left = window.right, right = window.left;
      var top = window.bottom, bottom = window.top;
      for (var y = window.top.floor(); y <= window.bottom.ceil(); y++) {
        for (var x = window.left.floor(); x <= window.right.ceil(); x++) {
          final px = x.clamp(0, image.width - 1).toDouble();
          final py = y.clamp(0, image.height - 1).toDouble();
          if (channelGap(
                pixelAt(scene, Offset(px, py)),
                pixelAt(ref, Offset(px, py)),
              ) >
              6) {
            if (px < left) left = px;
            if (px > right) right = px;
            if (py < top) top = py;
            if (py > bottom) bottom = py;
          }
        }
      }
      expect(
        right,
        greaterThan(left),
        reason: 'the lamp appears inside its window',
      );
      return Rect.fromLTRB(left, top, right, bottom);
    }

    final grassBox = diffBBox(onGrass, reference, screenWindow(grassLamp));
    final deckBox = diffBBox(onDeck, reference, screenWindow(deckLamp));
    expect(
      deckBox.left - grassBox.left,
      closeTo(192, 1),
      reason: 'the pure cell delta on x',
    );
    expect(
      deckBox.top - grassBox.top,
      closeTo(58, 2),
      reason:
          'cell delta 64 minus the 6px deck surface lift — the lamp '
          'head rises above the selected cell\'s outline, so the box '
          'top is the sprite\'s own',
    );
  });

  testWidgets('an invalid placement spot previews red', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // The same street-lamp selection at a valid grass cell and an
    // invalid water cell: the ghost's subtile marker flips from the
    // selection green to the line preview's invalid red.
    final boundaryKey = GlobalKey();
    Future<(ui.Image, ByteData)> render(CellCoord cell) async {
      await pumpView(
        tester,
        worldWithBridge(),
        onTap: (cell, structureId, subtileX, subtileY) {},
        boundaryKey: boundaryKey,
        selectedCatalogueId: 'street-lamp',
        selectedCell: cell,
        selectedSubtileX: 3,
        selectedSubtileY: 3,
      );
      await pumpUntilArtLoads(tester);
      return captureBytes(tester, boundaryKey);
    }

    final valid = await render(const CellCoord(5, 5));
    final invalid = await render(const CellCoord(10, 5));

    final center = tester.getRect(find.byType(ParcelWorldView)).center;
    Offset markerOf(CellCoord cell) {
      final fx = (3 + 0.5) / propSubtilesPerAxis - 0.5;
      final fy = (3 + 0.5) / propSubtilesPerAxis - 0.5;
      return center +
          Offset(
            (cell.column - cell.row) * 32.0 + (fx - fy) * 32,
            (cell.column + cell.row) * 16.0 + (fx + fy) * 16,
          ) -
          const Offset(0, 128);
    }

    final validPx = pixelAt(valid, markerOf(const CellCoord(5, 5)));
    final invalidPx = pixelAt(invalid, markerOf(const CellCoord(10, 5)));
    expect(
      ((validPx >> 16) & 0xFF) - ((validPx >> 24) & 0xFF),
      greaterThan(25),
      reason: 'a valid spot previews green',
    );
    expect(
      ((invalidPx >> 24) & 0xFF) - ((invalidPx >> 16) & 0xFF),
      greaterThan(25),
      reason: 'an invalid spot previews red',
    );
  });

  testWidgets('selecting a prop washes its sprite in place', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // A lone lamp far from the office, so nothing else overlaps it.
    final lamp = (await tester.runAsync(
      () => loadArt(
        'assets/sprites/props/streetside/prop_lightpole_a.png',
        'lightpole-a',
        [(2, 2)],
      ),
    ))!;
    final pixel = interiorPixel(lamp);
    expect(pixel, isNotNull, reason: 'the lamp has interior art');

    final boundaryKey = GlobalKey();
    ParcelWorldState world() => worldWithTallOffice(
      props: const [
        ['2', '2', '7', '7', 'street-lamp', 'lightpole-a', ''],
      ],
    );
    await pumpView(
      tester,
      world(),
      onTap: (cell, structureId, subtileX, subtileY) {},
      boundaryKey: boundaryKey,
    );
    await pumpUntilArtLoads(tester);
    final before = await captureBytes(tester, boundaryKey);
    await pumpView(
      tester,
      world(),
      onTap: (cell, structureId, subtileX, subtileY) {},
      boundaryKey: boundaryKey,
      selectedCell: const CellCoord(2, 2),
      selectedPropId: 'prop:2,2:7.7',
    );
    await tester.pump();
    final after = await captureBytes(tester, boundaryKey);

    final center = tester.getRect(find.byType(ParcelWorldView)).center;
    final point = lamp.screenTap(center, pixel!);
    final beforePx = pixelAt(before, point);
    final afterPx = pixelAt(after, point);
    // The selection wash: srcATop with 0x664BC69B over opaque art is
    // 60% original blended with 40% of the wash colour.
    int washed(int beforeChannel, int washChannel) =>
        (0.6 * beforeChannel + 0.4 * washChannel).round();
    expect(
      ((afterPx >> 24) & 0xFF) - washed((beforePx >> 24) & 0xFF, 0x4B),
      lessThanOrEqualTo(3),
    );
    expect(
      ((afterPx >> 16) & 0xFF) - washed((beforePx >> 16) & 0xFF, 0xC6),
      lessThanOrEqualTo(3),
    );
    expect(
      ((afterPx >> 8) & 0xFF) - washed((beforePx >> 8) & 0xFF, 0x9B),
      lessThanOrEqualTo(3),
    );
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
      onTap: (cell, structureId, subtileX, subtileY) =>
          taps.add((cell, structureId)),
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
      onTap: (cell, structureId, subtileX, subtileY) =>
          taps.add((cell, structureId)),
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
      onTap: (cell, structureId, subtileX, subtileY) {},
      dimStructures: false,
      boundaryKey: boundaryKey,
    );
    await pumpUntilArtLoads(tester);
    final imageA = (await captureView(tester, boundaryKey))!;
    final bytesA = await tester.runAsync(() => imageA.toByteData());

    await pumpView(
      tester,
      world,
      onTap: (cell, structureId, subtileX, subtileY) {},
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

  /// The renderer's prop anchor: the sprite's ground anchor pinned to
  /// a subtile's south vertex — the sub-lattice version of the
  /// footprint anchor above.
  Art.forProp(
    this.width,
    this.height,
    ByteData bytes,
    this.sprite, {
    required (int, int) cell,
    required int subtileX,
    required int subtileY,
  }) : worldRect = _propAnchorRect(
         sprite,
         width,
         height,
         cell,
         subtileX,
         subtileY,
       ),
       alpha = bytes.buffer.asUint8List(
         bytes.offsetInBytes,
         bytes.lengthInBytes,
       );

  /// The renderer's tile-fit anchor for bridge decks and ramps:
  /// width stretched to the tile, height at the art's aspect, hanging
  /// below the diamond by the sprite's baseOffsetY.
  Art.forTileFit(
    this.width,
    this.height,
    ByteData bytes,
    this.sprite,
    (int, int) cell,
  ) : worldRect = _tileFitRect(sprite, width, height, cell),
      alpha = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );

  static Rect _tileFitRect(
    SpriteDefinition sprite,
    int width,
    int height,
    (int, int) cell,
  ) {
    final centerX = (cell.$1 - cell.$2) * 32.0;
    final centerY = (cell.$1 + cell.$2) * 16.0;
    final unit = 64.0 / width;
    final drawnWidth = width * unit;
    final drawnHeight = height * unit;
    final southVertexY = centerY + 16 + sprite.baseOffsetY * unit;
    return Rect.fromLTWH(
      centerX - drawnWidth / 2,
      southVertexY - drawnHeight,
      drawnWidth,
      drawnHeight,
    );
  }

  static Rect _propAnchorRect(
    SpriteDefinition sprite,
    int width,
    int height,
    (int, int) cell,
    int subtileX,
    int subtileY,
  ) {
    final centerX = (cell.$1 - cell.$2) * 32.0;
    final centerY = (cell.$1 + cell.$2) * 16.0;
    final fx = (subtileX + 0.5) / propSubtilesPerAxis - 0.5;
    final fy = (subtileY + 0.5) / propSubtilesPerAxis - 0.5;
    final anchorX = centerX + (fx - fy) * 32.0;
    final bottomY = centerY + (fx + fy) * 16.0 + 2.0;
    final drawnWidth = width * sprite.renderScale;
    final drawnHeight = height * sprite.renderScale;
    return Rect.fromLTWH(
      anchorX - drawnWidth * sprite.groundAnchorX,
      bottomY - drawnHeight * sprite.groundAnchorY,
      drawnWidth,
      drawnHeight,
    );
  }

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

  /// The sprite pixel's straight RGBA, laid out like captured pixels.
  int rgba(int x, int y) {
    final i = (y * width + x) * 4;
    return (alpha[i] << 24) |
        (alpha[i + 1] << 16) |
        (alpha[i + 2] << 8) |
        alpha[i + 3];
  }

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

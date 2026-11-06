import 'dart:ui' as ui;

import 'package:citysim/content/asset_content_source.dart';
import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/parcel_city_app.dart';
import 'package:citysim/rendering/parcel_world_view.dart';
import 'package:citysim/rendering/sprite_picking.dart';
import 'package:citysim/storage/sheet_tables.dart';
import 'package:citysim/storage/world_sheet_codec.dart';
import 'package:citysim/world/terrain_provider.dart';
import 'package:citysim/world/world_save_store.dart';
import 'package:citysim/world/world_state.dart';
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
  // (6,3) facing left. The office's screen rectangle reaches high
  // above its footprint, covering ground tiles behind it — the region
  // whose taps used to be stolen by bounding-box picking.
  ParcelWorldState worldWithTallOffice() => sheetTablesToWorld(
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
      tiles: const [
        ['4', '4', 'road', 'complete', 'dirt', '', '', ''],
        ['5', '4', 'road', 'complete', 'asphalt', '', '', ''],
        [
          '6',
          '3',
          'structure',
          'complete',
          'tall-office',
          'office-tall-blue',
          'left',
          '',
        ],
      ],
      projects: const [],
    ),
    content: content,
    terrainProvider: terrain,
  );

  /// Decodes the office sprite's alpha through real async — the same
  /// art the app loads — so tap points derive from actual pixels.
  Future<Art> loadOfficeArt() async {
    final data = await rootBundle.load(
      'assets/sprites/buildings/offices/bld_office_tall_blue_a.png',
    );
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    final bytes = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    final art = Art(
      frame.image.width,
      frame.image.height,
      bytes!,
      content.sprite('office-tall-blue')!,
    );
    frame.image.dispose();
    codec.dispose();
    return art;
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

    final art = (await tester.runAsync(loadOfficeArt))!;
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

      final art = (await tester.runAsync(loadOfficeArt))!;
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
}

/// The office sprite's decoded alpha plus the renderer's anchor math,
/// replicated so tests can map sprite pixels to screen tap points.
class Art {
  Art(this.width, this.height, ByteData bytes, this.sprite)
    : alpha = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );

  final int width;
  final int height;
  final Uint8List alpha;
  final SpriteDefinition sprite;

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

  (int, int)? firstTransparent(int withinRows) {
    for (var y = 0; y < withinRows; y++) {
      for (var x = 0; x < width; x++) {
        if (!opaque(x, y)) return (x, y);
      }
    }
    return null;
  }

  /// The sprite's world rectangle, from the renderer's anchor math for
  /// the 2×2 office at origin (6,3).
  Rect get worldRect {
    const cells = [(6, 3), (7, 3), (6, 4), (7, 4)];
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

  Offset worldPoint((int, int) pixel) =>
      worldRect.topLeft +
      Offset(
        (pixel.$1 + 0.5) * worldRect.width / width,
        (pixel.$2 + 0.5) * worldRect.height / height,
      );

  Offset screenTap(Offset viewCenter, (int, int) pixel) =>
      viewCenter + worldPoint(pixel) - const Offset(0, 128);
}

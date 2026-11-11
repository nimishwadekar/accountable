/// Fog rendering tests: the cloud deck tiles over fog parcels —
/// a terrain like any other, drawn from sprites — with no shore
/// banks bleeding land material onto the clouds.
///
/// The world is the chunk render test's anchor world — roads on the
/// starter parcel — under a terrain provider that charts only parcel
/// (0, 0) as grass; everything else is fog. The fixed 800x600 camera
/// centred on cell (4, 4) then shows the starter parcel as an island
/// in the fog, with the boundary running along the parcel's edges.
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

/// Only the starter parcel is charted grass; the rest of the world is
/// fog, authored and unauthored alike.
class _FogBeyondStarter implements TerrainProvider {
  @override
  int get generatorVersion => 1;

  @override
  TerrainCell sample(CellCoord coord, int seed) => TerrainCell(
    coord: coord,
    kind: parcelForCell(coord) == const ParcelCoord(0, 0)
        ? TerrainKind.grass
        : TerrainKind.fog,
  );
}

ParcelWorldState _islandWorld(ContentBundle content) => sheetTablesToWorld(
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
  terrainProvider: _FogBeyondStarter(),
);

/// Screen position of a cell's centre for the test's fixed camera:
/// an 800x600 view, scale 1, centred on the starter cell (4, 4).
Offset _screenCenterOf(CellCoord cell) {
  final world = Offset(
    (cell.column - cell.row) * 32.0,
    (cell.column + cell.row) * 16.0,
  );
  const start = Offset(0, 128); // world centre of cell (4, 4).
  return const Offset(400, 300) + (world - start);
}

Future<(ui.Image, ByteData)> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
) async {
  final image = (await tester.runAsync(() async {
    final boundary =
        tester.renderObject(find.byKey(boundaryKey)) as RenderRepaintBoundary;
    return boundary.toImage(pixelRatio: 1);
  }))!;
  final bytes = (await tester.runAsync<ByteData?>(() => image.toByteData()))!;
  return (image, bytes);
}

/// The captured pixel at a screen point, as big-endian R,G,B,A.
int _pixelAt((ui.Image, ByteData) capture, Offset point) {
  final (image, bytes) = capture;
  final x = point.dx.round().clamp(0, image.width - 1);
  final y = point.dy.round().clamp(0, image.height - 1);
  return bytes.getUint32((y * image.width + x) * 4);
}

int _red(int pixel) => (pixel >> 24) & 0xFF;
int _blue(int pixel) => (pixel >> 8) & 0xFF;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ContentBundle content;
  setUpAll(() async {
    content = await loadContentBundle(const AssetContentSource());
  });

  testWidgets('fog parcels render the cloud deck from sprites', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: RepaintBoundary(
            key: boundaryKey,
            child: ParcelWorldView(
              state: _islandWorld(content),
              content: content,
              terrainProvider: _FogBeyondStarter(),
              onCellTap: (cell, structureId, subtileX, subtileY) {},
            ),
          ),
        ),
      ),
    );
    // Settle: decode the sprites and rasterize the chunks.
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();
    final capture = await _capture(tester, boundaryKey);

    // Deep fog — cell (12, 4), four cells past the boundary — must
    // be cloud, not the water it once was (water art reads ~66, 98,
    // 118) and not the mint background (181, 220, 207).
    final deck = _pixelAt(capture, _screenCenterOf(const CellCoord(12, 4)));
    expect(_red(deck), greaterThan(200), reason: 'cloud deck, not water');
    expect(_blue(deck), greaterThan(195), reason: 'cloud deck, not mint');

    // The fog rim — cell (8, 2), the first fog cell — must stay
    // cloud-coloured: no shore-bank art may bleed land material over
    // the clouds (grass reads R-B ~ +74, cloud ~ -5).
    final rim = _pixelAt(capture, _screenCenterOf(const CellCoord(8, 2)));
    expect(
      _red(rim) - _blue(rim),
      lessThan(30),
      reason: 'no shore bank art over the fog deck',
    );
  });
}

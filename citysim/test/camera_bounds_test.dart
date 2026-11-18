/// Camera bounding tests: panning cannot escape the charted map.
///
/// The camera centre is clamped to the charted parcels' bounding box
/// plus a fog margin, so the map can never be panned out of view.
/// These tests drag the camera far past every clamp, then tap the
/// screen centre and check the reported cell: the world point under
/// the viewport centre must sit exactly on the clamp.
///
/// Expected clamps for the frozen content's charted block (parcels
/// columns -3..6, rows -1..2, 8×8 cells each): the block spans world
/// x in [-1536, 2048] and y in [-528, 1264], so with the 256-px
/// margin the centre may travel x in [-1792, 2304] and y in
/// [-784, 1520]. The fixed camera starts centred on cell (4, 4) =
/// world (0, 128).
library;

import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/rendering/parcel_world_view.dart';
import 'package:citysim/storage/sheet_tables.dart';
import 'package:citysim/storage/world_sheet_codec.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:citysim/world/terrain_provider.dart';
import 'package:citysim/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'frozen_content.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ContentBundle content;
  late ContentTerrainProvider terrain;

  setUpAll(() {
    content = frozenContent();
    terrain = ContentTerrainProvider(content.terrain);
  });

  ParcelWorldState anchorWorld() => sheetTablesToWorld(
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
    terrainProvider: terrain,
  );

  testWidgets('panning clamps at the charted map plus fog margin', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final taps = <CellCoord>[];
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: ParcelWorldView(
            state: anchorWorld(),
            content: content,
            terrainProvider: terrain,
            onCellTap: (cell, structureId, subtileX, subtileY) =>
                taps.add(cell),
          ),
        ),
      ),
    );
    // The gesture layer only exists once the artwork has loaded,
    // which needs real-async windows alongside the pumps.
    for (var attempt = 0; attempt < 10; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      if (find.byType(CustomPaint).evaluate().isNotEmpty) break;
    }
    expect(
      find.byType(CustomPaint),
      findsWidgets,
      reason: 'the map (and its gesture layer) should be mounted',
    );

    final center = tester.getRect(find.byType(ParcelWorldView)).center;

    // Drag far LEFT — the camera pushes east and must stop at the
    // charted block's right edge plus margin: world x = 2304, which
    // is cell-diagonal (column - row) = 72. Without the clamp the
    // 6000-px drag would land around 188.
    var drag = await tester.startGesture(center);
    for (var i = 0; i < 60; i++) {
      await drag.moveBy(const Offset(-100, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await drag.up();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(center);
    await tester.pump();
    var cell = taps.single;
    expect(
      cell.column - cell.row,
      72,
      reason: 'east clamp: charted right edge (2048) + 256 margin',
    );
    expect(cell.column + cell.row, 8, reason: 'no vertical drift');
    taps.clear();

    // Drag far RIGHT — the mirror clamp at world x = -1792.
    drag = await tester.startGesture(center);
    for (var i = 0; i < 80; i++) {
      await drag.moveBy(const Offset(100, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await drag.up();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(center);
    await tester.pump();
    cell = taps.single;
    expect(
      cell.column - cell.row,
      -56,
      reason: 'west clamp: charted left edge (-1536) - 256 margin',
    );
    expect(cell.column + cell.row, 8, reason: 'no vertical drift');
    taps.clear();

    // Drag far UP — the camera pushes south and must stop at the
    // charted block's bottom edge plus margin: world y = 1520, which
    // is cell-diagonal (column + row) = 95, rounding to the nearest
    // cell at 96.
    drag = await tester.startGesture(center);
    for (var i = 0; i < 30; i++) {
      await drag.moveBy(const Offset(0, -100));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await drag.up();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(center);
    await tester.pump();
    cell = taps.single;
    expect(
      cell.column + cell.row,
      96,
      reason: 'south clamp: charted bottom edge (1264) + 256 margin',
    );
    expect(cell.column - cell.row, -56, reason: 'no horizontal drift');
  });
}

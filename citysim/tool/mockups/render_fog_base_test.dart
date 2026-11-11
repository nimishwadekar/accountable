// One-off mockup harness, not part of the suite: renders the live
// save (assets/test_sheets) through the real renderer at a wide
// camera and writes fog_mockup_base.png next to the package, as the
// base image for fog previews composited outside Flutter.
//
// Run: flutter test tool/mockups/render_fog_base_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:citysim/content/asset_content_source.dart';
import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/rendering/parcel_world_view.dart';
import 'package:citysim/storage/sheet_tables.dart';
import 'package:citysim/storage/world_sheet_codec.dart';
import 'package:citysim/world/terrain_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ContentBundle content;
  late ContentTerrainProvider terrain;

  setUpAll(() async {
    content = await loadContentBundle(const AssetContentSource());
    terrain = ContentTerrainProvider(content.terrain);
  });

  testWidgets('renders the live save to fog_mockup_base.png', (tester) async {
    // Wide enough to frame the whole authored 7x7 parcel block plus
    // the uncharted fog ring around it at the camera's fixed scale 1.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(3900, 2400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String sheet(String name) =>
        File('assets/test_sheets/$name.csv').readAsStringSync();
    final world = sheetTablesToWorld(
      decodeSheetTables(
        userData: sheet('UserData'),
        tiles: sheet('Tiles'),
        props: sheet('Props'),
        ownedParcels: sheet('OwnedParcels'),
        projects: sheet('Projects'),
      ),
      content: content,
      terrainProvider: terrain,
    );

    final boundaryKey = GlobalKey();
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
              onCellTap: (cell, structureId, subtileX, subtileY) {},
              showTileGrid: false,
            ),
          ),
        ),
      ),
    );

    // Same settling the picking tests use: let every sprite decode
    // and the chunk cache rasterize before capturing.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1000)),
    );
    await tester.pump();

    final image = (await tester.runAsync(() async {
      final boundary =
          tester.renderObject(find.byKey(boundaryKey)) as RenderRepaintBoundary;
      return boundary.toImage(pixelRatio: 1);
    }))!;
    final png = (await tester.runAsync<ByteData?>(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    ))!;
    File('fog_mockup_base.png').writeAsBytesSync(png.buffer.asUint8List());
  });
}

// City snapshot renderer for playtest saves.
//
// Not part of the default suite (plain `flutter test` scans only
// test/): this harness deliberately reads the reviewers' live save
// files and the frozen playtest content snapshot, renders each city
// through the production ParcelWorldView at the game's resting zoom,
// and writes a PNG per reviewer.
//
// Run: flutter test tool/render/city_snapshots_test.dart
// Output: docs/sim/renders/<reviewer>-day<day>.png

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/rendering/parcel_world_view.dart';
import 'package:citysim/storage/sheet_tables.dart';
import 'package:citysim/storage/world_sheet_codec.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:citysim/world/terrain_provider.dart';
import 'package:citysim/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../sim/content_variants.dart';

const _snapshotDir = 'docs/sim/playtests/content-snapshot';
const _stateDir = 'docs/sim/playtests';
const _outputDir = 'docs/sim/renders';

Map<String, Object?> _read(Directory dir, String name) =>
    decodeJsonObject(File('${dir.path}/$name').readAsStringSync());

ContentBundle _loadContent() {
  final dir = Directory(_snapshotDir);
  return ladderABundle(
    parseContentBundle(
      manifest: _read(dir, 'manifest.json'),
      catalogue: _read(dir, 'catalogue.json'),
      sprites: _read(dir, 'sprites.json'),
      economy: _read(dir, 'economy.json'),
      ambience: _read(dir, 'ambience.json'),
      terrain: _read(dir, 'terrain.json'),
      progression: _read(dir, 'progression.json'),
    ),
  );
}

SheetTables _tablesFromJson(Object? value) {
  final map = (value as Map).cast<String, Object?>();
  List<List<String>> rows(Object? key) => [
    for (final row in map[key] as List)
      [for (final cell in row as List) cell as String],
  ];
  return SheetTables(
    userData: (map['userData'] as Map).cast<String, String>(),
    tiles: rows('tiles'),
    props: rows('props'),
    ownedParcels: rows('ownedParcels'),
    projects: rows('projects'),
  );
}

/// Frames the whole owned area: viewport size around the isometric
/// bounding box of every owned parcel, plus margins for building
/// height (the top) and breathing room.
({double width, double height, CellCoord focus}) _frame(
  ParcelWorldState state,
) {
  final ps = state.parcelSize;
  var minX = double.infinity;
  var maxX = -double.infinity;
  var minY = double.infinity;
  var maxY = -double.infinity;
  var centreColumn = 0.0;
  var centreRow = 0.0;
  for (final parcel in state.parcels) {
    final left = parcel.coord.x * ps;
    final top = parcel.coord.y * ps;
    final right = left + ps - 1;
    final bottom = top + ps - 1;
    for (final (column, row) in [
      (left, top),
      (right, top),
      (left, bottom),
      (right, bottom),
    ]) {
      final x = (column - row) * 32.0;
      final y = (column + row) * 16.0;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    centreColumn += left + (ps - 1) / 2;
    centreRow += top + (ps - 1) / 2;
  }
  final count = state.parcels.length;
  centreColumn /= count;
  centreRow /= count;
  const marginX = 340.0;
  const marginTop = 460.0;
  const marginBottom = 240.0;
  return (
    width: (maxX - minX) + marginX * 2,
    height: (maxY - minY) + marginTop + marginBottom,
    focus: CellCoord(centreColumn.round(), centreRow.round()),
  );
}

void _serveAssetsFromDisk() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMessageHandler('flutter/assets', (message) async {
    final key = utf8.decode(message!.buffer.asUint8List());
    final file = File(key);
    if (!file.existsSync()) return null;
    return ByteData.sublistView(file.readAsBytesSync());
  });
}

void main() {
  for (final name in const ['maya', 'leo', 'sam', 'vera']) {
    testWidgets(
      'render $name',
      timeout: const Timeout(Duration(minutes: 3)),
      (tester) async {
        _serveAssetsFromDisk();
        final content = _loadContent();
        final terrain = ContentTerrainProvider(content.terrain);
        final envelope = decodeJsonObject(
          File('$_stateDir/$name/state.json').readAsStringSync(),
        );
        final state = sheetTablesToWorld(
          _tablesFromJson(envelope['tables']),
          content: content,
          terrainProvider: terrain,
        );
        final day = envelope['day'];
        final frame = _frame(state);
        final size = Size(frame.width, frame.height);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final capture = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: RepaintBoundary(
              key: capture,
              child: ParcelWorldView(
                state: state,
                content: content,
                terrainProvider: terrain,
                cameraFocusCell: frame.focus,
                onCellTap: (_, __, ___, ____) {},
              ),
            ),
          ),
        );

        // Sprites decode asynchronously through the real event loop.
        // Wait for the ground wave (the canvas mounts), then give the
        // late waves — roads, actors, shore bands — time to land.
        var mounted = false;
        for (var i = 0; i < 240 && !mounted; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 150)),
          );
          await tester.pump(const Duration(milliseconds: 16));
          mounted = find.byType(CircularProgressIndicator).evaluate().isEmpty;
        }
        expect(mounted, isTrue, reason: 'city art did not finish loading');
        for (var i = 0; i < 12; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 200)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pump();

        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(capture),
        );
        final image = await tester.runAsync(
          () => boundary.toImage(pixelRatio: 1.0),
        );
        final bytes = await tester.runAsync(
          () => image!.toByteData(format: ui.ImageByteFormat.png),
        );
        Directory(_outputDir).createSync(recursive: true);
        final out = File('$_outputDir/$name-day$day.png')
          ..writeAsBytesSync(bytes!.buffer.asUint8List());
        // ignore: avoid_print
        print('rendered ${out.path} (${image!.width}x${image.height})');
        expect(image.width, greaterThan(100));
      },
    );
  }
}

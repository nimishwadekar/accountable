import 'dart:math' as math;

import 'package:citysim/editor/pages/map_page.dart';
import 'package:citysim/storage/world_usage.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _categoriesWith(
  Map<String, String> parcels, {
  List<Map<String, Object?>>? props,
}) => {
  // Typed like decoded JSON — dynamic values — so edits can add new
  // keys (the tile layer) the way the real content pipeline does.
  'terrain.json': <String, Object?>{'parcels': parcels, 'props': ?props},
  // A minimal catalogue + sprite set for the nature brush: two
  // brushable decorations (legalTerrain) and one that is not.
  'catalogue.json': <String, Object?>{
    'models': [
      {
        'id': 'pine-tree',
        'name': 'Pine Tree',
        'kind': 'decoration',
        'assetRoles': ['pine-a', 'pine-b'],
        'legalTerrain': ['land'],
      },
      {
        'id': 'rocks',
        'name': 'Rocks',
        'kind': 'decoration',
        'assetRoles': ['rocks-a'],
        'legalTerrain': ['land'],
      },
      {
        'id': 'street-lamp',
        'name': 'Street Lamp',
        'kind': 'decoration',
        'assetRoles': ['lamp'],
      },
    ],
  },
  'sprites.json': <String, Object?>{
    'pine-a': {'path': 'sprites/props/trees/pine-a.png'},
    'pine-b': {'path': 'sprites/props/trees/pine-b.png'},
    'rocks-a': {'path': 'sprites/props/rocks/rocks-a.png'},
    'lamp': {'path': 'sprites/props/streetside/lamp.png'},
  },
};

Widget _host(Map<String, Object?> categories, WorldUsage? usage) => MaterialApp(
  home: Scaffold(
    body: MapPage(
      categories: categories,
      onChanged: (edit) => edit(categories),
      usageLoader: () async => usage,
    ),
  ),
);

void main() {
  testWidgets('renders parcels with kind colors and labels', (tester) async {
    await tester.pumpWidget(
      _host(_categoriesWith({'0,0': 'grass', '1,0': 'water'}), null),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('parcel-0-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('parcel-1-0')), findsOneWidget);
    expect(find.textContaining('No world save loaded'), findsOneWidget);
  });

  testWidgets('+ buttons add same-kind neighbours in void directions', (
    tester,
  ) async {
    final categories = _categoriesWith({'0,0': 'grass', '1,0': 'water'});
    await tester.pumpWidget(_host(categories, null));
    await tester.pump();

    // East of the water parcel is void: + adds water at (2,0).
    await tester.tap(find.byKey(const ValueKey('add-1-0-1-0')));
    await tester.pump();
    expect(
      (categories['terrain.json'] as Map)['parcels'],
      containsPair('2,0', 'water'),
    );

    // South of the starter parcel is void: + adds grass at (0,1).
    await tester.tap(find.byKey(const ValueKey('add-0-0-0-1')));
    await tester.pump();
    expect(
      (categories['terrain.json'] as Map)['parcels'],
      containsPair('0,1', 'grass'),
    );

    // East of the starter parcel is taken: no + button there.
    expect(find.byKey(const ValueKey('add-0-0-1-0')), findsNothing);
  });

  testWidgets('occupied and owned parcels lock with reasons', (tester) async {
    final usage = WorldUsage(
      // A road tile inside the east water parcel (1,0).
      occupiedCells: {const CellCoord(10, 4)},
      ownedParcels: {const ParcelCoord(-1, 0)},
    );
    final categories = _categoriesWith({
      '0,0': 'grass',
      '1,0': 'water',
      '-1,0': 'grass',
    });
    await tester.pumpWidget(_host(categories, usage));
    await tester.pump();

    // There is no starter parcel anymore: (0,0) is just another
    // vacant parcel, free to re-type or delete.
    await tester.tap(find.byKey(const ValueKey('parcel-0-0')));
    await tester.pump();
    expect(find.textContaining('Vacant — free to change'), findsOneWidget);

    // Occupied: kind and delete both locked.
    await tester.tap(find.byKey(const ValueKey('parcel-1-0')));
    await tester.pump();
    expect(find.textContaining('occupied cells'), findsOneWidget);

    // Owned but vacant: delete locked, re-typing allowed.
    await tester.tap(find.byKey(const ValueKey('parcel--1-0')));
    await tester.pump();
    expect(
      find.textContaining('cannot be deleted, only re-typed'),
      findsOneWidget,
    );
  });

  testWidgets('selecting a vacant parcel allows kind change and delete', (
    tester,
  ) async {
    final categories = _categoriesWith({'0,0': 'grass', '2,0': 'grass'});
    await tester.pumpWidget(_host(categories, null));
    await tester.pump();

    // Re-type the vacant far parcel.
    await tester.tap(find.byKey(const ValueKey('parcel-2-0')));
    await tester.pump();
    await tester.tap(find.text('water'));
    await tester.pump();
    expect((categories['terrain.json'] as Map)['parcels']['2,0'], 'water');

    // Delete it.
    await tester.tap(find.text('Delete parcel'));
    await tester.pump();
    expect(
      (categories['terrain.json'] as Map)['parcels'],
      isNot(contains('2,0')),
    );
    expect(find.textContaining('Select a parcel'), findsOneWidget);
  });

  testWidgets('tile brush paints cells, locks occupied ones, erases to base', (
    tester,
  ) async {
    // A tall surface keeps the canvas clear of the selection panel
    // below it, so parcel taps land on the map.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    addTearDown(tester.view.reset);
    addTearDown(tester.view.resetDevicePixelRatio);
    final categories = _categoriesWith({'0,0': 'grass'});
    await tester.pumpWidget(
      _host(
        categories,
        WorldUsage(
          occupiedCells: {const CellCoord(4, 4)},
          ownedParcels: const {},
        ),
      ),
    );
    await tester.pump();

    // Switch to the tile brush; water is the default brush.
    await tester.tap(find.text('Paint tiles'));
    await tester.pump();

    // Cell centres within the sole parcel's 256×128 diamond, whose
    // render box the page lays out with its own padding.
    final parcel = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('parcel-0-0')),
    );
    Offset cellCentre(int cx, int cy) => parcel.localToGlobal(
      Offset(128 + (cx - cy) * 16, 64 + (cx + cy - 7) * 8),
    );

    // Painting a free cell writes a water override.
    await tester.tapAt(cellCentre(3, 4));
    await tester.pump();
    expect(
      (categories['terrain.json'] as Map)['tiles'],
      containsPair('3,4', 'water'),
    );

    // A drag sweeps the cells it crosses.
    final gesture = await tester.startGesture(cellCentre(1, 1));
    await gesture.moveBy(const Offset(16, 8)); // onto cell (2,1)
    await gesture.up();
    await tester.pump();
    expect(
      (categories['terrain.json'] as Map)['tiles'],
      containsPair('2,1', 'water'),
    );

    // A paint drag never pans the map — the brush owns the drag.
    final before = tester
        .renderObject<RenderBox>(find.byKey(const ValueKey('parcel-0-0')))
        .localToGlobal(Offset.zero);
    final sweep = await tester.startGesture(cellCentre(2, 3));
    await sweep.moveBy(const Offset(32, 16));
    await sweep.moveBy(const Offset(32, 16));
    await sweep.up();
    await tester.pump();
    expect(
      tester
          .renderObject<RenderBox>(find.byKey(const ValueKey('parcel-0-0')))
          .localToGlobal(Offset.zero),
      before,
      reason: 'painting must not move the camera',
    );

    // Occupied cells refuse paint and surface why.
    await tester.tapAt(cellCentre(4, 4));
    await tester.pump();
    expect(
      (categories['terrain.json'] as Map)['tiles'],
      isNot(contains('4,4')),
    );
    expect(find.textContaining('Skipped locked cells'), findsOneWidget);

    // Painting a cell back to its parcel's kind erases the override
    // rather than writing a redundant entry.
    await tester.tap(find.text('grass'));
    await tester.pump();
    await tester.tapAt(cellCentre(3, 4));
    await tester.pump();
    expect(
      (categories['terrain.json'] as Map)['tiles'],
      isNot(contains('3,4')),
    );

    // The eraser restores the base the same way.
    await tester.tap(find.text('water'));
    await tester.pump();
    await tester.tapAt(cellCentre(5, 5));
    await tester.pump();
    expect(
      (categories['terrain.json'] as Map)['tiles'],
      containsPair('5,5', 'water'),
    );
    await tester.tap(
      find.byTooltip(
        'Eraser — or right-click while painting. Click again to paint',
      ),
    );
    await tester.pump();
    await tester.tapAt(cellCentre(5, 5));
    await tester.pump();
    expect(
      (categories['terrain.json'] as Map)['tiles'],
      isNot(contains('5,5')),
    );

    // A right-click stroke erases too, and undo walks back strokes.
    await tester.tap(find.text('water'));
    await tester.pump();
    await tester.tapAt(cellCentre(6, 6));
    await tester.pump();
    expect(
      (categories['terrain.json'] as Map)['tiles'],
      containsPair('6,6', 'water'),
    );
    final erase = await tester.startGesture(
      cellCentre(6, 6),
      buttons: kSecondaryButton,
    );
    await erase.up();
    await tester.pump();
    expect(
      (categories['terrain.json'] as Map)['tiles'],
      isNot(contains('6,6')),
    );

    // Undo restores each stroke's starting state, one at a time.
    await tester.tap(find.byTooltip('Undo (Ctrl+Z)'));
    await tester.pump();
    expect(
      (categories['terrain.json'] as Map)['tiles'],
      containsPair('6,6', 'water'),
      reason: 'the right-click erase stroke is undone',
    );
    await tester.tap(find.byTooltip('Undo (Ctrl+Z)'));
    await tester.pump();
    expect(
      (categories['terrain.json'] as Map)['tiles'],
      isNot(contains('6,6')),
    );
    expect(
      (categories['terrain.json'] as Map)['tiles'],
      containsPair('2,1', 'water'),
      reason: 'only the last stroke is undone at a time',
    );
  });

  test('nature brush draws distinct subtiles in the disk, then filters', () {
    // Everything legal: the draw caps at N and never repeats.
    final all = sampleNatureBrush(
      centerCol: 4.5,
      centerRow: 4.5,
      radiusCells: 1,
      count: 3,
      legal: (cell, subtileX, subtileY) => true,
      random: math.Random(5),
    );
    expect(all.length, 3);
    expect(all.toSet().length, 3, reason: 'draws are without replacement');
    // Every anchor's subtile centre lies inside the disk.
    for (final (cell, subtileX, subtileY) in all) {
      final col = cell.column + (subtileX + 0.5) / 8;
      final row = cell.row + (subtileY + 0.5) / 8;
      expect(
        math.sqrt((col - 4.5) * (col - 4.5) + (row - 4.5) * (row - 4.5)),
        lessThanOrEqualTo(1),
      );
    }
    // Nothing legal: the click places nothing — N is an upper bound.
    expect(
      sampleNatureBrush(
        centerCol: 4.5,
        centerRow: 4.5,
        radiusCells: 1,
        count: 5,
        legal: (cell, subtileX, subtileY) => false,
        random: math.Random(5),
      ),
      isEmpty,
    );
    // A draw larger than the pool exhausts it: every subtile in the
    // disk comes back exactly once.
    final pool = sampleNatureBrush(
      centerCol: 4.5,
      centerRow: 4.5,
      radiusCells: 0.5,
      count: 1000,
      legal: (cell, subtileX, subtileY) => true,
      random: math.Random(9),
    );
    expect(pool.toSet().length, pool.length);
    expect(pool.length, lessThan(64), reason: 'a half-cell disk is small');
    // The same seed draws the same sample.
    expect(
      sampleNatureBrush(
        centerCol: 10.5,
        centerRow: 3.5,
        radiusCells: 2,
        count: 8,
        legal: (cell, subtileX, subtileY) => true,
        random: math.Random(4),
      ),
      sampleNatureBrush(
        centerCol: 10.5,
        centerRow: 3.5,
        radiusCells: 2,
        count: 8,
        legal: (cell, subtileX, subtileY) => true,
        random: math.Random(4),
      ),
    );
  });

  testWidgets('nature brush sprinkles rows onto legal cells only', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    addTearDown(tester.view.reset);
    addTearDown(tester.view.resetDevicePixelRatio);
    // The starter parcel is grass; the east parcel is water and owned
    // — the brush must refuse both — and one starter cell is occupied.
    final categories = _categoriesWith({'0,0': 'grass', '1,0': 'water'});
    await tester.pumpWidget(
      _host(
        categories,
        WorldUsage(
          occupiedCells: {const CellCoord(6, 4)},
          ownedParcels: {const ParcelCoord(1, 0)},
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Nature'));
    await tester.pump();
    // The picker defaults to the first brushable item — the pine
    // tree, not the lamp (no legalTerrain).
    expect(find.text('Pine Tree'), findsOneWidget);

    final parcel = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('parcel-0-0')),
    );
    Offset cellCentre(int cx, int cy) => parcel.localToGlobal(
      Offset(128 + (cx - cy) * 16, 64 + (cx + cy - 7) * 8),
    );

    // Click near the parcel's east edge: the disk overlaps the water
    // and owned parcel, but rows only land on free starter-land.
    await tester.tapAt(cellCentre(7, 4));
    await tester.pump();
    final rows = ((categories['terrain.json'] as Map)['props'] as List)
        .cast<Map>();
    expect(rows, isNotEmpty);
    expect(rows.length, lessThanOrEqualTo(8));
    final anchors = <String>{};
    for (final row in rows) {
      expect(row['catalogueId'], 'pine-tree');
      expect(row['assetRole'], anyOf('pine-a', 'pine-b'));
      final x = row['x'] as int;
      final y = row['y'] as int;
      expect(x, inInclusiveRange(0, 7), reason: 'never off the grass parcel');
      expect(y, inInclusiveRange(0, 7));
      expect(
        anchors.add('$x,$y:${row['subtileX']}.${row['subtileY']}'),
        isTrue,
        reason: 'one row per subtile',
      );
    }

    // Right-click clears a tile that carries rows — pick one from
    // what the click placed (the draw is random, so the clicked
    // cell itself may have stayed empty).
    final placed = ((categories['terrain.json'] as Map)['props'] as List)
        .cast<Map>();
    final target = placed.first;
    final tx = target['x'] as int;
    final ty = target['y'] as int;
    await tester.tapAt(cellCentre(tx, ty), buttons: kSecondaryButton);
    await tester.pump();
    expect(
      ((categories['terrain.json'] as Map)['props'] as List? ?? const [])
          .cast<Map>()
          .where((row) => row['x'] == tx && row['y'] == ty),
      isEmpty,
    );

    // Undo walks the click back — the props section goes sparse-free.
    await tester.tap(find.byTooltip('Undo (Ctrl+Z)'));
    await tester.pump();
    expect(
      ((categories['terrain.json'] as Map)['props'] as List)
          .where((row) => row['x'] == tx && row['y'] == ty)
          .length,
      greaterThan(0),
      reason: 'the clear is undone, leaving the click\'s rows',
    );
    await tester.tap(find.byTooltip('Undo (Ctrl+Z)'));
    await tester.pump();
    expect((categories['terrain.json'] as Map).containsKey('props'), isFalse);
  });

  testWidgets('tile paint and parcel edits refuse cells with nature', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    addTearDown(tester.view.reset);
    addTearDown(tester.view.resetDevicePixelRatio);
    final categories = _categoriesWith(
      {'0,0': 'grass', '1,0': 'grass'},
      props: [
        {
          'catalogueId': 'pine-tree',
          'x': 3,
          'y': 3,
          'subtileX': 2,
          'subtileY': 2,
          'assetRole': 'pine-a',
        },
        {
          'catalogueId': 'pine-tree',
          'x': 12,
          'y': 3,
          'subtileX': 4,
          'subtileY': 4,
          'assetRole': 'pine-b',
        },
      ],
    );
    await tester.pumpWidget(_host(categories, null));
    await tester.pump();

    final parcel = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('parcel-0-0')),
    );
    Offset cellCentre(int cx, int cy) => parcel.localToGlobal(
      Offset(128 + (cx - cy) * 16, 64 + (cx + cy - 7) * 8),
    );

    // The tile brush refuses the propped cell.
    await tester.tap(find.text('Paint tiles'));
    await tester.pump();
    await tester.tapAt(cellCentre(3, 3));
    await tester.pump();
    expect((categories['terrain.json'] as Map).containsKey('tiles'), isFalse);
    expect(find.textContaining('Skipped propped cells'), findsOneWidget);

    // The parcel inspector locks re-typing and deleting while rows
    // remain, and the clear button empties the parcel in one step.
    // The far parcel carries the other row — the starter's lock
    // reason would shadow the nature one.
    await tester.tap(find.text('Select'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('parcel-1-0')));
    await tester.pump();
    expect(find.textContaining('carries 1 nature prop'), findsOneWidget);
    await tester.tap(find.text('Clear 1 nature prop(s)'));
    await tester.pump();
    expect(
      ((categories['terrain.json'] as Map)['props'] as List).where(
        (row) => row['x'] == 12 && row['y'] == 3,
      ),
      isEmpty,
    );
  });

  testWidgets('painting works after the parcel clear button', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    addTearDown(tester.view.reset);
    addTearDown(tester.view.resetDevicePixelRatio);
    final categories = _categoriesWith(
      {'0,0': 'grass', '1,0': 'grass'},
      props: [
        {
          'catalogueId': 'pine-tree',
          'x': 12,
          'y': 3,
          'subtileX': 4,
          'subtileY': 4,
          'assetRole': 'pine-b',
        },
      ],
    );
    await tester.pumpWidget(_host(categories, null));
    await tester.pump();

    final parcel = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('parcel-0-0')),
    );
    Offset cellCentre(int cx, int cy) => parcel.localToGlobal(
      Offset(128 + (cx - cy) * 16, 64 + (cx + cy - 7) * 8),
    );

    // Select the far parcel and clear its nature via the button.
    await tester.tap(find.byKey(const ValueKey('parcel-1-0')));
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'after selecting');
    await tester.tap(find.text('Clear 1 nature prop(s)'));
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'after clearing');
    expect(
      (categories['terrain.json'] as Map).containsKey('props'),
      isFalse,
      reason: 'the last row takes the props section with it',
    );

    // The nature brush still sprinkles after the clear.
    await tester.tap(find.text('Nature'));
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'after switching tools');
    await tester.tapAt(cellCentre(3, 3));
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'after sprinkling');
    expect(
      ((categories['terrain.json'] as Map)['props'] as List).cast<Map>(),
      isNotEmpty,
    );

    // And the tile brush still paints — on a cell outside the
    // sprinkle's disk, since propped cells rightly refuse tiles.
    await tester.tap(find.text('Paint tiles'));
    await tester.pump();
    await tester.tapAt(cellCentre(6, 6));
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'after tile painting');
    expect(
      (categories['terrain.json'] as Map)['tiles'],
      containsPair('6,6', 'water'),
    );
  });

  testWidgets('nature eraser toggles and erases only the selected item', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    addTearDown(tester.view.reset);
    addTearDown(tester.view.resetDevicePixelRatio);
    final categories = _categoriesWith(
      {'0,0': 'grass'},
      props: [
        {
          'catalogueId': 'pine-tree',
          'x': 4,
          'y': 4,
          'subtileX': 2,
          'subtileY': 2,
          'assetRole': 'pine-a',
        },
        {
          'catalogueId': 'pine-tree',
          'x': 5,
          'y': 5,
          'subtileX': 1,
          'subtileY': 1,
          'assetRole': 'pine-b',
        },
        {
          'catalogueId': 'rocks',
          'x': 4,
          'y': 4,
          'subtileX': 6,
          'subtileY': 6,
          'assetRole': 'rocks-a',
        },
      ],
    );
    await tester.pumpWidget(_host(categories, null));
    await tester.pump();

    await tester.tap(find.text('Nature'));
    await tester.pump();
    expect(find.text('Pine Tree'), findsOneWidget, reason: 'pine is default');

    final parcel = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('parcel-0-0')),
    );
    Offset cellCentre(int cx, int cy) => parcel.localToGlobal(
      Offset(128 + (cx - cy) * 16, 64 + (cx + cy - 7) * 8),
    );

    // Toggle the eraser on and click: the pines inside the circle go
    // — both the clicked cell's and the neighbour's — while the
    // rocks on the very same subtile grid survive.
    await tester.tap(
      find.byTooltip('Erase the selected item in the circle — or right-click'),
    );
    await tester.pump();
    await tester.tapAt(cellCentre(4, 4));
    await tester.pump();
    final afterErase = ((categories['terrain.json'] as Map)['props'] as List)
        .cast<Map>();
    expect(
      afterErase.where((row) => row['catalogueId'] == 'pine-tree'),
      isEmpty,
    );
    expect(
      afterErase.where((row) => row['catalogueId'] == 'rocks'),
      hasLength(1),
      reason: 'other items survive the eraser',
    );

    // The button is still live — toggling back places again.
    await tester.tap(find.byTooltip('Erasing — click again to place'));
    await tester.pump();
    await tester.tapAt(cellCentre(5, 5));
    await tester.pump();
    expect(
      ((categories['terrain.json'] as Map)['props'] as List).cast<Map>().where(
        (row) => row['catalogueId'] == 'pine-tree',
      ),
      isNotEmpty,
      reason: 'placing works again after toggling the eraser off',
    );
  });

  testWidgets('holding the nature brush repeats placement until release', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    addTearDown(tester.view.reset);
    addTearDown(tester.view.resetDevicePixelRatio);
    final categories = _categoriesWith({'0,0': 'grass'});
    await tester.pumpWidget(_host(categories, null));
    await tester.pump();
    await tester.tap(find.text('Nature'));
    await tester.pump();

    final parcel = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('parcel-0-0')),
    );
    Offset cellCentre(int cx, int cy) => parcel.localToGlobal(
      Offset(128 + (cx - cy) * 16, 64 + (cx + cy - 7) * 8),
    );
    int rowCount() =>
        ((categories['terrain.json'] as Map)['props'] as List? ?? const [])
            .length;

    // Press and hold: the press places N rows, then the hold loop
    // places again every quarter second at the cell under the
    // pointer.
    final gesture = await tester.startGesture(cellCentre(4, 4));
    await tester.pump();
    final first = rowCount();
    expect(first, 8, reason: 'the press places N rows at once');
    await tester.pump(const Duration(milliseconds: 300));
    final second = rowCount();
    expect(second, greaterThan(first), reason: 'the hold loop placed again');
    await tester.pump(const Duration(milliseconds: 300));
    expect(rowCount(), greaterThan(second), reason: 'and again');

    // Releasing stops the loop cold.
    await gesture.up();
    await tester.pump();
    final released = rowCount();
    await tester.pump(const Duration(milliseconds: 600));
    expect(rowCount(), released, reason: 'the loop stops on release');
  });
}

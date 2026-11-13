import 'package:citysim/editor/pages/map_page.dart';
import 'package:citysim/storage/world_usage.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _categoriesWith(Map<String, String> parcels) => {
  // Typed like decoded JSON — dynamic values — so edits can add new
  // keys (the tile layer) the way the real content pipeline does.
  'terrain.json': <String, Object?>{'parcels': parcels},
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

  testWidgets('occupied, owned, and starter parcels lock with reasons', (
    tester,
  ) async {
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

    // The starter parcel is locked both ways.
    await tester.tap(find.byKey(const ValueKey('parcel-0-0')));
    await tester.pump();
    expect(
      find.textContaining('starter parcel must stay grass'),
      findsOneWidget,
    );

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
    await tester.tap(find.byTooltip('Eraser — or right-click while painting'));
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
}

import 'package:citysim/editor/pages/map_page.dart';
import 'package:citysim/storage/world_usage.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _categoriesWith(Map<String, String> parcels) => {
  'terrain.json': {'parcels': parcels},
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
    await tester.tap(find.text('grass').last);
    await tester.pump();
    await tester.tap(find.text('water').last);
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
}

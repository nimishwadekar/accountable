import 'package:citysim/parcel_city_app.dart';
import 'package:citysim/rendering/parcel_world_view.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:citysim/world/world_state.dart';
import 'package:citysim/world/world_save_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryParcelStore implements ParcelWorldStore {
  _MemoryParcelStore({this.legacy = false});

  ParcelWorldState? state;
  final bool legacy;

  @override
  Future<bool> hasLegacyV1Save() async => legacy;

  @override
  Future<ParcelWorldState?> load() async => state;

  @override
  Future<void> save(ParcelWorldState state) async => this.state = state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'parcel preview check-in and manual day controls render at mobile widths',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = _MemoryParcelStore();

      await tester.pumpWidget(ParcelCityApp(store: store));
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await tester.pump();
      expect(find.text('Check in · +1'), findsOneWidget);
      expect(find.text('1 parcel · 0 structures'), findsOneWidget);
      expect(find.text('Could not load the world artwork.'), findsNothing);
      expect(store.state?.roads.single.cell.column, 4);
      expect(store.state?.structures, isEmpty);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Check in · +1'));
      await tester.pump();
      expect(store.state?.coins, 1);

      await tester.tap(find.text('Roads').first);
      await tester.pump();
      final mapRect = tester.getRect(find.byType(ParcelWorldView));
      await tester.tapAt(mapRect.center + const Offset(32, 16));
      await tester.pump();
      expect(find.textContaining('1 road tiles'), findsOneWidget);
      final planButton = find.text('Assign builder · plan free');
      await tester.ensureVisible(planButton);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(planButton);
      await tester.pump();
      expect(store.state?.coins, 1, reason: 'planning the road costs no coins');
      expect(store.state?.constructions.single.roadCells, [
        const CellCoord(5, 4),
      ]);
      expect(store.state?.roads, hasLength(1));

      final updatedMapRect = tester.getRect(find.byType(ParcelWorldView));
      await tester.tapAt(updatedMapRect.center + const Offset(32, 16));
      await tester.pump();
      await tester.drag(find.byType(ListView).last, const Offset(0, 600));
      await tester.pump();
      final fundButton = find.text('Fund selected road tile · 1 coin');
      await tester.drag(find.byType(ListView).last, const Offset(0, -100));
      await tester.pump();
      await tester.ensureVisible(fundButton);
      await tester.tap(fundButton);
      await tester.pump();
      expect(store.state?.coins, 0);
      expect(
        store.state?.roads.any((road) => road.cell == const CellCoord(5, 4)),
        isTrue,
      );

      tester.view.physicalSize = const Size(320, 800);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('legacy V1 save requires an explicit new-world choice', (
    tester,
  ) async {
    final store = _MemoryParcelStore(legacy: true);
    await tester.pumpWidget(ParcelCityApp(store: store));
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('Start the parcel-world preview?'), findsOneWidget);
    expect(find.text('Start new parcel world'), findsOneWidget);
    expect(store.state, isNull);

    await tester.tap(find.text('Start new parcel world'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(store.state, isNotNull);
    expect(store.state!.parcels, hasLength(1));
    expect(store.state!.structures, isEmpty);
  });

  testWidgets(
    'catalogue tiles paint their selection splash above panel cards',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(ParcelCityApp(store: _MemoryParcelStore()));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();

      await tester.tap(find.text('Buildings').first);
      await tester.pump();
      final cottage = find.text('Sunny cottage');
      await tester.ensureVisible(cottage);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(cottage);
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );
}

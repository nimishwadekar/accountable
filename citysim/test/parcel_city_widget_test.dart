import 'package:citysim/content/asset_content_source.dart';
import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/parcel_city_app.dart';
import 'package:citysim/rendering/parcel_world_view.dart';
import 'package:citysim/storage/sheet_tables.dart';
import 'package:citysim/storage/world_sheet_codec.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:citysim/world/terrain_provider.dart';
import 'package:citysim/world/world_state.dart';
import 'package:citysim/world/world_save_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryParcelStore implements ParcelWorldStore {
  _MemoryParcelStore();

  ParcelWorldState? state;

  @override
  Future<ParcelWorldState?> load() async => state;

  @override
  Future<void> save(ParcelWorldState state) async => this.state = state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Asset loading inside fake-async tests is unreliable once a prior test
  // has run the app, so the content bundle is loaded once with real async
  // before any test starts and injected into the app under test.
  late ContentBundle content;
  setUpAll(() async {
    content = await loadContentBundle(const AssetContentSource());
  });

  testWidgets(
    'parcel preview check-in and manual day controls render at mobile widths',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = _MemoryParcelStore();

      await tester.pumpWidget(ParcelCityApp(store: store, content: content));
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

  testWidgets(
    'catalogue tiles paint their selection splash above panel cards',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ParcelCityApp(store: _MemoryParcelStore(), content: content),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();

      await tester.tap(find.text('Buildings').first);
      await tester.pump();
      // Model names are dashboard-editable content, so the tile is located
      // through the loaded bundle instead of a hardcoded display name.
      final cottageName = content.catalogue
          .firstWhere(
            (model) =>
                model.kind == StructureKind.building &&
                model.enabled &&
                model.unlockAtPopulation == 0,
          )
          .name;
      final cottage = find.text(cottageName);
      await tester.ensureVisible(cottage);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(cottage);
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a bridged world renders through the depth-sorted pass', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Starter road, a road east to the channel, a completed bridge over
    // the water parcel, and the far-bank road beyond it — so the sorted
    // pass carries bridge bodies and ramps alongside any structures.
    final terrain = ContentTerrainProvider(content.terrain);
    final world = sheetTablesToWorld(
      SheetTables(
        userData: const {
          'seed': '7',
          'coins': '10',
          'coins_earned': '10',
          'coins_spent': '0',
          'simulated_date': '2026-11-05',
          'high_water_date': '2026-11-05',
          'construction_day': '5',
        },
        ownedParcels: const [
          ['0', '0'],
          ['1', '0'],
          ['2', '0'],
        ],
        tiles: [
          ['4', '4', 'road', 'complete', 'dirt', '', '', ''],
          ['5', '4', 'road', 'complete', 'asphalt', '', '', ''],
          ['6', '4', 'road', 'complete', 'asphalt', '', '', ''],
          ['7', '4', 'road', 'complete', 'asphalt', '', '', ''],
          for (var column = 8; column <= 15; column++)
            ['$column', '4', 'bridge', 'complete', '', '', '', ''],
          ['16', '4', 'road', 'complete', 'asphalt', '', '', ''],
          [
            '17',
            '3',
            'structure',
            'complete',
            'large-home',
            'home-large-blue',
            'left',
            '',
          ],
        ],
        projects: const [],
      ),
      content: content,
      terrainProvider: terrain,
    );

    await tester.pumpWidget(
      ParcelCityApp(
        store: _MemoryParcelStore()..state = world,
        content: content,
      ),
    );
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.text('Could not load the world artwork.'), findsNothing);
  });
}

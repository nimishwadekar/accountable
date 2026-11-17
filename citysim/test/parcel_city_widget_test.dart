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

  /// A world one step into the game: parcel (0,0) founded (free) and
  /// optionally a first road tile at its centre — assembled directly
  /// through the save codec so no coins, days, or events are spent
  /// reaching it.
  ParcelWorldState foundedWorld({bool withRoad = true}) => sheetTablesToWorld(
    SheetTables(
      userData: {
        'seed': '7',
        'coins': '${content.economy.startingTreasuryCoins}',
        'coins_earned': '${content.economy.startingTreasuryCoins}',
        'coins_spent': '0',
        'simulated_date': '2026-11-02',
        'high_water_date': '2026-11-02',
        'construction_day': '0',
      },
      ownedParcels: const [
        ['0', '0'],
      ],
      tiles: withRoad
          ? const [
              ['4', '4', 'road', 'complete', 'asphalt', '', '', ''],
            ]
          : const [],
      projects: const [],
    ),
    content: content,
    terrainProvider: ContentTerrainProvider(content.terrain),
  );

  testWidgets(
    'founding, check-in, and manual day controls render at mobile widths',
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

      // A brand-new game owns nothing, builds nothing, and the hint
      // says where to begin.
      expect(find.text('0 parcels · 0 structures'), findsOneWidget);
      expect(
        find.text('Open the Parcel tool to claim your free founding parcel'),
        findsOneWidget,
      );
      expect(find.text('Could not load the world artwork.'), findsNothing);

      // Found: the parcel tool, a tap on the charted parcel under the
      // camera's centre, and the free claim.
      await tester.tap(find.text('Parcels').first);
      await tester.pump();
      expect(
        find.text(
          'Your first parcel is free — tap one with at least 5 land cells',
        ),
        findsOneWidget,
      );
      final mapRect = tester.getRect(find.byType(ParcelWorldView));
      await tester.tapAt(mapRect.center);
      await tester.pump();
      final review = find.text('Review parcel purchase');
      await tester.ensureVisible(review);
      await tester.pump();
      await tester.tap(review);
      await tester.pump();
      await tester.tap(find.text('Claim parcel'));
      await tester.pump();
      expect(find.text('1 parcel · 0 structures'), findsOneWidget);
      expect(store.state?.parcels.single.coord, const ParcelCoord(0, 0));
      expect(store.state?.parcels.single.pricePaid, 0);
      expect(store.state?.roads, isEmpty, reason: 'nothing is pre-built');
      expect(
        store.state?.coins,
        content.economy.startingTreasuryCoins,
        reason: 'the founding parcel is free',
      );

      // The check-in is the town report: a founded town with no
      // roads yet owes nothing, and no coin moves.
      await tester.tap(find.text('Check in · +0'));
      await tester.pump();
      expect(find.textContaining('Town report'), findsOneWidget);
      expect(find.textContaining('Upkeep paid'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(
        store.state?.coins,
        content.economy.startingTreasuryCoins,
        reason: 'an empty town nets zero',
      );

      // The founding claim scrolled the panel down; the tool chips
      // build lazily at its top, so scroll back up to reach them.
      final roadsTool = find.text('Roads');
      await tester.scrollUntilVisible(
        roadsTool,
        -200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pump();
      await tester.tap(roadsTool.first);
      await tester.pump();
      // Two-click planning: the first click sets the start tile, the
      // second sets the end tile projected onto the closer axis.
      await tester.tapAt(mapRect.center + const Offset(32, 16));
      await tester.pump();
      await tester.tapAt(mapRect.center + const Offset(64, 32));
      await tester.pump();
      expect(find.textContaining('2 road tiles'), findsOneWidget);
      final planButton = find.textContaining('Buy road plan');
      await tester.ensureVisible(planButton);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(planButton);
      await tester.pump();
      expect(
        store.state?.coins,
        content.economy.startingTreasuryCoins -
            2 * content.economy.roadTileCostCoins,
        reason: 'the whole stretch is paid upfront',
      );
      expect(store.state?.constructions.single.roadCells, [
        const CellCoord(5, 4),
        const CellCoord(6, 4),
      ]);
      expect(store.state?.roads, isEmpty, reason: 'nothing delivered yet');

      // Creep: a day passes, the check-in lays the first tile.
      final advanceButton = find.text('+1 day');
      await tester.scrollUntilVisible(
        advanceButton,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pump();
      await tester.tap(advanceButton);
      await tester.pump();
      await tester.tap(find.text('Check in current day'));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(
        store.state?.roads.any((road) => road.cell == const CellCoord(5, 4)),
        isTrue,
      );
      expect(
        store.state?.roads.where((road) => road.projectId == 'construction-1'),
        hasLength(1),
        reason: 'one tile delivered, one still creeping',
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
      // through the loaded bundle instead of a hardcoded display name —
      // the first building the from-start milestone unlocks.
      final cottageName = content.catalogue
          .firstWhere(
            (model) =>
                model.kind == StructureKind.building &&
                model.enabled &&
                content.progression.sorted.first.models.contains(model.id),
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

  testWidgets('parcel mode selects parcels, not cells', (tester) async {
    tester.view.devicePixelRatio = 1;
    // Wide enough that the unowned parcel south of the founding one
    // is tappable: the app caps the map view's width, so the phone
    // width cannot reach a parcel a full tile left of centre.
    tester.view.physicalSize = const Size(900, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _MemoryParcelStore()..state = foundedWorld(withRoad: false);

    await tester.pumpWidget(ParcelCityApp(store: store, content: content));
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    await tester.tap(find.text('Parcels').first);
    await tester.pump();
    final mapRect = tester.getRect(find.byType(ParcelWorldView));
    // The founding parcel is owned: tapping it highlights nothing.
    await tester.tapAt(mapRect.center + const Offset(16, 8));
    await tester.pump();

    var view = tester.widget<ParcelWorldView>(find.byType(ParcelWorldView));
    expect(view.parcelMode, isTrue);
    expect(view.selectedParcel, isNull, reason: 'owned parcels select nothing');
    expect(view.selectedCell, isNull);

    // The parcel south of the founding one is charted and unowned:
    // the tap selects that whole parcel, at parcel granularity only.
    // Its centre cell (4, 12) sits one parcel down-left of the
    // camera's start cell.
    await tester.tapAt(mapRect.center + const Offset(-256, 128));
    await tester.pump();

    view = tester.widget<ParcelWorldView>(find.byType(ParcelWorldView));
    expect(view.selectedParcel, const ParcelCoord(0, 1));
    expect(view.selectedCell, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inspect mode selects objects only, terrain clears', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _MemoryParcelStore()..state = foundedWorld();

    await tester.pumpWidget(ParcelCityApp(store: store, content: content));
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    // The default tool is inspect. The founded parcel's first road
    // runs through the camera's start cell (4, 4), at the map's
    // centre: tapping it selects the road section.
    final mapRect = tester.getRect(find.byType(ParcelWorldView));
    await tester.tapAt(mapRect.center);
    await tester.pump();
    var view = tester.widget<ParcelWorldView>(find.byType(ParcelWorldView));
    expect(view.selectedCell, const CellCoord(4, 4));
    expect(view.highlightCells, isNotEmpty, reason: 'the road section');

    // Plain grass next to the road (cell (2, 2), one tile up from
    // the centre) highlights nothing — the tap just clears.
    await tester.tapAt(mapRect.center + const Offset(0, -64));
    await tester.pump();
    view = tester.widget<ParcelWorldView>(find.byType(ParcelWorldView));
    expect(view.selectedCell, isNull, reason: 'terrain selects nothing');
    expect(view.highlightCells, isEmpty);
    expect(view.selectedParcel, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('parcel mode ignores fog parcels', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _MemoryParcelStore();
    // A two-parcel map: the owned starter and one charted neighbour,
    // fog beyond — every parcel-mode rule within a default camera.
    final tinyContent = ContentBundle(
      manifest: content.manifest,
      catalogue: content.catalogue,
      sprites: content.sprites,
      economy: content.economy,
      ambience: content.ambience,
      progression: content.progression,
      terrain: TerrainContent(
        generatorVersion: 1,
        parcels: {
          const ParcelCoord(0, 0): TerrainKind.grass,
          const ParcelCoord(0, 1): TerrainKind.grass,
        },
      ),
    );

    await tester.pumpWidget(ParcelCityApp(store: store, content: tinyContent));
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    await tester.tap(find.text('Parcels').first);
    await tester.pump();
    final mapRect = tester.getRect(find.byType(ParcelWorldView));
    ParcelWorldView view() =>
        tester.widget<ParcelWorldView>(find.byType(ParcelWorldView));

    // The charted neighbour (centre cell (4, 12)) selects.
    await tester.tapAt(mapRect.center + const Offset(-256, 128));
    await tester.pump();
    expect(view().selectedParcel, const ParcelCoord(0, 1));

    // The fog parcel west of the starter (centre cell (-1, 11))
    // selects nothing.
    await tester.tapAt(mapRect.center + const Offset(-384, 32));
    await tester.pump();
    expect(view().selectedParcel, isNull, reason: 'fog parcels select nothing');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the tile grid hides for inspect and shows for tools', (
    tester,
  ) async {
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

    ParcelWorldView view() =>
        tester.widget<ParcelWorldView>(find.byType(ParcelWorldView));
    // The default inspect tool renders the world clean...
    expect(view().showTileGrid, isFalse, reason: 'inspect hides the grid');
    // ...and every working tool shows it.
    await tester.tap(find.text('Roads').first);
    await tester.pump();
    expect(view().showTileGrid, isTrue, reason: 'the road tool shows the grid');
    expect(tester.takeException(), isNull);
  });

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
            'south',
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

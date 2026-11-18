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

/// The world-space centre of a cell, matching the view's camera math
/// (64×32 logical tiles): used to compute exact tap positions.
Offset _cellWorld(CellCoord cell) =>
    Offset((cell.column - cell.row) * 32.0, (cell.column + cell.row) * 16.0);

/// A store holding a full multi-city save — the double for focus and
/// attribution tests.
class _MemoryCityStore implements ParcelWorldStore {
  _MemoryCityStore(this.tables, this.states);

  MultiCityTables tables;
  Map<String, ParcelWorldState> states;

  @override
  Future<LoadedCitySave?> load() async =>
      LoadedCitySave(tables: tables, states: states);

  @override
  Future<void> saveCity(
    MultiCityTables tables,
    String cityId,
    ParcelWorldState state,
  ) async {
    this.tables = tables;
    states = {...states, cityId: state};
  }
}

class _MemoryParcelStore implements ParcelWorldStore {
  _MemoryParcelStore();

  ParcelWorldState? state;

  @override
  Future<LoadedCitySave?> load() async {
    final state = this.state;
    if (state == null) return null;
    return LoadedCitySave(
      tables: MultiCityTables(
        cities: [
          CityRecord(id: 'city_1', name: 'City 1', founded: state.dateKey),
        ],
        tablesById: {'city_1': worldToSheetTables(state)},
      ),
      states: {'city_1': state},
    );
  }

  @override
  Future<void> saveCity(
    MultiCityTables tables,
    String cityId,
    ParcelWorldState state,
  ) async => this.state = state;
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

  testWidgets('nothing outside the city is selectable', (tester) async {
    tester.view.devicePixelRatio = 1;
    // Wide enough to reach the wild pines two parcels north-west of
    // the founding parcel: the side panel caps the map's width, so a
    // phone viewport cannot put them under a tap.
    tester.view.physicalSize = const Size(1600, 1200);
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

    final mapRect = tester.getRect(find.byType(ParcelWorldView));
    Offset screenFor(CellCoord cell) =>
        mapRect.center + (_cellWorld(cell) - _cellWorld(const CellCoord(4, 4)));

    // A wild pine stands at (-2,-9), on charted land the town does
    // not own. Inspecting it must select nothing — not the tree, and
    // not the tile beneath it.
    await tester.tapAt(
      screenFor(const CellCoord(-2, -9)) + const Offset(0, -24),
    );
    await tester.pump();
    var view = tester.widget<ParcelWorldView>(find.byType(ParcelWorldView));
    expect(view.selectedCell, isNull, reason: 'foreign tiles select nothing');
    expect(view.selectedPropId, isNull, reason: 'wild props are not pickable');

    // The same rule under the building tool: bare foreign ground
    // selects nothing there either.
    await tester.tap(find.text('Buildings'));
    await tester.pump();
    await tester.tapAt(screenFor(const CellCoord(10, 10)));
    await tester.pump();
    view = tester.widget<ParcelWorldView>(find.byType(ParcelWorldView));
    expect(view.selectedCell, isNull);
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

  testWidgets('focus switches cities and attributes play to the focused one', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Two towns on the shared map: Alpha at (0,0), Beta at (2,0) —
    // a charted grass parcel east of the channel.
    final alpha = foundedWorld(withRoad: true);
    final beta = sheetTablesToWorld(
      SheetTables(
        userData: {
          'seed': '9',
          'coins': '${content.economy.startingTreasuryCoins}',
          'coins_earned': '${content.economy.startingTreasuryCoins}',
          'coins_spent': '0',
          'simulated_date': '2026-11-02',
          'high_water_date': '2026-11-02',
          'construction_day': '0',
        },
        ownedParcels: const [
          ['2', '0'],
        ],
        tiles: const [
          ['20', '4', 'road', 'complete', 'asphalt', '', '', ''],
        ],
        projects: const [],
      ),
      content: content,
      terrainProvider: ContentTerrainProvider(content.terrain),
    );
    final store = _MemoryCityStore(
      MultiCityTables(
        cities: const [
          CityRecord(id: 'city_1', name: 'Alpha', founded: '2026-11-01'),
          CityRecord(id: 'city_2', name: 'Beta', founded: '2026-11-02'),
        ],
        tablesById: {
          'city_1': worldToSheetTables(alpha),
          'city_2': worldToSheetTables(beta),
        },
      ),
      {'city_1': alpha, 'city_2': beta},
    );

    await tester.pumpWidget(ParcelCityApp(store: store, content: content));
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    // The lowest id is focused.
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('1 parcel · 0 structures'), findsOneWidget);

    // Switch focus to Beta through the city list.
    await tester.tap(find.text('Alpha'));
    await tester.pump();
    await tester.tap(find.text('Beta'));
    await tester.pump();
    expect(find.text('Beta'), findsOneWidget);
    // The camera flies there — out, across, in — over about three
    // seconds. Let it land before the road-plan taps lean on its
    // final position.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // A road plan in Beta — attributed to Beta alone. The camera
    // flew to Beta's owned area, so its parcel sits under the
    // camera's centre; on foreign land the quote would refuse and
    // no buy button could appear.
    await tester.tap(find.text('Roads'));
    await tester.pump();
    final viewCenter = tester.getRect(find.byType(ParcelWorldView)).center;
    Offset screenFor(CellCoord cell) =>
        viewCenter + (_cellWorld(cell) - _cellWorld(const CellCoord(20, 4)));
    await tester.tapAt(screenFor(const CellCoord(20, 5)));
    await tester.pump();
    await tester.tapAt(screenFor(const CellCoord(21, 5)));
    await tester.pump();
    expect(find.textContaining('Buy road plan'), findsOneWidget);
    await tester.tap(find.textContaining('Buy road plan'));
    await tester.pump();
    // The purchase committed to Beta: the road tool shows the creep
    // card for the new stretch.
    expect(find.text('0/2 tiles laid · one more per check-in'), findsOneWidget);

    // The save spliced Beta's block only.
    expect(store.states['city_2']!.constructions, hasLength(1));
    expect(store.states['city_1']!.constructions, isEmpty);
    expect(store.tables.tablesById['city_1']!.projects, isEmpty);
    expect(store.tables.tablesById['city_2']!.projects, hasLength(1));

    // A half-drawn plan dies on focus switch.
    await tester.tapAt(screenFor(const CellCoord(22, 5)));
    await tester.pump();
    await tester.tapAt(screenFor(const CellCoord(23, 5)));
    await tester.pump();
    expect(find.textContaining('Buy road plan'), findsOneWidget);
    await tester.tap(find.text('Beta'));
    await tester.pump();
    await tester.tap(find.text('Alpha'));
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.textContaining('Buy road plan'),
      findsNothing,
      reason: 'the interaction surface resets with focus',
    );
    expect(find.text('1 parcel · 0 structures'), findsOneWidget);
  });

  testWidgets('re-picking the focused city flies the camera home', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // The same two towns as the focus test: Alpha at (0,0), Beta at
    // (2,0) with its road at (20,4).
    final alpha = foundedWorld(withRoad: true);
    final beta = sheetTablesToWorld(
      SheetTables(
        userData: {
          'seed': '9',
          'coins': '${content.economy.startingTreasuryCoins}',
          'coins_earned': '${content.economy.startingTreasuryCoins}',
          'coins_spent': '0',
          'simulated_date': '2026-11-02',
          'high_water_date': '2026-11-02',
          'construction_day': '0',
        },
        ownedParcels: const [
          ['2', '0'],
        ],
        tiles: const [
          ['20', '4', 'road', 'complete', 'asphalt', '', '', ''],
        ],
        projects: const [],
      ),
      content: content,
      terrainProvider: ContentTerrainProvider(content.terrain),
    );
    final store = _MemoryCityStore(
      MultiCityTables(
        cities: const [
          CityRecord(id: 'city_1', name: 'Alpha', founded: '2026-11-01'),
          CityRecord(id: 'city_2', name: 'Beta', founded: '2026-11-02'),
        ],
        tablesById: {
          'city_1': worldToSheetTables(alpha),
          'city_2': worldToSheetTables(beta),
        },
      ),
      {'city_1': alpha, 'city_2': beta},
    );

    await tester.pumpWidget(ParcelCityApp(store: store, content: content));
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    // Fly to Beta and let the camera land on its centroid.
    await tester.tap(find.text('Alpha'));
    await tester.pump();
    await tester.tap(find.text('Beta'));
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Wander off: a drag pans the camera away from the centroid.
    await tester.dragFrom(
      tester.getRect(find.byType(ParcelWorldView)).center,
      const Offset(220, 120),
    );
    await tester.pump();

    // Re-pick the focused city from the list — a camera move, not a
    // switch: the flight must run even though focus never changed.
    await tester.tap(find.text('Beta'));
    await tester.pump();
    await tester.tap(find.widgetWithText(SimpleDialogOption, 'Beta'));
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The camera is home: a road plan on Beta's parcel quotes. Had
    // the flight not run, the home-anchored taps would land on
    // foreign ground and the buy button could not appear.
    await tester.tap(find.text('Roads'));
    await tester.pump();
    final viewCenter = tester.getRect(find.byType(ParcelWorldView)).center;
    Offset screenFor(CellCoord cell) =>
        viewCenter + (_cellWorld(cell) - _cellWorld(const CellCoord(20, 4)));
    await tester.tapAt(screenFor(const CellCoord(20, 5)));
    await tester.pump();
    await tester.tapAt(screenFor(const CellCoord(21, 5)));
    await tester.pump();
    expect(find.textContaining('Buy road plan'), findsOneWidget);
  });

  testWidgets('starting a new city founds a second save block', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final alpha = foundedWorld(withRoad: true);
    final store = _MemoryCityStore(
      MultiCityTables(
        cities: const [
          CityRecord(id: 'city_1', name: 'Alpha', founded: '2026-11-01'),
        ],
        tablesById: {'city_1': worldToSheetTables(alpha)},
      ),
      {'city_1': alpha},
    );

    await tester.pumpWidget(ParcelCityApp(store: store, content: content));
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    // Start a new city through the list; the name dialog defaults to
    // the minted number.
    await tester.tap(find.text('Alpha'));
    await tester.pump();
    await tester.tap(find.text('Start a new city'));
    await tester.pump();
    expect(find.text('Found city'), findsOneWidget);
    await tester.tap(find.text('Found city'));
    await tester.pump();

    // Focus switched to the fresh city: the founding loop restarts,
    // and the index gained its record.
    expect(find.text('City 2'), findsOneWidget);
    expect(find.text('0 parcels · 0 structures'), findsOneWidget);
    expect(
      find.text('Open the Parcel tool to claim your free founding parcel'),
      findsOneWidget,
    );
    expect(store.tables.cities.map((record) => record.id), [
      'city_1',
      'city_2',
    ]);

    // Founding cannot take city_1's parcel…
    await tester.tap(find.text('Parcels'));
    await tester.pump();
    final viewCenter = tester.getRect(find.byType(ParcelWorldView)).center;
    await tester.tapAt(viewCenter);
    await tester.pump();
    expect(find.text('Another city has claimed that parcel.'), findsOneWidget);
    // …but charted unclaimed land founds free.
    Offset screenFor(CellCoord cell) =>
        viewCenter + (_cellWorld(cell) - _cellWorld(const CellCoord(4, 4)));
    await tester.tapAt(screenFor(const CellCoord(20, 4)));
    await tester.pump();
    final review = find.text('Review parcel purchase');
    await tester.ensureVisible(review);
    await tester.pump();
    await tester.tap(review);
    await tester.pump();
    await tester.tap(find.text('Claim parcel'));
    await tester.pump();
    expect(find.text('1 parcel · 0 structures'), findsOneWidget);

    // The founding landed in city_2's block; Alpha's is untouched.
    expect(store.states['city_2']!.parcels, hasLength(1));
    expect(store.states['city_1']!.parcels, hasLength(1));
    expect(store.tables.tablesById['city_2']!.ownedParcels, hasLength(1));
    expect(store.tables.tablesById['city_1']!.ownedParcels, hasLength(1));
  });
}

/// Actor-pass tests for the static/dynamic split.
///
/// 1. Property test: merging the pre-sorted static and dynamic lists
///    reproduces exactly the (depth, insertion) order the unsplit
///    single-list sort produced — the split must not change painter
///    order, depth ties included.
/// 2. Widget test: the static-actor cache survives idle frames and
///    camera motion without a rebuild, and rebuilds exactly once
///    when the world changes.
library;

import 'dart:math' as math;

import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/rendering/parcel_world_view.dart';
import 'package:citysim/rendering/perf_probe.dart';
import 'package:citysim/storage/sheet_tables.dart';
import 'package:citysim/storage/world_sheet_codec.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:citysim/world/terrain_provider.dart';
import 'package:citysim/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'frozen_content.dart';

ParcelWorldState _anchorWorld(ContentBundle content) => sheetTablesToWorld(
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
  terrainProvider: ContentTerrainProvider(content.terrain),
);

void main() {
  // The frozen content bundle builds synchronously in setUpAll; the
  // sprite PNGs it names still decode during the tests, and asset
  // reads inside a testWidgets body run in fake-async, where they
  // are unreliable.
  late ContentBundle content;
  setUpAll(() {
    content = frozenContent();
  });

  test('merged actor order equals the single-list sort it replaced', () {
    final random = math.Random(7);
    // The painter's pre-sort: (depth, insertion order), per list.
    List<(double, int)> sortByDepthInsertion(List<(double, int)> list) {
      final order = [for (var i = 0; i < list.length; i++) i]
        ..sort((a, b) {
          final depth = list[a].$1.compareTo(list[b].$1);
          return depth != 0 ? depth : a.compareTo(b);
        });
      return [for (final i in order) list[i]];
    }

    // Coarse depth grid on purpose: many exact ties, the case where
    // a merge could quietly diverge from a full sort.
    for (var trial = 0; trial < 300; trial++) {
      final statics = <(double, int)>[
        for (var i = 0; i < random.nextInt(12); i++)
          (random.nextInt(6) * 0.5, i),
      ];
      final dynamics = <(double, int)>[
        for (var i = 0; i < random.nextInt(12); i++)
          (random.nextInt(6) * 0.5, i),
      ];
      final merged = mergeByDepth(
        sortByDepthInsertion(statics),
        sortByDepthInsertion(dynamics),
        (entry) => entry.$1,
      );
      // The unsplit pass: one list, statics appended before the
      // dynamics, sorted by (depth, global insertion index).
      final single = [...statics, ...dynamics];
      final order = [for (var i = 0; i < single.length; i++) i]
        ..sort((a, b) {
          final depth = single[a].$1.compareTo(single[b].$1);
          return depth != 0 ? depth : a.compareTo(b);
        });
      expect(merged, [for (final i in order) single[i]]);
    }
  });

  testWidgets(
    'the static actor cache survives motion and rebuilds once per world '
    'change',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 600);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // The real terrain's painted nature rides along as wild props,
      // so the static pass carries the author's forest plus this
      // placed pine.
      final world = _anchorWorld(content).copyWith(
        props: [
          PlacedProp(
            id: 'prop:4:3:2.2',
            catalogueId: 'pine-tree',
            cell: const CellCoord(4, 3),
            subtileX: 2,
            subtileY: 2,
            pricePaid: 0,
            placedAtDay: 0,
          ),
        ],
      );
      ParcelWorldProbe.recording = true;
      ParcelWorldProbe.reset();

      Widget app(ParcelWorldState state) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: ParcelWorldView(
            state: state,
            content: content,
            terrainProvider: ContentTerrainProvider(content.terrain),
            onCellTap: (cell, structureId, subtileX, subtileY) {},
          ),
        ),
      );

      await tester.pumpWidget(app(world));
      // Settle: decode art (real asset I/O only progresses inside
      // runAsync windows) until frames pass with no chunk records.
      var settled = false;
      for (var attempt = 0; attempt < 10 && !settled; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        ParcelWorldProbe.reset();
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        settled =
            ParcelWorldProbe.samples.isNotEmpty &&
            ParcelWorldProbe.samples.every(
              (sample) => sample.chunkRecords == 0,
            );
      }
      expect(settled, isTrue, reason: 'the artwork should finish decoding');

      // Idle: a still camera never rebuilds the statics.
      ParcelWorldProbe.reset();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        ParcelWorldProbe.samples.map((sample) => sample.staticRebuilds),
        everyElement(0),
        reason: 'idle frames replay the cached static order',
      );

      // Camera motion: painter instances come and go per rebuild,
      // the cached order stays.
      ParcelWorldProbe.reset();
      final center = tester.getRect(find.byType(ParcelWorldView)).center;
      final drag = await tester.startGesture(center);
      for (var i = 0; i < 12; i++) {
        await drag.moveBy(const Offset(14, 7));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await drag.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        ParcelWorldProbe.samples.map((sample) => sample.staticRebuilds),
        everyElement(0),
        reason: 'panning must replay the cached static order',
      );

      // A world change rebuilds the statics exactly once.
      ParcelWorldProbe.reset();
      await tester.pumpWidget(app(world.copyWith(coins: world.coins + 1)));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        ParcelWorldProbe.samples.fold<int>(
          0,
          (sum, sample) => sum + sample.staticRebuilds,
        ),
        1,
        reason: 'one world change, one static rebuild',
      );
    },
  );

  testWidgets('wild nature decodes and draws before any purchase', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // The fresh, unfounded world — nothing owned, nothing placed, so
    // nothing in the save requests nature art. The only variable is
    // one wild pine on unowned land under the camera: with the
    // loader requesting nature roles, the actor pass draws one more
    // sprite once art settles; without it (the regression), the pine
    // never decodes and the frontier renders bare.
    final world = newParcelWorldState(
      content: content,
      seed: 123456,
      today: DateTime.utc(2026, 11, 2),
    );
    ContentTerrainProvider terrainWith(List<TerrainProp> props) =>
        ContentTerrainProvider(
          TerrainContent(
            generatorVersion: content.terrain.generatorVersion,
            parcels: content.terrain.parcels,
            tiles: content.terrain.tiles,
            props: props,
          ),
        );

    Widget app(ContentTerrainProvider terrain) => MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: ParcelWorldView(
          state: world,
          content: content,
          terrainProvider: terrain,
          onCellTap: (cell, structureId, subtileX, subtileY) {},
        ),
      ),
    );

    // Settle: decode art (real asset I/O only progresses inside
    // runAsync windows) until frames pass with no chunk records and
    // an unchanged actor count, then read that count.
    Future<int> settledActorCount(ContentTerrainProvider terrain) async {
      ParcelWorldProbe.recording = true;
      ParcelWorldProbe.reset();
      await tester.pumpWidget(app(terrain));
      var settled = false;
      var lastActors = -1;
      var quietWindows = 0;
      for (var attempt = 0; attempt < 25 && !settled; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 400)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        ParcelWorldProbe.reset();
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final frames = ParcelWorldProbe.samples;
        final actors = frames.isEmpty ? -1 : frames.last.actorOps;
        quietWindows = actors == lastActors ? quietWindows + 1 : 0;
        settled =
            frames.isNotEmpty &&
            frames.every((s) => s.chunkRecords == 0) &&
            quietWindows >= 2;
        lastActors = actors;
      }
      expect(settled, isTrue, reason: 'the artwork should finish decoding');
      return lastActors;
    }

    final bare = await settledActorCount(terrainWith(const []));
    final wild = await settledActorCount(
      terrainWith(const [
        TerrainProp(
          catalogueId: 'pine-tree',
          cell: CellCoord(4, 3),
          subtileX: 2,
          subtileY: 2,
        ),
      ]),
    );
    expect(
      wild,
      greaterThan(bare),
      reason: 'the wild pine must decode and draw on unowned land',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}

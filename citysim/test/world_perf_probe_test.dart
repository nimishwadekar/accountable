/// Performance probe measurement for the parcel-world renderer, run
/// against the real sample town from `assets/test_sheets` (read-only —
/// the save is never written).
///
/// Phases: idle at the default zoom, touch-drag panning at the default
/// zoom, trackpad pinch-out, and trackpad panning zoomed out. Each
/// phase prints [ProbeStats]; the expectations at the end check the
/// structural claims from the performance analysis (which costs scale
/// with what), not absolute timings, so the test is stable across
/// machines.
///
/// Run on the desktop VM (the supported measurement platform):
///
///     flutter test test/world_perf_probe_test.dart
///
/// Debug Chrome is deliberately not a supported probe target: even a
/// trimmed run cannot finish inside a 14-minute timeout there — itself
/// a finding about the web-debug platform tax. For live numbers in a
/// real browser, open a debug game build with `?perf=1` and read the
/// on-screen HUD instead.
library;

import 'package:citysim/content/asset_content_source.dart';
import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/parcel_city_app.dart';
import 'package:citysim/rendering/parcel_world_view.dart';
import 'package:citysim/rendering/perf_probe.dart';
import 'package:citysim/storage/sheet_tables.dart';
import 'package:citysim/storage/world_sheet_codec.dart';
import 'package:citysim/world/terrain_provider.dart';
import 'package:citysim/world/world_save_store.dart';
import 'package:citysim/world/world_state.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Size;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

class _MemoryParcelStore implements ParcelWorldStore {
  ParcelWorldState? state;

  @override
  Future<ParcelWorldState?> load() async => state;

  @override
  Future<void> save(ParcelWorldState state) async => this.state = state;
}

/// The bundled sample town, decoded from the live CSV save.
Future<ParcelWorldState> _loadSampleTown(ContentBundle content) async {
  Future<String> sheet(String name) =>
      rootBundle.loadString('assets/test_sheets/$name.csv');
  final tables = decodeSheetTables(
    userData: await sheet('UserData'),
    tiles: await sheet('Tiles'),
    props: await sheet('Props'),
    ownedParcels: await sheet('OwnedParcels'),
    projects: await sheet('Projects'),
  );
  return sheetTablesToWorld(
    tables,
    content: content,
    terrainProvider: ContentTerrainProvider(content.terrain),
  );
}

void main() {
  // Content loads in setUpAll (real async): asset reads inside a
  // testWidgets body run in fake-async, where they are unreliable —
  // see the note in parcel_city_widget_test.dart.
  late ContentBundle content;
  late ParcelWorldState sampleTown;
  setUpAll(() async {
    content = await loadContentBundle(const AssetContentSource());
    sampleTown = await _loadSampleTown(content);
  });

  // Viewport matching the analysis: a typical laptop browser window at
  // DPR 1 (logical pixels).
  const viewport = Size(1500, 850);

  testWidgets(
    'renderer probe: idle vs motion at two zoom levels on the sample town',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = viewport;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final world = sampleTown;
      ParcelWorldProbe.recording = true;
      ParcelWorldProbe.reset();
      await tester.pumpWidget(
        ParcelCityApp(
          store: _MemoryParcelStore()..state = world,
          content: content,
        ),
      );

      // Settle: decode images, initialize the camera, and keep pumping
      // until a window of frames passes without a ground-layer
      // re-record (late image loads each trigger one). Real asset I/O
      // only progresses inside runAsync windows; the sample town's
      // ~130 sprites take a few real seconds in debug mode.
      debugPrint('[perf] settling…');
      var settled = false;
      for (var attempt = 0; attempt < 10 && !settled; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 400)),
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
      expect(
        settled,
        isTrue,
        reason:
            'images should finish decoding so later phases measure '
            'steady-state frames',
      );
      expect(
        find.text('Could not load the world artwork.'),
        findsNothing,
        reason: 'the painter must be mounted for the phases to measure',
      );

      final center = tester.getRect(find.byType(ParcelWorldView)).center;

      // Phase A — idle at the default zoom.
      debugPrint('[perf] phase A: idle @ zoom 1.00');
      ParcelWorldProbe.reset();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final idle = ProbeStats(
        'idle @ zoom 1.00',
        ParcelWorldProbe.samples.toList(),
      );

      // Phase B — touch-drag panning at the default zoom.
      debugPrint('[perf] phase B: panning @ zoom 1.00');
      ParcelWorldProbe.reset();
      final drag = await tester.startGesture(center);
      for (var i = 0; i < 36; i++) {
        await drag.moveBy(const Offset(10, 5));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await drag.up();
      await tester.pump(const Duration(milliseconds: 100));
      final panIn = ProbeStats(
        'panning @ zoom 1.00',
        ParcelWorldProbe.samples.toList(),
      );

      // Phase C — trackpad pinch out to roughly half zoom. A trackpad
      // gesture starts with panZoomStart automatically.
      debugPrint('[perf] phase C: pinching out');
      ParcelWorldProbe.reset();
      final pinch = await tester.startGesture(
        center,
        kind: PointerDeviceKind.trackpad,
      );
      var trackScale = 1.0;
      for (var i = 0; i < 6; i++) {
        trackScale *= 0.9;
        await pinch.panZoomUpdate(center, scale: trackScale);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await pinch.panZoomEnd();
      await tester.pump(const Duration(milliseconds: 100));
      final pinchOut = ProbeStats(
        'pinching out',
        ParcelWorldProbe.samples.toList(),
      );

      // Phase D — trackpad panning while zoomed out.
      debugPrint('[perf] phase D: panning zoomed out');
      ParcelWorldProbe.reset();
      final pan = await tester.startGesture(
        center,
        kind: PointerDeviceKind.trackpad,
      );
      for (var i = 1; i <= 36; i++) {
        await pan.panZoomUpdate(center, pan: Offset(i * 12.0, i * 6.0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await pan.panZoomEnd();
      await tester.pump(const Duration(milliseconds: 100));
      final panOut = ProbeStats(
        'panning @ zoom ~0.54',
        ParcelWorldProbe.samples.toList(),
      );

      debugPrint(idle.describe());
      debugPrint(panIn.describe());
      debugPrint(pinchOut.describe());
      debugPrint(panOut.describe());

      // Structural claims from the performance analysis. Absolute
      // timings vary per machine; these relationships should not.
      // 1. A still camera never re-records chunks.
      expect(idle.chunkRecords, lessThanOrEqualTo(2));
      // 2. Motion no longer re-records the ground layer — only chunks
      //    entering view record, about one per frame at most.
      expect(panIn.chunkRecords, lessThanOrEqualTo(20));
      expect(panOut.chunkRecords, lessThanOrEqualTo(60));
      // 3. Frame draws are chunk textures plus actors — hundreds, not
      //    the thousands of per-cell draws the unchunked renderer
      //    pushed at zoom-out.
      expect(panOut.meanTotalOps, lessThan(600));
      // 4. More chunks are visible zoomed out than zoomed in.
      expect(panOut.meanChunkDraws, greaterThan(panIn.meanChunkDraws));
      // 5. Chunk-granularity culling: drawn cells stay near the
      //    visible-cell estimate, never below it.
      expect(panOut.overdraw, greaterThan(0.85));
      expect(panOut.overdraw, lessThan(1.9));
      // 6. The zoom actually reached the zoomed-out regime.
      expect(panOut.meanScale, lessThan(0.62));
      expect(panOut.meanScale, greaterThan(0.42));

      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 14)),
  );
}

/// Debug-only performance instrumentation for the parcel-world
/// renderer.
///
/// The probe answers specific questions about each frame:
/// - how long the UI thread spends in `paint()` overall, and how much
///   of that is the terrain layer (chunk records, rasterizations, and
///   chunk texture draws);
/// - how many raster quads the frame carries (chunk textures plus
///   actors), because op count — not pixels — is what dominates
///   zoomed-out frames;
/// - how much chunk re-recording happened (world or sprite changes,
///   or entering previously unseen areas);
/// - how many cells the draw bounds cover versus how many are actually
///   visible (chunk-granularity overdraw).
///
/// Frames are collected while [recording] is on. A debug build opened
/// with `?perf=1` enables recording automatically, paints a small HUD
/// onto the map, and prints a summary to the console every few
/// seconds. Everything here is a no-op in release builds (`kDebugMode`
/// guards), and tests read [samples] directly.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// One measured frame of the parcel-world renderer.
class FrameSample {
  const FrameSample({
    required this.scale,
    required this.paintMicros,
    required this.terrainMicros,
    required this.chunkDraws,
    required this.chunkRecords,
    required this.terrainOps,
    required this.washOps,
    required this.roadOps,
    required this.outlineOps,
    required this.actorOps,
    required this.boundsCells,
    required this.drawnCells,
    required this.onscreenCells,
  });

  final double scale;

  /// Total UI-thread time spent in `paint()` for this frame.
  final int paintMicros;

  /// Time in the terrain layer: chunk records, rasterizations, and
  /// chunk draws.
  final int terrainMicros;

  /// Chunk textures (or world-space picture replays) drawn this frame.
  final int chunkDraws;

  /// Chunks re-recorded this frame.
  final int chunkRecords;

  /// Sprite draws emitted while recording chunks this frame.
  final int terrainOps;
  final int washOps;
  final int roadOps;
  final int outlineOps;

  final int actorOps;

  /// Cells covered by the painter's draw bounds (the lattice bounding
  /// box of the visible diamond).
  final int boundsCells;

  /// Cells covered by the chunks actually drawn.
  final int drawnCells;

  /// Cells whose diamonds intersect the viewport.
  final int onscreenCells;

  /// Raster quads pushed this frame: chunk textures plus actors.
  int get totalOps => chunkDraws + actorOps;
}

/// Summary statistics over a run of frames.
class ProbeStats {
  ProbeStats(this.label, List<FrameSample> source)
    : frames = source.length,
      chunkRecords = source.fold<int>(
        0,
        (sum, sample) => sum + sample.chunkRecords,
      ),
      meanScale = _mean(source.map((s) => s.scale)),
      meanPaintMs = _mean(source.map((s) => s.paintMicros / 1000)),
      p95PaintMs = _percentile(
        source.map((s) => s.paintMicros / 1000).toList(),
        0.95,
      ),
      maxPaintMs = source.fold<double>(
        0,
        (max, s) => math.max(max, s.paintMicros / 1000),
      ),
      meanTerrainMs = _mean(source.map((s) => s.terrainMicros / 1000)),
      maxTerrainMs = source.fold<double>(
        0,
        (max, s) => math.max(max, s.terrainMicros / 1000),
      ),
      meanChunkDraws = _mean(source.map((s) => s.chunkDraws)),
      meanTotalOps = _mean(source.map((s) => s.totalOps)),
      meanActorOps = _mean(source.map((s) => s.actorOps)),
      meanTerrainOps = _mean(source.map((s) => s.terrainOps)),
      meanWashOps = _mean(source.map((s) => s.washOps)),
      meanRoadOps = _mean(source.map((s) => s.roadOps)),
      meanOutlineOps = _mean(source.map((s) => s.outlineOps)),
      meanBoundsCells = _mean(source.map((s) => s.boundsCells)),
      meanDrawnCells = _mean(source.map((s) => s.drawnCells)),
      meanOnscreenCells = _mean(source.map((s) => s.onscreenCells));

  final String label;
  final int frames;
  final int chunkRecords;
  final double meanScale;
  final double meanPaintMs;
  final double p95PaintMs;
  final double maxPaintMs;
  final double meanTerrainMs;
  final double maxTerrainMs;
  final double meanChunkDraws;
  final double meanTotalOps;
  final double meanActorOps;
  final double meanTerrainOps;
  final double meanWashOps;
  final double meanRoadOps;
  final double meanOutlineOps;
  final double meanBoundsCells;
  final double meanDrawnCells;
  final double meanOnscreenCells;

  /// Drawn cells per visible cell — chunk-granularity culling waste.
  /// ~1.0 is perfect; the unculled bounding box measured ~2.6.
  double get overdraw =>
      meanOnscreenCells > 0 ? meanDrawnCells / meanOnscreenCells : 0;

  String describe() =>
      '-- $label: $frames frames, $chunkRecords chunk records, zoom '
      '${meanScale.toStringAsFixed(2)}\n'
      '   paint: mean ${meanPaintMs.toStringAsFixed(1)}ms'
      '  p95 ${p95PaintMs.toStringAsFixed(1)}ms'
      '  max ${maxPaintMs.toStringAsFixed(1)}ms'
      '  (terrain: mean ${meanTerrainMs.toStringAsFixed(1)}ms,'
      ' max ${maxTerrainMs.toStringAsFixed(1)}ms)\n'
      '   draws/frame: ${_fmt(meanTotalOps)} total'
      ' - chunks ${_fmt(meanChunkDraws)},'
      ' actors ${_fmt(meanActorOps)}\n'
      '   record work/frame: terrain ${_fmt(meanTerrainOps)},'
      ' wash ${_fmt(meanWashOps)},'
      ' roads ${_fmt(meanRoadOps)},'
      ' outlines ${_fmt(meanOutlineOps)}\n'
      '   bounds ${_fmt(meanBoundsCells)} cells,'
      ' drawn ${_fmt(meanDrawnCells)},'
      ' onscreen ~${_fmt(meanOnscreenCells)}'
      ' (${overdraw.toStringAsFixed(2)}x overdraw)';

  static double _mean(Iterable<num> values) {
    var sum = 0.0;
    var count = 0;
    for (final value in values) {
      sum += value;
      count++;
    }
    return count == 0 ? 0 : sum / count;
  }

  static double _percentile(List<num> values, double p) {
    if (values.isEmpty) return 0;
    final sorted = values..sort();
    final index = (sorted.length * p).clamp(0, sorted.length - 1).floor();
    return sorted[index].toDouble();
  }

  static String _fmt(num value) {
    final rounded = value.round();
    final text = '$rounded';
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      final remaining = text.length - i - 1;
      if (remaining > 0 && remaining % 3 == 0) buffer.write(',');
    }
    return buffer.toString();
  }
}

/// Collects [FrameSample]s from the parcel-world painter. All methods
/// are cheap no-ops unless recording is enabled.
class ParcelWorldProbe {
  /// Collect frame samples. Enabled automatically when the HUD is on.
  static bool recording = false;

  /// Paint the on-screen HUD onto the map each frame.
  static bool hudVisible = false;

  static bool _queryChecked = false;
  static Stopwatch? _paintClock;
  static Stopwatch? _terrainClock;
  static int _terrainMicros = 0;
  static double _scale = 1;
  static int _chunkDraws = 0;
  static int _chunkRecords = 0;
  static int _terrainOps = 0;
  static int _washOps = 0;
  static int _roadOps = 0;
  static int _outlineOps = 0;
  static int _actorOps = 0;
  static int _boundsCells = 0;
  static int _drawnCells = 0;
  static int _onscreenCells = 0;

  /// Record-work counters from the most recent frame that recorded
  /// chunks, carried into replay-only frames for continuity.
  static int _carryTerrainOps = 0;
  static int _carryWashOps = 0;
  static int _carryRoadOps = 0;
  static int _carryOutlineOps = 0;

  static int _hudFrame = 0;
  static TextPainter? _hudPainter;
  static List<String>? _hudLines;

  /// Most recent samples, oldest first (capped).
  static final List<FrameSample> samples = [];

  static const int _maxSamples = 4096;
  static const int _hudWindow = 60;
  static const int _hudRefreshFrames = 30;
  static const int _consoleEveryFrames = 240;

  /// Clears collected samples. Per-frame counters reset on each frame.
  static void reset() => samples.clear();

  /// Called at the top of the painter's `paint()`. Reads the
  /// `?perf=1` query parameter once so a debug build can enable the
  /// HUD without code changes.
  static void beginFrame(double scale) {
    if (!kDebugMode) return;
    if (!_queryChecked) {
      _queryChecked = true;
      hudVisible = Uri.base.queryParameters['perf'] == '1';
    }
    if (hudVisible) recording = true;
    if (!recording) return;
    _scale = scale;
    _terrainMicros = 0;
    _chunkDraws = 0;
    _chunkRecords = 0;
    _terrainOps = 0;
    _washOps = 0;
    _roadOps = 0;
    _outlineOps = 0;
    _actorOps = 0;
    _boundsCells = 0;
    _drawnCells = 0;
    _onscreenCells = 0;
    _paintClock = Stopwatch()..start();
  }

  /// Called around the terrain layer's per-frame work (chunk records,
  /// rasterizations, and draws).
  static void beginTerrain() {
    if (_paintClock == null) return;
    _terrainClock = Stopwatch()..start();
  }

  static void endTerrain() {
    final clock = _terrainClock;
    if (clock == null) return;
    clock.stop();
    _terrainMicros += clock.elapsedMicroseconds;
    _terrainClock = null;
    _carryTerrainOps = _terrainOps;
    _carryWashOps = _washOps;
    _carryRoadOps = _roadOps;
    _carryOutlineOps = _outlineOps;
  }

  static void countChunkDraw() {
    if (_paintClock != null) _chunkDraws++;
  }

  static void countChunkRecord() {
    if (_paintClock != null) _chunkRecords++;
  }

  static void countTerrain() {
    if (_paintClock != null) _terrainOps++;
  }

  static void countWash() {
    if (_paintClock != null) _washOps++;
  }

  static void countRoad() {
    if (_paintClock != null) _roadOps++;
  }

  static void countOutline() {
    if (_paintClock != null) _outlineOps++;
  }

  static void countActor() {
    if (_paintClock != null) _actorOps++;
  }

  /// Cells covered by drawn chunks.
  static void noteDrawnCells(int cells) {
    if (_paintClock != null) _drawnCells += cells;
  }

  /// Cells covered by the painter's draw bounds.
  static void noteBoundsCells(int cells) {
    if (_paintClock != null) _boundsCells = cells;
  }

  /// Cells whose diamonds intersect the viewport.
  static void noteOnscreenCells(int cells) {
    if (_paintClock != null) _onscreenCells = cells;
  }

  /// Called at the end of the painter's `paint()`.
  static void endFrame() {
    final clock = _paintClock;
    if (clock == null) return;
    clock.stop();
    samples.add(
      FrameSample(
        scale: _scale,
        paintMicros: clock.elapsedMicroseconds,
        terrainMicros: _terrainMicros,
        chunkDraws: _chunkDraws,
        chunkRecords: _chunkRecords,
        terrainOps: _carryTerrainOps,
        washOps: _carryWashOps,
        roadOps: _carryRoadOps,
        outlineOps: _carryOutlineOps,
        actorOps: _actorOps,
        boundsCells: _boundsCells,
        drawnCells: _drawnCells,
        onscreenCells: _onscreenCells,
      ),
    );
    if (samples.length > _maxSamples) {
      samples.removeRange(0, samples.length - _maxSamples);
    }
    _paintClock = null;
    if (hudVisible && samples.isNotEmpty) {
      _hudFrame++;
      if (_hudFrame % _consoleEveryFrames == 0) {
        final window = samples.sublist(
          math.max(0, samples.length - _consoleEveryFrames),
        );
        debugPrint(
          ProbeStats('live (last ${window.length})', window).describe(),
        );
      }
    }
  }

  /// Paints the HUD in the map's top-right corner, below the camera
  /// reset button. Refreshes its text a couple of times per second
  /// from the most recent samples.
  static void paintHud(ui.Canvas canvas, ui.Size size) {
    if (!hudVisible || size.isEmpty) return;
    if (_hudLines == null || _hudFrame % _hudRefreshFrames == 0) {
      final window = samples.length <= _hudWindow
          ? samples
          : samples.sublist(samples.length - _hudWindow);
      final stats = ProbeStats('hud', window);
      _hudLines = [
        'paint ${stats.meanPaintMs.toStringAsFixed(1)}ms'
            ' (terrain ${stats.meanTerrainMs.toStringAsFixed(1)}ms,'
            ' ${stats.chunkRecords} chunk records)',
        'draws ${ProbeStats._fmt(stats.meanTotalOps)}'
            ' (chunks ${ProbeStats._fmt(stats.meanChunkDraws)},'
            ' actors ${ProbeStats._fmt(stats.meanActorOps)})',
        'zoom ${stats.meanScale.toStringAsFixed(2)}'
            ' - drawn ${ProbeStats._fmt(stats.meanDrawnCells)},'
            ' onscreen ~${ProbeStats._fmt(stats.meanOnscreenCells)}'
            ' (${stats.overdraw.toStringAsFixed(2)}x overdraw)',
      ];
      _hudPainter?.dispose();
      _hudPainter = TextPainter(
        text: TextSpan(
          text: _hudLines!.join('\n'),
          style: const TextStyle(
            color: ui.Color(0xFFF2F7F4),
            fontSize: 12,
            height: 1.35,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width - 24);
    }
    final painter = _hudPainter;
    if (painter == null) return;
    const padding = 8.0;
    const top = 62.0;
    final left = size.width - painter.width - padding - 10;
    final backdrop = ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(
        left,
        top,
        painter.width + padding * 2,
        painter.height + padding * 2,
      ),
      const ui.Radius.circular(8),
    );
    canvas.drawRRect(backdrop, ui.Paint()..color = const ui.Color(0xB3162B22));
    painter.paint(canvas, ui.Offset(left + padding, top + padding));
  }
}

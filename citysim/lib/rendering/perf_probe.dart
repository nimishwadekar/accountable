/// Debug-only performance instrumentation for the parcel-world
/// renderer.
///
/// The probe answers specific questions about each frame:
/// - how long the UI thread spends in `paint()` overall, and how much
///   of that is re-recording the cached ground layer (the suspected
///   cost of camera motion);
/// - how many draw ops the frame carries, split by layer, because op
///   count — not pixels — is what dominates zoomed-out frames;
/// - how many cells the draw bounds cover versus how many are actually
///   on screen (the bounding-box overdraw), estimated by sampling.
///
/// Frames are collected while [recording] is on. A debug build opened
/// with `?perf=1` enables recording automatically, paints a small HUD
/// onto the map, and prints a summary to the console every few seconds.
/// Everything here is a no-op in release builds (`kDebugMode` guards),
/// and tests read [samples] directly.
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
    required this.recordMicros,
    required this.terrainOps,
    required this.washOps,
    required this.shimmerContours,
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

  /// Time spent re-recording the cached ground layer; 0 when the frame
  /// replayed the existing picture.
  final int recordMicros;

  final int terrainOps;
  final int washOps;
  final int shimmerContours;
  final int roadOps;
  final int outlineOps;
  final int actorOps;

  /// Cells covered by the painter's draw bounds (the lattice bounding
  /// box of the visible diamond).
  final int boundsCells;

  /// Cells actually visited by the terrain record loop — after
  /// diamond culling this should sit near [onscreenCells] instead of
  /// [boundsCells].
  final int drawnCells;

  /// Estimated cells actually visible on screen.
  final int onscreenCells;

  bool get recorded => recordMicros > 0;

  int get flatOps =>
      terrainOps + washOps + shimmerContours + roadOps + outlineOps;

  int get totalOps => flatOps + actorOps;
}

/// Summary statistics over a run of frames.
class ProbeStats {
  ProbeStats(this.label, List<FrameSample> source)
    : frames = source.length,
      records = source.where((sample) => sample.recorded).length,
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
      meanRecordMs = _mean(
        source.where((s) => s.recorded).map((s) => s.recordMicros / 1000),
      ),
      maxRecordMs = source
          .where((s) => s.recorded)
          .fold<double>(0, (max, s) => math.max(max, s.recordMicros / 1000)),
      meanTotalOps = _mean(source.map((s) => s.totalOps)),
      meanTerrainOps = _mean(source.map((s) => s.terrainOps)),
      meanWashOps = _mean(source.map((s) => s.washOps)),
      meanShimmerContours = _mean(source.map((s) => s.shimmerContours)),
      meanRoadOps = _mean(source.map((s) => s.roadOps)),
      meanOutlineOps = _mean(source.map((s) => s.outlineOps)),
      meanActorOps = _mean(source.map((s) => s.actorOps)),
      meanBoundsCells = _mean(source.map((s) => s.boundsCells)),
      meanDrawnCells = _mean(source.map((s) => s.drawnCells)),
      meanOnscreenCells = _mean(source.map((s) => s.onscreenCells));

  final String label;
  final int frames;
  final int records;
  final double meanScale;
  final double meanPaintMs;
  final double p95PaintMs;
  final double maxPaintMs;
  final double meanRecordMs;
  final double maxRecordMs;
  final double meanTotalOps;
  final double meanTerrainOps;
  final double meanWashOps;
  final double meanShimmerContours;
  final double meanRoadOps;
  final double meanOutlineOps;
  final double meanActorOps;
  final double meanBoundsCells;
  final double meanDrawnCells;
  final double meanOnscreenCells;

  /// Drawn cells per on-screen cell — how much off-screen work the
  /// record loop still carries. ~1.0 is perfect culling; the
  /// unculled bounding box measured ~2.6.
  double get overdraw =>
      meanOnscreenCells > 0 ? meanDrawnCells / meanOnscreenCells : 0;

  String describe() =>
      '-- $label: $frames frames, $records re-records, zoom '
      '${meanScale.toStringAsFixed(2)}\n'
      '   paint: mean ${meanPaintMs.toStringAsFixed(1)}ms'
      '  p95 ${p95PaintMs.toStringAsFixed(1)}ms'
      '  max ${maxPaintMs.toStringAsFixed(1)}ms'
      '  (re-record: mean ${meanRecordMs.toStringAsFixed(1)}ms,'
      ' max ${maxRecordMs.toStringAsFixed(1)}ms)\n'
      '   ops/frame: ${_fmt(meanTotalOps)} total'
      ' - terrain ${_fmt(meanTerrainOps)},'
      ' wash ${_fmt(meanWashOps)},'
      ' shimmer ${_fmt(meanShimmerContours)},'
      ' roads ${_fmt(meanRoadOps)},'
      ' outlines ${_fmt(meanOutlineOps)},'
      ' actors ${_fmt(meanActorOps)}\n'
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

  static String _fmt(double value) {
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
  static Stopwatch? _recordClock;
  static double _scale = 1;
  static int _recordMicros = 0;
  static int _terrainOps = 0;
  static int _washOps = 0;
  static int _shimmerContours = 0;
  static int _roadOps = 0;
  static int _outlineOps = 0;
  static int _actorOps = 0;
  static int _onscreenCells = 0;
  static int _drawnCells = 0;

  /// Op counts from the most recent record, carried into replay-only
  /// frames: a frame that replays the cached picture still pushes all
  /// of those ops through the rasterizer, so its sample should say so.
  static int _carryTerrainOps = 0;
  static int _carryWashOps = 0;
  static int _carryShimmerContours = 0;
  static int _carryRoadOps = 0;
  static int _carryOutlineOps = 0;
  static int _carryOnscreenCells = 0;
  static int _carryDrawnCells = 0;
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
    _recordMicros = 0;
    _terrainOps = 0;
    _washOps = 0;
    _shimmerContours = 0;
    _roadOps = 0;
    _outlineOps = 0;
    _actorOps = 0;
    _onscreenCells = 0;
    _drawnCells = 0;
    _paintClock = Stopwatch()..start();
  }

  /// Called around the cached ground layer's re-record.
  static void beginRecord() {
    if (_paintClock == null) return;
    _recordClock = Stopwatch()..start();
  }

  static void endRecord() {
    final clock = _recordClock;
    if (clock == null) return;
    clock.stop();
    _recordMicros += clock.elapsedMicroseconds;
    _recordClock = null;
    _carryTerrainOps = _terrainOps;
    _carryWashOps = _washOps;
    _carryShimmerContours = _shimmerContours;
    _carryRoadOps = _roadOps;
    _carryOutlineOps = _outlineOps;
    _carryOnscreenCells = _onscreenCells;
    _carryDrawnCells = _drawnCells;
  }

  static void countTerrain() {
    if (_paintClock != null) _terrainOps++;
  }

  static void countWash() {
    if (_paintClock != null) _washOps++;
  }

  static void countShimmer() {
    if (_paintClock != null) _shimmerContours++;
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

  /// Adds sampled on-screen cells to this frame's estimate.
  static void noteOnscreenCells(int cells) {
    if (_paintClock != null) _onscreenCells += cells;
  }

  /// Counts cells visited by the terrain record loop.
  static void noteDrawnCells(int cells) {
    if (_paintClock != null) _drawnCells += cells;
  }

  /// Called at the end of the painter's `paint()`.
  static void endFrame({required int boundsCells}) {
    final clock = _paintClock;
    if (clock == null) return;
    clock.stop();
    final replayed = _recordMicros == 0;
    samples.add(
      FrameSample(
        scale: _scale,
        paintMicros: clock.elapsedMicroseconds,
        recordMicros: _recordMicros,
        terrainOps: replayed ? _carryTerrainOps : _terrainOps,
        washOps: replayed ? _carryWashOps : _washOps,
        shimmerContours: replayed ? _carryShimmerContours : _shimmerContours,
        roadOps: replayed ? _carryRoadOps : _roadOps,
        outlineOps: replayed ? _carryOutlineOps : _outlineOps,
        actorOps: _actorOps,
        boundsCells: boundsCells,
        drawnCells: replayed ? _carryDrawnCells : _drawnCells,
        onscreenCells: replayed ? _carryOnscreenCells : _onscreenCells,
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

  /// Paints the HUD in the top-left corner of the map. Refreshes its
  /// text a couple of times per second from the most recent samples.
  static void paintHud(ui.Canvas canvas, ui.Size size) {
    if (!hudVisible || size.isEmpty) return;
    if (_hudLines == null || _hudFrame % _hudRefreshFrames == 0) {
      final window = samples.length <= _hudWindow
          ? samples
          : samples.sublist(samples.length - _hudWindow);
      final stats = ProbeStats('hud', window);
      _hudLines = [
        'paint ${stats.meanPaintMs.toStringAsFixed(1)}ms'
            ' (record ${stats.meanRecordMs.toStringAsFixed(1)}ms,'
            ' ${stats.records}/${stats.frames} frames)',
        'ops ${ProbeStats._fmt(stats.meanTotalOps)}'
            ' - terrain ${ProbeStats._fmt(stats.meanTerrainOps)}'
            ' wash ${ProbeStats._fmt(stats.meanWashOps)}'
            ' shimmer ${ProbeStats._fmt(stats.meanShimmerContours)}'
            ' actors ${ProbeStats._fmt(stats.meanActorOps)}',
        'zoom ${stats.meanScale.toStringAsFixed(2)}'
            ' - bounds ${ProbeStats._fmt(stats.meanBoundsCells)},'
            ' drawn ${ProbeStats._fmt(stats.meanDrawnCells)},'
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
    // Anchored below the map panel's top-right camera-reset button so
    // it never covers the parcel/structure status chip at top-left.
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

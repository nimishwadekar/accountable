import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import 'content_api.dart';

/// Live previews for the ambience editor. These mirror the game's ambient
/// rendering in miniature: the same sine math, driven by a local ticker.

class _PreviewTicker extends StatefulWidget {
  const _PreviewTicker({required this.builder});

  final Widget Function(BuildContext context, double seconds) builder;

  @override
  State<_PreviewTicker> createState() => _PreviewTickerState();
}

class _PreviewTickerState extends State<_PreviewTicker>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _clock = _Clock();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(
      (elapsed) => _clock.seconds = elapsed.inMicroseconds / 1e6,
    );
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _clock,
    builder: (context, _) => widget.builder(context, _clock.seconds),
  );
}

class _Clock extends ChangeNotifier {
  double _seconds = 0;

  double get seconds => _seconds;

  set seconds(double value) {
    _seconds = value;
    notifyListeners();
  }
}

/// Water shimmer preview: bands of highlight sweeping a water diamond.
class WaterShimmerPreview extends StatelessWidget {
  const WaterShimmerPreview({
    required this.period,
    required this.maxOpacity,
    required this.bands,
    super.key,
  });

  final double period;
  final double maxOpacity;
  final int bands;

  @override
  Widget build(BuildContext context) => _PreviewTicker(
    builder: (context, seconds) => CustomPaint(
      size: const Size(140, 100),
      painter: _ShimmerPainter(
        seconds: seconds,
        period: period,
        maxOpacity: maxOpacity,
        bands: bands,
      ),
    ),
  );
}

class _ShimmerPainter extends CustomPainter {
  const _ShimmerPainter({
    required this.seconds,
    required this.period,
    required this.maxOpacity,
    required this.bands,
  });

  final double seconds;
  final double period;
  final double maxOpacity;
  final int bands;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final waterPaint = Paint()..color = const Color(0xFF699CBC);
    _diamond(canvas, center, size.width * 0.8, size.height * 0.8, waterPaint);

    for (var band = 0; band < bands; band++) {
      final wave =
          0.5 +
          0.5 *
              math.sin(
                2 * math.pi * (seconds / period) - band * 2 * math.pi / bands,
              );
      final alpha = wave * maxOpacity;
      if (alpha < 0.006) continue;
      _diamond(
        canvas,
        center,
        size.width * 0.8 * (1 - band / bands),
        size.height * 0.8 * (1 - band / bands),
        Paint()..color = Color.fromARGB((alpha * 255).round(), 235, 245, 250),
      );
    }
  }

  void _diamond(
    Canvas canvas,
    Offset center,
    double width,
    double height,
    Paint paint,
  ) {
    final path = Path()
      ..moveTo(center.dx, center.dy - height / 2)
      ..lineTo(center.dx + width / 2, center.dy)
      ..lineTo(center.dx, center.dy + height / 2)
      ..lineTo(center.dx - width / 2, center.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ShimmerPainter oldDelegate) =>
      oldDelegate.seconds != seconds ||
      oldDelegate.period != period ||
      oldDelegate.maxOpacity != maxOpacity ||
      oldDelegate.bands != bands;
}

/// Vegetation sway preview: a pine tree rocking around its base.
class SwayPreview extends StatelessWidget {
  const SwayPreview({
    required this.maxAngle,
    required this.frequency,
    super.key,
  });

  final double maxAngle;
  final double frequency;

  @override
  Widget build(BuildContext context) => _PreviewTicker(
    builder: (context, seconds) => Transform.rotate(
      angle: maxAngle * math.sin(seconds * frequency),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Image.network(
          ContentApi().assetUrl(
            'sprites/props/trees/prop_tree_pine_medium.png',
          ),
          width: 70,
          height: 90,
          fit: BoxFit.contain,
          alignment: Alignment.bottomCenter,
          errorBuilder: (_, _, _) => const Icon(Icons.park_rounded, size: 64),
        ),
      ),
    ),
  );
}

/// Pedestrian walk-cycle preview: cycling the pack's four walk frames at
/// the chosen frame rate and sprite scale.
class WalkCyclePreview extends StatelessWidget {
  const WalkCyclePreview({
    required this.frameRate,
    required this.spriteScale,
    super.key,
  });

  final double frameRate;
  final double spriteScale;

  @override
  Widget build(BuildContext context) => _PreviewTicker(
    builder: (context, seconds) {
      final frame = (seconds * frameRate).floor() % 4 + 1;
      return Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          color: const Color(0xFFB5DCCF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Image.network(
            ContentApi().assetUrl('characters/char_a_walk_SE_f0$frame.png'),
            width: 24 * spriteScale * 2,
            height: 32 * spriteScale * 2,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.directions_walk_rounded, size: 48),
          ),
        ),
      );
    },
  );
}

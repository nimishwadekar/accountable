/// Per-pixel tap testing for isometric sprites.
///
/// Screen rectangles massively over-cover iso art — a tall building's
/// box overlaps the tiles and neighbours behind it — so picking tests
/// the sprite's own alpha instead: a tap only hits a structure where
/// its art is actually opaque.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// CPU-side alpha of a decoded sprite. Built once per asset path when
/// the image loads; sprites are static art, so masks never invalidate.
class SpriteMask {
  const SpriteMask(this.width, this.height, this.alpha);

  final int width;
  final int height;
  final Uint8List alpha;

  /// Anti-aliased haze below this alpha value reads as transparent.
  static const int alphaThreshold = 16;

  bool hits(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return false;
    return alpha[y * width + x] >= alphaThreshold;
  }
}

/// Extracts a sprite's alpha channel for [SpriteMask] tap testing.
Future<SpriteMask?> extractSpriteMask(ui.Image image) async {
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  if (data == null) return null;
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  final alpha = Uint8List(image.width * image.height);
  for (var i = 0; i < alpha.length; i++) {
    alpha[i] = bytes[i * 4 + 3];
  }
  return SpriteMask(image.width, image.height, alpha);
}

/// Maps a screen-space [position] into the sprite's pixel space and
/// tests the mask. [rect] is the sprite's on-screen rectangle exactly
/// as drawn, so the mapping divides by the drawn size — taps stay
/// accurate at every camera zoom.
bool spritePixelHit(SpriteMask mask, Rect rect, Offset position) {
  if (!rect.contains(position)) return false;
  final px = ((position.dx - rect.left) / rect.width * mask.width).floor();
  final py = ((position.dy - rect.top) / rect.height * mask.height).floor();
  return mask.hits(px, py);
}

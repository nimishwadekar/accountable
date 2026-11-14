import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:citysim/rendering/parcel_world_view.dart';
import 'package:citysim/rendering/sprite_picking.dart';
import 'package:flutter_test/flutter_test.dart';

/// The pixel test behind the selection x-ray: art coverage, not
/// bounding boxes, decides whether a front sprite dims.
void main() {
  SpriteMask mask(int w, int h, List<(int, int)> opaque) {
    final alpha = Uint8List(w * h);
    for (final (x, y) in opaque) {
      alpha[y * w + x] = 255;
    }
    return SpriteMask(w, h, alpha);
  }

  test('art coverage, not bounding boxes, decides the overlap', () {
    // Two 10x10 sprites on coinciding rects. A's art on the left,
    // B's on the right: boxes overlap, art does not. Opaque pixels
    // sit on the sampler's step-2 lattice.
    final left = mask(10, 10, [(2, 4), (2, 6)]);
    final right = mask(10, 10, [(8, 4), (8, 6)]);
    const rect = Rect.fromLTWH(0, 0, 10, 10);
    expect(spriteArtOverlaps(rect, left, rect, right), isFalse);

    // B's art reaching into A's columns is coverage.
    final reaching = mask(10, 10, [(8, 4), (2, 6)]);
    expect(spriteArtOverlaps(rect, left, rect, reaching), isTrue);
  });

  test('missing masks fall back to the boxes', () {
    const rectA = Rect.fromLTWH(0, 0, 10, 10);
    const rectB = Rect.fromLTWH(5, 5, 10, 10);
    expect(spriteArtOverlaps(rectA, null, rectB, null), isTrue);
    expect(
      spriteArtOverlaps(rectA, null, Rect.fromLTWH(20, 20, 5, 5), null),
      isFalse,
    );
  });

  test('different canvas sizes map through their rects', () {
    // A 4x4 canvas stretched over an 8x8 rect against an 8x8 canvas
    // on the same rect: A's centre (2,2) lands on screen (4,4),
    // which maps to B's centre (4,4) — opaque on both sides.
    final small = mask(4, 4, [(2, 2)]);
    final large = mask(8, 8, [(4, 4)]);
    const rect = Rect.fromLTWH(0, 0, 8, 8);
    expect(spriteArtOverlaps(rect, small, rect, large), isTrue);
  });

  test('disjoint rects never overlap', () {
    final a = mask(4, 4, [(1, 1)]);
    final b = mask(4, 4, [(1, 1)]);
    expect(
      spriteArtOverlaps(
        Rect.fromLTWH(0, 0, 4, 4),
        a,
        Rect.fromLTWH(10, 10, 4, 4),
        b,
      ),
      isFalse,
    );
  });
}

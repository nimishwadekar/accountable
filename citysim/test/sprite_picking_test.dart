import 'dart:typed_data';

import 'package:citysim/rendering/sprite_picking.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

SpriteMask _mask(int width, int height, bool Function(int x, int y) opaque) {
  final alpha = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      alpha[y * width + x] = opaque(x, y) ? 255 : 0;
    }
  }
  return SpriteMask(width, height, alpha);
}

void main() {
  test('transparent pixels inside the rect do not hit', () {
    // A tall iso sprite shape: opaque column in the middle, empty
    // corners — the exact region that used to steal taps.
    final mask = _mask(10, 10, (x, y) => x >= 3 && x <= 6 && y >= 2);
    const rect = Rect.fromLTWH(0, 0, 100, 100);

    expect(
      spritePixelHit(mask, rect, const Offset(50, 50)),
      isTrue,
      reason: 'opaque centre hits',
    );
    expect(
      spritePixelHit(mask, rect, const Offset(10, 10)),
      isFalse,
      reason: 'transparent top-left corner misses',
    );
    expect(
      spritePixelHit(mask, rect, const Offset(90, 10)),
      isFalse,
      reason: 'transparent top-right corner misses',
    );
  });

  test('the alpha threshold ignores anti-aliased haze', () {
    final alpha = Uint8List(2);
    alpha[0] = SpriteMask.alphaThreshold - 1;
    alpha[1] = SpriteMask.alphaThreshold;
    final mask = SpriteMask(2, 1, alpha);
    const rect = Rect.fromLTWH(0, 0, 2, 1);

    expect(
      spritePixelHit(mask, rect, const Offset(0.5, 0.5)),
      isFalse,
      reason: 'below threshold reads as transparent',
    );
    expect(
      spritePixelHit(mask, rect, const Offset(1.5, 0.5)),
      isTrue,
      reason: 'at threshold reads as opaque',
    );
  });

  test('pixel mapping scales with the drawn rect', () {
    // The sprite draws at twice its pixel size (render scale and zoom);
    // a tap three quarters across the rect must test the pixel three
    // quarters across the mask.
    final mask = _mask(4, 4, (x, y) => x == 3 && y == 3);
    const rect = Rect.fromLTWH(100, 200, 8, 8);

    expect(
      spritePixelHit(
        mask,
        rect,
        const Offset(100 + 8 * 0.875, 200 + 8 * 0.875),
      ),
      isTrue,
      reason: 'tap maps to the opaque bottom-right pixel',
    );
    expect(
      spritePixelHit(
        mask,
        rect,
        const Offset(100 + 8 * 0.625, 200 + 8 * 0.875),
      ),
      isFalse,
      reason: 'neighbouring pixel is transparent',
    );
  });

  test('taps outside the rect never hit', () {
    final mask = _mask(4, 4, (x, y) => true);
    const rect = Rect.fromLTWH(10, 10, 20, 20);

    expect(spritePixelHit(mask, rect, const Offset(9.9, 20)), isFalse);
    expect(spritePixelHit(mask, rect, const Offset(30.1, 20)), isFalse);
    expect(spritePixelHit(mask, rect, const Offset(20, 9.9)), isFalse);
    expect(spritePixelHit(mask, rect, const Offset(20, 30.1)), isFalse);
  });
}

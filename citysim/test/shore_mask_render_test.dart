import 'dart:ui' as ui;

import 'package:citysim/content/asset_content_source.dart';
import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/rendering/parcel_world_view.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Render-level regression tests for the colour-masked shore art. The
/// masks feed `ui.ImageDescriptor.raw` with premultiplied RGBA bytes —
/// leaving colour under zero alpha renders as amplified garbage (the
/// banks once drew solid white), so these tests draw the real masked
/// art and read the canvas back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ContentBundle content;
  setUpAll(() async {
    content = await loadContentBundle(const AssetContentSource());
  });

  Future<ui.Image> decode(String path) async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  test('masked banks draw grass and stay transparent over water', () async {
    final image = await decode(content.tryAssetPath('shore.grass.quarter.se')!);
    final bank = await maskShoreBank('shore.grass.quarter.se', image);
    expect(bank, isNotNull);

    // Draw the bank over a flat blue "water" background and read it
    // back — the same drawImageRect the painter performs.
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 128, 64),
      ui.Paint()..color = const ui.Color(0xFF699CBC),
    );
    canvas.drawImageRect(
      bank!,
      const Rect.fromLTWH(0, 0, 128, 64),
      const Rect.fromLTWH(0, 0, 128, 64),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(128, 64);
    final bytes = await rendered.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    int rgbaAt(int x, int y) => bytes!.getUint32((y * 128 + x) * 4);

    // The bank half: opaque grass, not white — the premultiplied-alpha
    // regression turned this pixel white.
    final grass = rgbaAt(32, 24);
    expect((grass >> 16) & 0xFF, greaterThan(140), reason: 'grass green');
    expect((grass >> 8) & 0xFF, lessThan(120), reason: 'not washed out');
    expect(grass & 0xFF, 255, reason: 'opaque');

    // The masked-out half: the background shows through untouched.
    final open = rgbaAt(96, 40);
    expect((open >> 16) & 0xFF, inInclusiveRange(130, 190));
    expect((open >> 8) & 0xFF, greaterThan(150), reason: 'blue background');
    expect(open & 0xFF, 255, reason: 'opaque');

    // And a downscaled draw — the game draws 128×64 art at 64×32 —
    // must not blow out along the waterline either.
    final small = await picture.toImage(64, 32);
    final smallBytes = await small.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    for (var x = 0; x < 64; x++) {
      for (var y = 0; y < 32; y++) {
        final rgba = smallBytes!.getUint32((y * 64 + x) * 4);
        final r = (rgba >> 24) & 0xFF,
            g = (rgba >> 16) & 0xFF,
            b = (rgba >> 8) & 0xFF;
        expect(
          r < 250 || g < 250 || b < 250,
          isTrue,
          reason:
              'no amplified-white pixels at ($x,$y) '
              '($r,$g,$b) — premultiplied regression',
        );
      }
    }

    image.dispose();
    bank.dispose();
    rendered.dispose();
    small.dispose();
  });

  test('masked water grid keeps only the light line pixels', () async {
    final image = await decode(content.tryAssetPath('terrain.water')!);
    final grid = await maskWaterGrid(image);
    expect(grid, isNotNull);

    final gridBytes = await grid!.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    int rgbaAt(int x, int y) => gridBytes!.getUint32((y * 128 + x) * 4);

    // A point on the diamond outline carries the light line colour at
    // full alpha; a mid-water point is fully transparent with zeroed
    // colour (valid premultiplied).
    final line = rgbaAt(64, 0); // The north vertex's line pixels.
    expect((line >> 8) & 0xFF, greaterThan(150), reason: 'light blue line');
    expect(line & 0xFF, greaterThan(200), reason: 'near-opaque line');
    final open = rgbaAt(64, 32); // Tile centre, plain water.
    expect(open, 0, reason: 'plain water fully transparent');

    image.dispose();
    grid.dispose();
  });
}

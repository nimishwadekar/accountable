import 'dart:ui' as ui;

import 'package:citysim/content/asset_content_source.dart';
import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/rendering/parcel_world_view.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Render-level regression tests for the composed shore band: the
/// neighbouring land's material blended over the water tile's own
/// art, solid at the tile boundary and faded out by half a tile. The
/// gradient is baked into opaque pixels — binary alpha — because the
/// engines disagree on partial alpha for raw images (Skia reads
/// premultiplied, CanvasKit straight); these tests pin that the
/// guarantee holds on the real art.
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

  test('the band bakes the material fading over the water', () async {
    final grassImage = await decode(content.tryAssetPath('terrain.grass')!);
    final waterImage = await decode(content.tryAssetPath('terrain.water')!);
    final grassData = await grassImage.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    final waterData = await waterImage.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    expect(grassData, isNotNull);
    expect(waterData, isNotNull);
    final grassPixels = grassData!.buffer.asUint8List(
      grassData.offsetInBytes,
      grassData.lengthInBytes,
    );
    final waterPixels = waterData!.buffer.asUint8List(
      waterData.offsetInBytes,
      waterData.lengthInBytes,
    );
    final width = grassImage.width;
    final height = grassImage.height;
    final out = composeShoreBandPixels(
      {'grass': grassPixels},
      waterPixels,
      shoreBandLands('g.......'),
      width,
      height,
    );

    int alphaAt(int x, int y) => out[(y * width + x) * 4 + 3];

    // Solid at the boundary: a window around (90,18) sits ~5px from
    // the middle of the edge shared with the north land.
    var strongest = 0;
    for (var y = 14; y <= 22; y++) {
      for (var x = 86; x <= 94; x++) {
        if (alphaAt(x, y) > strongest) strongest = alphaAt(x, y);
      }
    }
    expect(
      strongest,
      255,
      reason: 'the tile boundary is solid land — binary alpha',
    );

    // Gone by half a tile: the centre is ~29px from the shore, and
    // the open-water half stays water.
    expect(
      alphaAt(width ~/ 2, height ~/ 2),
      0,
      reason: 'the band ends by half a tile',
    );
    expect(alphaAt(64, 44), 0, reason: 'the open half stays water');

    // The waterline is a gradient: many pixels sit genuinely between
    // the two materials (water blue ≈ 188, grass blue ≈ 80 — mid
    // blends land between).
    var midBand = 0;
    for (var i = 0; i < width * height; i++) {
      if (out[i * 4 + 3] == 255 &&
          out[i * 4 + 2] > 95 &&
          out[i * 4 + 2] < 175) {
        midBand++;
      }
    }
    expect(midBand, greaterThan(100), reason: 'the waterline is a gradient');

    // Either art's unpainted pixels never contribute: where the land
    // or the water tile is transparent — the jagged diamond fringes —
    // the overlay stays transparent and the chunk shows through.
    var fringeLeaks = 0;
    for (var i = 0; i < width * height; i++) {
      if ((grassPixels[i * 4 + 3] == 0 || waterPixels[i * 4 + 3] == 0) &&
          out[i * 4 + 3] > 0) {
        fringeLeaks++;
      }
    }
    expect(fringeLeaks, 0, reason: 'the art fringes stay as drawn');

    // And every painted colour is a mix of the two materials —
    // nothing invented, nothing stacked.
    var colorMismatches = 0;
    for (var i = 0; i < width * height; i++) {
      if (out[i * 4 + 3] != 255) continue;
      for (var ch = 0; ch < 3; ch++) {
        final land = grassPixels[i * 4 + ch];
        final water = waterPixels[i * 4 + ch];
        final mixed = out[i * 4 + ch];
        final low = (land < water ? land : water) - 2;
        final high = (land < water ? water : land) + 2;
        if (mixed < low || mixed > high) {
          colorMismatches++;
          break;
        }
      }
    }
    expect(
      colorMismatches,
      0,
      reason: 'every band colour is a mix of the two materials',
    );

    grassImage.dispose();
    waterImage.dispose();
  });
}

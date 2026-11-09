import 'dart:ui' as ui;

import 'package:citysim/content/asset_content_source.dart';
import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/rendering/parcel_world_view.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Render-level regression tests for the composed shore banks: the
/// ground material cut by the baked shape mask. The mask is opaque in
/// places the pack's material never painted (a jagged transparent
/// fringe along its diamond edges) — without the RGB repair inside
/// [composeShoreBank] those pixels draw solid black along the bank's
/// borders. The output bytes feed a premultiplied-alpha descriptor,
/// so RGB must scale with the mask alpha.
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

  test('banks are the material cut by the mask, without black edges', () async {
    final material = await decode(content.tryAssetPath('terrain.grass')!);
    final maskImage = await decode(content.tryAssetPath('shore.quarter.sw')!);
    final bank = await composeShoreBank(material, maskImage);
    expect(bank, isNotNull);

    final bankBytes = await bank!.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    final maskBytes = await maskImage.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    expect(bankBytes, isNotNull);
    expect(maskBytes, isNotNull);
    final pixels = bankBytes!.buffer.asUint8List(
      bankBytes.offsetInBytes,
      bankBytes.lengthInBytes,
    );
    final maskPixels = maskBytes!.buffer.asUint8List(
      maskBytes.offsetInBytes,
      maskBytes.lengthInBytes,
    );

    // The land half draws the material at the mask's full opacity —
    // (90,14) sits on the material's flattened edge band (flat grass,
    // no speckle) inside quarter.sw's land.
    final land = (90 * 4) + (14 * 128 * 4);
    expect(pixels[land + 3], 255, reason: 'land is opaque');
    expect(pixels[land + 1] > pixels[land], isTrue, reason: 'green grass');
    expect(pixels[land], greaterThan(140), reason: 'not black, not white');

    // The waterline keeps its greyscale gradient: alpha follows the
    // mask's partial value and the colour stays the material's.
    final ramp = (64 * 4) + (37 * 128 * 4);
    expect(pixels[ramp + 3], maskPixels[ramp], reason: 'waterline alpha');
    expect(
      pixels[ramp + 3],
      inInclusiveRange(1, 254),
      reason: 'waterline is partial',
    );
    expect(
      pixels[ramp + 1] > pixels[ramp + 2],
      isTrue,
      reason: 'material colour through the ramp',
    );

    // The open water half is fully transparent.
    final water = (64 * 4) + (44 * 128 * 4);
    expect(pixels[water + 3], 0, reason: 'water half shows the water tile');

    // No black edges: wherever the bank has coverage, the colour must
    // come from the material, never from unpainted transparency.
    var blackLeaks = 0;
    for (var i = 0; i < pixels.length; i += 4) {
      if (pixels[i + 3] > 40 &&
          pixels[i] < 30 &&
          pixels[i + 1] < 30 &&
          pixels[i + 2] < 30) {
        blackLeaks++;
      }
    }
    expect(
      blackLeaks,
      0,
      reason: 'mask must never expose unpainted (black) material',
    );

    material.dispose();
    maskImage.dispose();
    bank.dispose();
  });
}

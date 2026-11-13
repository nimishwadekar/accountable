import 'dart:ui' as ui;

import 'package:citysim/content/asset_content_source.dart';
import 'package:citysim/content/content_bundle.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The ground tiles' edge contract: solid diamonds, straight tops,
/// skirted bottoms.
///
/// Every ground tile is fully opaque inside its mathematical diamond
/// and carries no opaque art past the diamond's two top edges (the
/// north-west and north-east canvas corners). Under the chunk's
/// back-to-front painter order a tile's top fringe draws over its
/// earlier-drawn north/west neighbours — the offset that showed on
/// concrete pads — while the bottom skirts stay hidden underneath the
/// later south/east neighbours and seal the seams from below:
/// anti-aliasing at tile and parcel seams blends against them instead
/// of the background. Removing the tops is safe only because the
/// diamonds are solid, so both halves of the contract are pinned.
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

  test('ground tiles are solid diamonds with straight tops', () async {
    const roles = [
      'terrain.grass',
      'terrain.grass.puddle',
      'terrain.water',
      'terrain.dirt',
      'terrain.asphalt',
      'terrain.concrete',
      'terrain.fog',
    ];
    for (final role in roles) {
      final path = content.tryAssetPath(role);
      expect(path, isNotNull, reason: '$role resolves to an asset');
      final image = await decode(path!);
      expect(image.width, 128, reason: '$role canvas width');
      expect(image.height, 64, reason: '$role canvas height');
      final data = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      expect(data, isNotNull, reason: '$role decodes');
      final px = data!.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );

      var solidInside = 0;
      var bottomSkirt = 0;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final alpha = px[(y * image.width + x) * 4 + 3];
          final s =
              (x + 0.5 - image.width / 2).abs() / (image.width / 2) +
              (y + 0.5 - image.height / 2).abs() / (image.height / 2);
          if (s <= 1) {
            expect(
              alpha,
              255,
              reason: '$role must be opaque inside its diamond at ($x,$y)',
            );
            solidInside++;
          } else if (y + 0.5 < image.height / 2) {
            expect(
              alpha,
              0,
              reason:
                  '$role must carry no top fringe past its north-west and '
                  'north-east edges at ($x,$y)',
            );
          } else if (alpha > 0) {
            bottomSkirt++;
          }
        }
      }
      expect(solidInside, 4096, reason: '$role covers its whole diamond');
      expect(
        bottomSkirt,
        greaterThan(400),
        reason: '$role keeps its bottom skirt — it seals the seams',
      );
      image.dispose();
    }
  });
}

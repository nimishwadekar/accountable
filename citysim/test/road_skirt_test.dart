/// Pins the road and bridge sprite skirts.
///
/// Road tiles tessellate edge to edge along their connections, and
/// bilinear resampling left their combined coverage under 100%, so
/// the terrain beneath showed through as thin lines between road
/// tiles (and water through bridge deck seams) — the same texture
/// bleeding the ground tiles had. The sprites now carry a ~4-art-px
/// opaque skirt past their connection edges, filled from the
/// nearest opaque pixel.
///
/// Skirts exist ONLY on the bottom edges — bottom-right (toward the
/// east neighbour) and bottom-left (toward the south neighbour).
/// Tiles draw back-to-front in row-major order, so only those
/// neighbours draw later and cover the skirt; a top-edge skirt would
/// paint over the already-drawn west/north neighbour (which is what
/// the first attempt did). Top-facing seams need no skirt: every
/// west/north seam is also the neighbour's east/south seam, and that
/// neighbour's bottom skirt is the opaque backing under our softened
/// edge.
///
/// These tests assert, per sprite, that skirt pixels exist beyond
/// the bottom cut lines for exactly the expected directions and
/// that nothing exists beyond the top cut lines. The cut lines in
/// the 128-wide art (diamond vertices N(64,0) E(128,32) S(64,64)
/// W(0,32)):
///   E zone beyond x + 2y > 192 (SE edge, bottom-right)
///   S zone beyond x - 2y < -64 (SW edge, bottom-left)
///   N zone beyond x - 2y > 64   (NE edge, top-right)
///   W zone beyond x + 2y < 64   (NW edge, top-left)
library;

import 'dart:ui' as ui;

import 'package:citysim/content/asset_content_source.dart';
import 'package:citysim/content/content_bundle.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

/// Skirt directions per road role: the role's open directions
/// filtered to the bottom edges (E, S). Roles whose only
/// connections face west or north carry no skirt at all — their
/// seams are sealed by the neighbours' bottom skirts.
const roadSkirtDirections = <String, String>{
  'road.end.sw': '',
  'road.end.nw': 'E',
  'road.end.ne': 'S',
  'road.end.se': '',
  'road.straight.se': 'E',
  'road.straight.sw': 'S',
  'road.corner.w': 'E',
  'road.corner.n': 'S',
  'road.corner.e': 'S',
  'road.corner.s': 'E',
  'road.t.sw': 'ES',
  'road.t.nw': 'S',
  'road.t.ne': 'E',
  'road.t.se': 'ES',
  'road.cross': 'ES',
};

/// Opaque-pixel counts beyond each cut line, per role.
typedef _Zones = ({int east, int south, int north, int west});

Future<_Zones> _zonesOf(String role, ContentBundle content) async {
  final path = content.tryAssetPath(role)!.replaceFirst('assets/', '');
  final data = await rootBundle.load('assets/$path');
  final codec = await ui.instantiateImageCodec(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
  final image = (await codec.getNextFrame()).image;
  final bytes = await image.toByteData();
  final px = bytes!.buffer.asUint8List(
    bytes.offsetInBytes,
    bytes.lengthInBytes,
  );
  var east = 0, south = 0, north = 0, west = 0;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (px[(y * image.width + x) * 4 + 3] == 0) continue;
      final fx = x + 0.5, fy = y + 0.5;
      if (fx + 2 * fy > 196) east++;
      if (fx - 2 * fy < -68) south++;
      if (fx - 2 * fy > 70) north++;
      if (fx + 2 * fy < 54) west++;
    }
  }
  image.dispose();
  codec.dispose();
  return (east: east, south: south, north: north, west: west);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ContentBundle content;
  final zones = <String, _Zones>{};
  setUpAll(() async {
    content = await loadContentBundle(const AssetContentSource());
    for (final role in roadSkirtDirections.keys) {
      zones[role] = await _zonesOf(role, content);
    }
    for (final role in [
      'bridge.body.se',
      'bridge.body.sw',
      'bridge.ramp.nw',
      'bridge.ramp.ne',
      'bridge.ramp.se',
      'bridge.ramp.sw',
    ]) {
      zones[role] = await _zonesOf(role, content);
    }
  });

  test('road sprites skirt exactly their bottom connection edges', () {
    for (final entry in roadSkirtDirections.entries) {
      final role = entry.key;
      final wantsEast = entry.value.contains('E');
      final wantsSouth = entry.value.contains('S');
      final z = zones[role]!;
      expect(
        z.east,
        wantsEast ? greaterThan(30) : 0,
        reason:
            '$role east skirt zone: '
            '${wantsEast ? 'must have' : 'must not have'} skirt '
            'pixels, got ${z.east}',
      );
      expect(
        z.south,
        wantsSouth ? greaterThan(30) : 0,
        reason:
            '$role south skirt zone: '
            '${wantsSouth ? 'must have' : 'must not have'} skirt '
            'pixels, got ${z.south}',
      );
      // No sprite may skirt a top edge: those skirts paint over the
      // already-drawn west/north neighbours.
      expect(
        z.north,
        0,
        reason:
            '$role must not skirt its top-right edge '
            '(would paint over the north neighbour), got ${z.north}',
      );
      expect(
        z.west,
        0,
        reason:
            '$role must not skirt its top-left edge '
            '(would paint over the west neighbour), got ${z.west}',
      );
    }
  });

  test('bridge sprites skirt the bottom cut along their span', () {
    // Bodies skirt the downhill cut; ramps skirt the deck-facing
    // cut; the far ramps carry no skirt (the last deck tile seals
    // their edge). Bridge art legitimately extends beyond the cuts
    // (railings, pillars, the ramp deck), so only the skirted cuts
    // are asserted.
    expect(
      zones['bridge.body.se']!.east,
      greaterThan(150),
      reason: 'east-going deck tiles skirt their east cut',
    );
    expect(
      zones['bridge.body.sw']!.south,
      greaterThan(150),
      reason: 'south-going deck tiles skirt their south cut',
    );
    expect(
      zones['bridge.ramp.nw']!.east,
      greaterThan(100),
      reason:
          'the near ramp of an east-going bridge skirts its '
          'deck-facing (east) cut',
    );
    expect(
      zones['bridge.ramp.ne']!.south,
      greaterThan(100),
      reason:
          'the near ramp of a south-going bridge skirts its '
          'deck-facing (south) cut',
    );
  });
}

import 'dart:typed_data';

import 'package:citysim/rendering/parcel_world_view.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:citysim/world/terrain_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Grid-backed terrain lookup for driving [shoreBandPattern] directly:
/// `#` water, `.` grass, `,` dirt, `a` asphalt, `f` fog. The water
/// cell under test is the grid's centre; the grid reads as drawn —
/// `[north-west, north, north-east]` in the first row, and so on.
TerrainCell Function(CellCoord) terrainFrom(List<String> rows) {
  TerrainCell at(CellCoord cell) {
    final inBounds =
        cell.row >= 0 &&
        cell.row < rows.length &&
        cell.column >= 0 &&
        cell.column < rows[cell.row].length;
    final symbol = inBounds ? rows[cell.row][cell.column] : '#';
    final style = switch (symbol) {
      ',' => GroundStyle.dirt,
      'a' => GroundStyle.asphalt,
      _ => GroundStyle.grass,
    };
    return TerrainCell(
      coord: cell,
      kind: switch (symbol) {
        '#' => TerrainKind.water,
        'f' => TerrainKind.fog,
        _ => TerrainKind.grass,
      },
      groundStyle: style,
    );
  }

  return at;
}

void main() {
  // The centre (1,1) of each 3×3 grid is the water cell under test.
  String? pattern(List<String> rows) =>
      shoreBandPattern(const CellCoord(1, 1), terrainFrom(rows));

  const width = 128, height = 64;
  final grass = _solidMaterial(width, height, 90, 180, 60);
  final dirt = _solidMaterial(width, height, 180, 120, 70);
  final water = _solidMaterial(width, height, 60, 120, 200);

  Uint8List compose(String pattern) => composeShoreBandPixels(
    {'grass': grass, 'dirt': dirt},
    water,
    shoreBandLands(pattern),
    width,
    height,
  );

  int alphaAt(Uint8List pixels, int x, int y) =>
      pixels[(y * width + x) * 4 + 3];

  group('shoreBandPattern', () {
    test('open water and water-or-fog neighbours draw no band', () {
      expect(pattern(['###', '###', '###']), isNull);
      expect(pattern(['#f#', '###', '###']), isNull);
      expect(pattern(['fff', 'f#f', 'fff']), isNull);
    });

    test('each land neighbour marks its compass slot', () {
      // Order: N, NE, E, SE, S, SW, W, NW. The grid reads `#` as
      // water and `.` as land.
      expect(pattern(['#.#', '###', '###']), 'g.......');
      expect(pattern(['##.', '###', '###']), '.g......');
      expect(pattern(['###', '##.', '###']), '..g.....');
      expect(pattern(['###', '###', '##.']), '...g....');
      expect(pattern(['###', '###', '#.#']), '....g...');
      expect(pattern(['###', '###', '.##']), '.....g..');
      expect(pattern(['###', '.##', '###']), '......g.');
      expect(pattern(['.##', '###', '###']), '.......g');
    });

    test('the band material follows the neighbouring land', () {
      expect(pattern(['#,#', '###', '###']), 'd.......');
      // Ground styles without their own band material fall back to
      // grass, matching the rule the bank sprites used.
      expect(pattern(['#a#', '###', '###']), 'g.......');
    });

    test('a surrounded pond bands from every side', () {
      // Deliberately no open-water guard: a one-cell pond reads as a
      // murky shallow, fading to water at its centre — the look the
      // previews settled on.
      expect(pattern(['...', '.#.', '...']), 'gggggggg');
    });
  });

  group('shoreBandLands', () {
    test('patterns without land decode to nothing', () {
      expect(shoreBandLands('........'), isEmpty);
    });

    test('each slot decodes to its cell offset and style', () {
      void expectLand(String pattern, int index, int dc, int dr, String style) {
        final lands = shoreBandLands(pattern);
        expect(lands, hasLength(index + 1));
        expect(lands[index].dc, dc);
        expect(lands[index].dr, dr);
        expect(lands[index].style, style);
      }

      expectLand('g.......', 0, 0, -1, 'grass');
      expectLand('.g......', 0, 1, -1, 'grass');
      expectLand('..g.....', 0, 1, 0, 'grass');
      expectLand('...g....', 0, 1, 1, 'grass');
      expectLand('....g...', 0, 0, 1, 'grass');
      expectLand('.....g..', 0, -1, 1, 'grass');
      expectLand('......g.', 0, -1, 0, 'grass');
      expectLand('.......g', 0, -1, -1, 'grass');

      // Mixed materials decode in compass order.
      final mixed = shoreBandLands('d.g.....');
      expect(mixed, hasLength(2));
      expect(mixed[0].dc, 0);
      expect(mixed[0].dr, -1);
      expect(mixed[0].style, 'dirt');
      expect(mixed[1].dc, 1);
      expect(mixed[1].dr, 0);
      expect(mixed[1].style, 'grass');
    });
  });

  group('composeShoreBandPixels', () {
    test('the gradient is baked into opaque pixels', () {
      final out = compose('g.......');
      // Binary alpha everywhere: the engines disagree on partial
      // alpha for raw images, so the ramp lives in the colour.
      for (var i = 3; i < out.length; i += 4) {
        expect(out[i], anyOf(0, 255), reason: 'alpha must be binary');
      }
      // (90,18) is ~5px from the shared edge — nearly pure grass;
      // (80,24) mid-ramp; the centre (64,32) is ~29px — half a tile —
      // from the shore, and (64,56) beyond the reach entirely.
      expect(alphaAt(out, 90, 18), 255);
      expect(out[(18 * width + 90) * 4 + 1], greaterThan(170));
      expect(alphaAt(out, 80, 24), 255);
      expect(out[(24 * width + 80) * 4 + 1], inInclusiveRange(125, 175));
      expect(alphaAt(out, 64, 32), 0);
      expect(alphaAt(out, 64, 56), 0);
    });

    test('every colour is one mix of the two materials', () {
      final out = compose('g.......');
      // A pixel blended as water*(1-ramp) + grass*ramp implies the
      // same mix fraction from every channel — the colour is exactly
      // these two materials at one shared fraction, never a third
      // colour and never a stacked double blend.
      final i = (24 * width + 80) * 4; // Mid-ramp pixel.
      final rRamp = (out[i] - 60) / (90 - 60);
      final gRamp = (out[i + 1] - 120) / (180 - 120);
      final bRamp = (out[i + 2] - 200) / (60 - 200);
      expect(rRamp, closeTo(gRamp, 0.02));
      expect(gRamp, closeTo(bRamp, 0.02));
      expect(gRamp, inInclusiveRange(0.2, 0.8), reason: 'mid-ramp');
    });

    test('corners reach at least as far as either shore alone', () {
      final north = compose('g.......');
      final east = compose('..g.....');
      final both = compose('g.g.....');
      for (var y = 0; y < height; y += 3) {
        for (var x = 0; x < width; x += 3) {
          final a = alphaAt(north, x, y);
          final b = alphaAt(east, x, y);
          if (a == 255 || b == 255) {
            expect(
              alphaAt(both, x, y),
              255,
              reason: 'pixel ($x,$y): smoothing may extend, never retract',
            );
          }
        }
      }
    });

    test('concave creases round like convex tips', () {
      // Land north and east flank a wedge of water at the cell's east
      // vertex; their distance fields meet in a crease along the
      // horizontal midline (the configuration is symmetric about it).
      // The smooth-minimum dips the field at the crease, so the blend
      // reaches deeper than either shore alone and the water spike's
      // tip rounds instead of ending in a sharp point.
      final north = compose('g.......');
      final both = compose('g.g.....');
      var rounded = 0; // Crease pixels rendered more land-ward.
      var extended = 0; // Crease pixels beyond either shore's reach.
      for (var x = 8; x < 120; x++) {
        const y = 32;
        final i = (y * width + x) * 4;
        final singleAlpha = north[i + 3];
        final singleGreen = north[i + 1];
        final bothAlpha = both[i + 3];
        final bothGreen = both[i + 1];
        if (singleAlpha == 255 &&
            bothAlpha == 255 &&
            bothGreen > singleGreen + 2) {
          rounded++;
        }
        if (singleAlpha == 0 && bothAlpha == 255) {
          extended++;
        }
      }
      expect(rounded, greaterThan(5), reason: 'the crease blend deepens');
      expect(
        extended,
        greaterThan(3),
        reason: 'the spike tip rounds past the plain reach',
      );
    });

    test("each pixel takes its nearest land's material", () {
      final out = compose('d.g.....'); // dirt north, grass east.
      // Near the north edge the band is dirt (red over blue); near
      // the east edge it is grass (green over blue).
      expect(alphaAt(out, 90, 18), 255);
      expect(
        out[(18 * width + 90) * 4],
        greaterThan(out[(18 * width + 90) * 4 + 2]),
      );
      expect(alphaAt(out, 92, 46), 255);
      expect(
        out[(46 * width + 92) * 4 + 1],
        greaterThan(out[(46 * width + 92) * 4]),
      );
    });

    test("the band never leaves its own cell's diamond", () {
      // Land to the south. The overlay draws above the whole chunk
      // layer, so anything it paints past its own diamond lands on
      // top of the south/east neighbours — their foundations, roads,
      // props — instead of under them. The synthetic materials are
      // opaque everywhere, so only the diamond rule keeps these
      // spillover pixels empty.
      final out = compose('....g...');
      // Inside the diamond near the shared SW edge: the band is there.
      expect(alphaAt(out, 34, 46), 255);
      // Outside the diamond — the water tile's bottom-skirt zone,
      // inside the south neighbour's territory and within reach of
      // its land: the band must stay out.
      expect(alphaAt(out, 30, 50), 0);
      expect(alphaAt(out, 40, 58), 0);
    });

    test("either art's unpainted fringe stays as the chunk drew it", () {
      final landPixels = _solidMaterial(width, height, 90, 180, 60);
      landPixels[(18 * width + 90) * 4 + 3] = 0; // Land hole near the shore.
      final out = composeShoreBandPixels(
        {'grass': landPixels},
        water,
        shoreBandLands('g.......'),
        width,
        height,
      );
      expect(alphaAt(out, 90, 18), 0);

      final waterPixels = _solidMaterial(width, height, 60, 120, 200);
      waterPixels[(18 * width + 90) * 4 + 3] = 0; // Water hole.
      final out2 = composeShoreBandPixels(
        {'grass': grass},
        waterPixels,
        shoreBandLands('g.......'),
        width,
        height,
      );
      expect(alphaAt(out2, 90, 18), 0);
    });
  });
}

Uint8List _solidMaterial(int width, int height, int r, int g, int b) {
  final pixels = Uint8List(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    pixels[i * 4] = r;
    pixels[i * 4 + 1] = g;
    pixels[i * 4 + 2] = b;
    pixels[i * 4 + 3] = 255;
  }
  return pixels;
}

import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/rendering/parcel_world_view.dart';
import 'package:citysim/world/world_queries.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('facingArtKey', () {
    test('north/south roads draw the left variant, east/west the right', () {
      expect(facingArtKey('north'), 'left');
      expect(facingArtKey('south'), 'left');
      expect(facingArtKey('east'), 'right');
      expect(facingArtKey('west'), 'right');
    });
  });

  group('facingForRoadSides', () {
    test('door-on-road sides beat around-the-corner ones', () {
      expect(facingForRoadSides({'east', 'north'}), 'east');
      expect(facingForRoadSides({'north'}), 'north');
      expect(facingForRoadSides({'south', 'west'}), 'south');
      expect(facingForRoadSides({'west'}), 'west');
      expect(facingForRoadSides({'east', 'south', 'west'}), 'south');
      expect(facingForRoadSides({'north', 'south'}), 'south');
      expect(facingForRoadSides({'east', 'west'}), 'east');
    });

    test('no frontage falls back to the south default', () {
      expect(facingForRoadSides(<String>{}), 'south');
    });
  });

  group('flipFacing', () {
    test('flips to the best side of the other art variant', () {
      expect(flipFacing('east', {'east', 'south'}), 'south');
      expect(flipFacing('north', {'north', 'south', 'west'}), 'west');
      expect(flipFacing('east', {'east', 'north', 'west'}), 'north');
      expect(flipFacing('south', {'east', 'south'}), 'east');
      expect(flipFacing('west', {'west', 'north'}), 'north');
    });

    test('same-variant sides are never swap targets', () {
      // South and north share the left variant, east and west the
      // right: nothing to flip to, so the fallback arm keeps the flip
      // total. Callers never offer the swap without both variants
      // present, so these arms only fire through direct calls.
      expect(flipFacing('south', {'south', 'north'}), 'east');
      expect(flipFacing('east', {'east', 'west'}), 'south');
    });
  });

  group('facingPullOffset', () {
    test('pulls along the road side screen diagonal, per tile', () {
      // One tile toward a side runs half a tile across and a quarter
      // tile down — the tile itself is 64×32 logical units.
      expect(facingPullOffset('north', 1), const Offset(32, -16));
      expect(facingPullOffset('east', 1), const Offset(32, 16));
      expect(facingPullOffset('south', 1), const Offset(-32, 16));
      expect(facingPullOffset('west', 1), const Offset(-32, -16));
    });

    test('offsets scale, zero stays put, negative pushes away', () {
      expect(facingPullOffset('east', 0.25), const Offset(8, 4));
      expect(facingPullOffset('south', 0), Offset.zero);
      expect(facingPullOffset('east', -0.5), const Offset(-16, -8));
    });
  });
}

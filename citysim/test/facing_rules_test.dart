import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/rendering/parcel_world_view.dart';
import 'package:citysim/world/world_queries.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('facingHalf', () {
    test('north/east map to the right art variant, south/west to left', () {
      expect(facingHalf('north'), 'right');
      expect(facingHalf('east'), 'right');
      expect(facingHalf('south'), 'left');
      expect(facingHalf('west'), 'left');
    });
  });

  group('facingForRoadSides', () {
    test('visible facade sides beat around-the-corner ones', () {
      expect(facingForRoadSides({'east', 'north'}), 'east');
      expect(facingForRoadSides({'north'}), 'north');
      expect(facingForRoadSides({'south', 'west'}), 'south');
      expect(facingForRoadSides({'west'}), 'west');
      expect(facingForRoadSides({'east', 'south', 'west'}), 'east');
    });

    test('no frontage falls back to the south default', () {
      expect(facingForRoadSides(<String>{}), 'south');
    });
  });

  group('flipFacing', () {
    test('flips to the best side of the other screen half', () {
      expect(flipFacing('east', {'east', 'south'}), 'south');
      expect(flipFacing('north', {'north', 'south', 'west'}), 'south');
      expect(flipFacing('east', {'east', 'north', 'west'}), 'west');
      expect(flipFacing('south', {'east', 'south'}), 'east');
      expect(flipFacing('west', {'west', 'north'}), 'north');
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

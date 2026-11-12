import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/rendering/parcel_world_view.dart';
import 'package:citysim/world/world_content.dart';
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

  group('facingQuarterTurns', () {
    test('east/west door sides turn the lot, north/south keep it', () {
      expect(facingQuarterTurns('east'), 1);
      expect(facingQuarterTurns('west'), 1);
      expect(facingQuarterTurns('north'), 0);
      expect(facingQuarterTurns('south'), 0);
      expect(facingQuarterTurns(null), 0);
    });
  });

  group('sideShiftOffset', () {
    test('col runs east (down-right), row south (down-left)', () {
      // One axis at a time, at a drawn width of 64: a quarter of the
      // width along the column axis is (16, 8); along the row axis it
      // is (-16, 8).
      expect(
        sideShiftOffset(
          const SpriteDefinition(sideShifts: {'south': (0.25, 0)}),
          'south',
          64,
        ),
        const Offset(16, 8),
      );
      expect(
        sideShiftOffset(
          const SpriteDefinition(sideShifts: {'north': (0, 0.25)}),
          'north',
          64,
        ),
        const Offset(-16, 8),
        reason: 'the row axis runs along the screen down-left diagonal',
      );
    });

    test('both axes together move straight down, negatives invert', () {
      expect(
        sideShiftOffset(
          const SpriteDefinition(sideShifts: {'east': (0.25, 0.25)}),
          'east',
          64,
        ),
        const Offset(0, 16),
        reason: 'equal col and row collapse to a straight screen drop',
      );
      expect(
        sideShiftOffset(
          const SpriteDefinition(sideShifts: {'west': (-0.25, 0)}),
          'west',
          64,
        ),
        const Offset(-16, -8),
      );
    });

    test('no facing or no entry keeps the anchor placement', () {
      expect(sideShiftOffset(const SpriteDefinition(), null, 64), Offset.zero);
      expect(
        sideShiftOffset(const SpriteDefinition(), 'south', 64),
        Offset.zero,
        reason: 'a side with no entry keeps the anchor placement',
      );
    });
  });
}

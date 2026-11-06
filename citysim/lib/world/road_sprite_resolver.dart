import 'coordinates.dart';

const roadNorth = 1;
const roadEast = 2;
const roadSouth = 4;
const roadWest = 8;

int roadNeighborMask(CellCoord cell, Set<CellCoord> roadCells) {
  var mask = 0;
  if (roadCells.contains(cell.offset(0, -1))) mask |= roadNorth;
  if (roadCells.contains(cell.offset(1, 0))) mask |= roadEast;
  if (roadCells.contains(cell.offset(0, 1))) mask |= roadSouth;
  if (roadCells.contains(cell.offset(-1, 0))) mask |= roadWest;
  return mask;
}

/// Sprite roles are named for where the piece visually points (the rounded
/// cap of an end tile, the elbow of a corner), which is opposite the edge
/// that stays open for connection. Openings were verified against the
/// supplied sprite pixels:
/// - end_X is open on the edge opposite X;
/// - corner_X is open on the two edges away from X;
/// - straight_X is open along its own axis;
/// - intersection_X is missing the X arm.
String roadSpriteRole(int mask) {
  final normalized = mask & 0x0F;
  if (normalized == 0) return 'road.end.se';
  if (_countBits(normalized) == 1) {
    return switch (normalized) {
      roadNorth => 'road.end.sw',
      roadEast => 'road.end.nw',
      roadSouth => 'road.end.ne',
      roadWest => 'road.end.se',
      _ => 'road.end.se',
    };
  }
  if (normalized == (roadEast | roadWest)) return 'road.straight.se';
  if (normalized == (roadNorth | roadSouth)) return 'road.straight.sw';
  if (normalized == (roadNorth | roadEast)) return 'road.corner.w';
  if (normalized == (roadEast | roadSouth)) return 'road.corner.n';
  if (normalized == (roadSouth | roadWest)) return 'road.corner.e';
  if (normalized == (roadWest | roadNorth)) return 'road.corner.s';
  if (normalized == 0x0F) return 'road.cross';
  if ((normalized & roadNorth) == 0) return 'road.t.sw';
  if ((normalized & roadEast) == 0) return 'road.t.nw';
  if ((normalized & roadSouth) == 0) return 'road.t.ne';
  return 'road.t.se';
}

/// The ramp at a bridge end. Ramp sprites are named for the screen
/// direction their deck descends toward, so the bank where the road
/// continues must get the ramp that descends toward it: the west bank
/// of an east-going span rises toward the water, which is the ramp
/// named for the far side.
String bridgeRampRole(CellCoord nearBank, CellCoord spanCell) {
  final dx = spanCell.column - nearBank.column;
  final dy = spanCell.row - nearBank.row;
  if (dx > 0) return 'bridge.ramp.nw';
  if (dx < 0) return 'bridge.ramp.se';
  if (dy > 0) return 'bridge.ramp.ne';
  return 'bridge.ramp.sw';
}

String bridgeBodyRole(CellCoord nearBank, CellCoord farBank) =>
    nearBank.column == farBank.column ? 'bridge.body.sw' : 'bridge.body.se';

int _countBits(int value) {
  var bits = 0;
  for (var remaining = value; remaining != 0; remaining &= remaining - 1) {
    bits++;
  }
  return bits;
}

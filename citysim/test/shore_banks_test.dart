import 'package:citysim/rendering/parcel_world_view.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:citysim/world/terrain_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Grid-backed terrain lookup for driving [waterBankRoles] directly:
/// `#` water, `.` grass, `,` dirt, `a` asphalt. The water cell under
/// test is the grid's centre; the grid reads as drawn —
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
      kind: symbol == '#' ? TerrainKind.water : TerrainKind.grass,
      groundStyle: style,
    );
  }

  return at;
}

void main() {
  // The centre (1,1) of each 3×3 grid is the water cell under test.
  List<String> banks(List<String> rows) =>
      waterBankRoles(const CellCoord(1, 1), terrainFrom(rows));

  test('open water and one-cell ponds draw no banks', () {
    expect(banks(['###', '###', '###']), isEmpty);
    expect(banks(['...', '.#.', '...']), isEmpty);
  });

  test('a single land neighbour banks the half facing it', () {
    expect(banks(['#.#', '###', '###']), ['shore.grass.quarter.sw']);
    expect(banks(['###', '##.', '###']), ['shore.grass.quarter.nw']);
    expect(banks(['###', '###', '#.#']), ['shore.grass.quarter.ne']);
    expect(banks(['###', '.##', '###']), ['shore.grass.quarter.se']);
  });

  test('the bank style follows the neighbouring land', () {
    expect(banks(['#,#', '###', '###']), ['shore.dirt.quarter.sw']);
    // Ground styles without their own shore family fall back to grass,
    // matching the land-side rule the banks mirror.
    expect(banks(['#a#', '###', '###']), ['shore.grass.quarter.sw']);
  });

  test('two adjacent land neighbours leave one water wedge', () {
    // Land north and east meets at the east vertex; the water wedge
    // remains at the west vertex, so the corner piece there carries
    // the bank around it.
    expect(banks(['#.#', '##.', '###']), ['shore.grass.corner.w']);
    expect(banks(['###', '##.', '#.#']), ['shore.grass.corner.n']);
    expect(banks(['###', '.##', '#.#']), ['shore.grass.corner.e']);
    expect(banks(['#.#', '.##', '###']), ['shore.grass.corner.s']);
    // The pair's style comes from the first neighbour in
    // north/east/south/west order.
    expect(banks(['#,#', '##.', '###']), ['shore.dirt.corner.w']);
  });

  test('diagonal-only land gets a bank wedge at the shared vertex', () {
    // Land at the up-left diagonal shares the north vertex; the bank
    // wedge comes from the edge piece whose grass sits there.
    expect(banks(['.##', '###', '###']), ['shore.grass.edge.s']);
    expect(banks(['##.', '###', '###']), ['shore.grass.edge.w']);
    expect(banks(['###', '###', '##.']), ['shore.grass.edge.n']);
    expect(banks(['###', '###', '.##']), ['shore.grass.edge.e']);
    // Two diagonals around the same empty cardinal side both wedge.
    expect(banks(['.#.', '###', '###']), [
      'shore.grass.edge.s',
      'shore.grass.edge.w',
    ]);
  });

  test('a cardinal bank covers the vertex a diagonal would reach', () {
    // Land north banks the north-east half, which already contains
    // the north vertex the up-left diagonal would wedge into.
    expect(banks(['..#', '###', '###']), ['shore.grass.quarter.sw']);
  });

  test('opposite land neighbours bank both halves between them', () {
    expect(banks(['#.#', '###', '#.#']), [
      'shore.grass.quarter.sw',
      'shore.grass.quarter.ne',
    ]);
    expect(banks(['###', '.#.', '###']), [
      'shore.grass.quarter.nw',
      'shore.grass.quarter.se',
    ]);
  });
}

/// The four sheets that store a parcel world — the analogue of the main
/// app's table schemas, and the shape of the future Google Spreadsheet.
///
/// Storage is state, not history: `UserData` holds the world's scalar
/// fields as key/value rows, `Tiles` holds one row per coordinate the
/// player has touched (roads, bridges, structures — keyed by global tile
/// x/y), `OwnedParcels` holds owned parcel coordinates, and `Projects` holds
/// currently active construction projects only (rows are deleted as
/// projects finish). Everything else — terrain, footprints, bridge spans,
/// unlocks, entity counters — derives from codebase content and the
/// tables themselves. No versions are stored anywhere; content edits are
/// live updates validated against the current save by the editors.
library;

import 'package:csv/csv.dart';

class SheetTables {
  const SheetTables({
    this.userData = const {},
    this.tiles = const [],
    this.ownedParcels = const [],
    this.projects = const [],
  });

  /// Scalar world fields: seed, coins, dates, check-in state.
  final Map<String, String> userData;

  /// Rows of `x, y, kind, status, detail, variant, facing, project`.
  final List<List<String>> tiles;

  /// Rows of `x, y` — owned parcel coordinates (parcel space).
  final List<List<String>> ownedParcels;

  /// Rows of `id, kind, detail, target, funded` — active projects only.
  final List<List<String>> projects;

  bool get isEmpty =>
      userData.isEmpty &&
      tiles.isEmpty &&
      ownedParcels.isEmpty &&
      projects.isEmpty;
}

/// Header rows define each sheet's layout; the same headers go into the
/// real Google Spreadsheet and the bundled CSV fixtures.
const userDataHeaders = <String>['key', 'value'];
const tilesHeaders = <String>[
  'x',
  'y',
  'kind',
  'status',
  'detail',
  'variant',
  'facing',
  'project',
];
const ownedParcelsHeaders = <String>['x', 'y'];
const projectsHeaders = <String>['id', 'kind', 'detail', 'target', 'funded'];

const userDataSheetName = 'UserData';
const tilesSheetName = 'Tiles';
const ownedParcelsSheetName = 'OwnedParcels';
const projectsSheetName = 'Projects';

/// Parses one CSV document (header row + data rows) into string rows.
/// Dynamic typing stays off: every cell is a string, exactly as stored.
List<List<String>> decodeCsvRows(String text) {
  final rows = csv
      .decode(text)
      .map((row) => row.map((cell) => '$cell').toList())
      .toList();
  if (rows.isEmpty) return const [];
  return rows.skip(1).toList();
}

/// Encodes string rows into a CSV document with the given header row.
String encodeCsvRows(List<String> headers, List<List<String>> rows) =>
    csv.encode([headers, ...rows]);

/// Reads a bundle of the four sheets from raw CSV documents. Missing
/// documents are treated as empty tables.
SheetTables decodeSheetTables({
  String userData = '',
  String tiles = '',
  String ownedParcels = '',
  String projects = '',
}) => SheetTables(
  userData: {
    for (final row in decodeCsvRows(userData))
      if (row.length >= 2 && row[0].isNotEmpty) row[0]: row[1],
  },
  tiles: _padRows(decodeCsvRows(tiles), tilesHeaders.length),
  ownedParcels: _padRows(
    decodeCsvRows(ownedParcels),
    ownedParcelsHeaders.length,
  ),
  projects: _padRows(decodeCsvRows(projects), projectsHeaders.length),
);

/// Encodes the four sheets back into CSV documents.
Map<String, String> encodeSheetTables(SheetTables tables) => {
  userDataSheetName: encodeCsvRows(userDataHeaders, [
    for (final entry
        in tables.userData.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)))
      [entry.key, entry.value],
  ]),
  tilesSheetName: encodeCsvRows(tilesHeaders, tables.tiles),
  ownedParcelsSheetName: encodeCsvRows(
    ownedParcelsHeaders,
    tables.ownedParcels,
  ),
  projectsSheetName: encodeCsvRows(projectsHeaders, tables.projects),
};

/// Normalizes row width so short hand-edited rows still line up with the
/// header layout.
List<List<String>> _padRows(List<List<String>> rows, int width) => [
  for (final row in rows) [...row, for (var i = row.length; i < width; i++) ''],
];

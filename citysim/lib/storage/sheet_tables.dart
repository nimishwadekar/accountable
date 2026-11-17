/// The six sheets that store the parcel-world save — the analogue of
/// the main app's table schemas, and the shape of the future Google
/// Spreadsheet.
///
/// Storage is state, not history. `Cities` is the index — one row per
/// city with a stable id, a mutable display name, and the founded
/// date — and every other sheet holds one row per fact **with a
/// leading `city_id` column**, in city-major blocks (rows grouped by
/// ascending city id, stable within a city). Inside the codec a
/// city's rows shed that column and become a plain [SheetTables] —
/// the per-city shape the game core already reads, so the reducer,
/// rules, and validation never learn that cities exist.
///
/// `UserData` holds each city's scalar fields as city/key/value rows,
/// `Tiles` one row per coordinate the player has touched (roads,
/// bridges, buildings — keyed by global tile x/y), `Props` placed
/// decorations at subtile positions (several per tile),
/// `OwnedParcels` owned parcel coordinates — exclusive across
/// cities; the decode fails if two cities hold the same parcel — and
/// `Projects` active construction projects only (rows are deleted as
/// projects finish, and the `Tiles` project column names a live
/// project only). Everything else — terrain, footprints, bridge
/// spans, unlocks, entity counters — derives from codebase content
/// and the tables themselves. No versions are stored anywhere and
/// there is no migration code: the game reads exactly this schema,
/// fails visibly on any other shape, and saves are converted by hand
/// when the schema changes.
library;

import 'package:csv/csv.dart';

class SheetTables {
  const SheetTables({
    this.userData = const {},
    this.tiles = const [],
    this.props = const [],
    this.ownedParcels = const [],
    this.projects = const [],
  });

  /// Scalar world fields: seed, coins, dates, check-in state.
  final Map<String, String> userData;

  /// Rows of `x, y, kind, status, detail, variant, facing, project`.
  final List<List<String>> tiles;

  /// Rows of `x, y, subtile_x, subtile_y, model, variant, facing` —
  /// placed decoration props; several may share a tile at different
  /// subtiles.
  final List<List<String>> props;

  /// Rows of `x, y` — owned parcel coordinates (parcel space).
  final List<List<String>> ownedParcels;

  /// Rows of `id, kind, detail, target, funded` — active projects only.
  final List<List<String>> projects;

  bool get isEmpty =>
      userData.isEmpty &&
      tiles.isEmpty &&
      props.isEmpty &&
      ownedParcels.isEmpty &&
      projects.isEmpty;
}

/// One city in the index: a stable id (`city_1`, `city_2`, …), a
/// mutable display name — "city" is the schema term and says nothing
/// about size; a village is a city — and the founded date as a
/// `YYYY-MM-DD` key.
class CityRecord {
  const CityRecord({
    required this.id,
    required this.name,
    required this.founded,
  });

  final String id;
  final String name;
  final String founded;
}

/// The whole save: the city index plus every city's five sheets.
/// Rows in [tablesById] carry no city column — the partition already
/// happened; [encodeMultiCityTables] stamps it back as the leading
/// column in city-major blocks.
class MultiCityTables {
  const MultiCityTables({this.cities = const [], this.tablesById = const {}});

  final List<CityRecord> cities;
  final Map<String, SheetTables> tablesById;

  bool get isEmpty =>
      cities.isEmpty && tablesById.values.every((tables) => tables.isEmpty);

  /// The id a newly founded city takes: one past the highest existing
  /// number. Cities are never deleted or retired, so this never
  /// collides and never reuses an id.
  String nextCityId() {
    var highest = 0;
    for (final id in tablesById.keys) {
      final number = cityIdNumber(id);
      if (number > highest) highest = number;
    }
    for (final record in cities) {
      final number = cityIdNumber(record.id);
      if (number > highest) highest = number;
    }
    return 'city_${highest + 1}';
  }

  /// The tables with a city's block replaced (the index unchanged).
  MultiCityTables withCityTables(String cityId, SheetTables tables) =>
      MultiCityTables(
        cities: cities,
        tablesById: {...tablesById, cityId: tables},
      );

  /// The tables with a new or replaced index record. Records stay
  /// sorted by ascending id.
  MultiCityTables withCityRecord(CityRecord record) => MultiCityTables(
    cities:
        ([
              ...cities.where((r) => r.id != record.id),
              record,
            ]..sort((a, b) => cityIdNumber(a.id).compareTo(cityIdNumber(b.id))))
            .toList(),
    tablesById: tablesById,
  );
}

/// City ids are `city_<number>`: the number orders them (so city_2
/// sorts before city_10) and mints new ones. Anything else is a
/// corrupt or unmigrated save and fails here.
int cityIdNumber(String id) {
  final match = RegExp(r'^city_(\d+)$').firstMatch(id);
  if (match == null) {
    throw FormatException('City id "$id" is not city_<number>.');
  }
  return int.parse(match.group(1)!);
}

/// Header rows define each sheet's layout; the same headers go into the
/// real Google Spreadsheet and the bundled CSV documents.
const citiesHeaders = <String>['city_id', 'name', 'founded'];
const userDataHeaders = <String>['city_id', 'key', 'value'];
const tilesHeaders = <String>[
  'city_id',
  'x',
  'y',
  'kind',
  'status',
  'detail',
  'variant',
  'facing',
  'project',
];
const propsHeaders = <String>[
  'city_id',
  'x',
  'y',
  'subtile_x',
  'subtile_y',
  'model',
  'variant',
  'facing',
];
const ownedParcelsHeaders = <String>['city_id', 'x', 'y'];
const projectsHeaders = <String>[
  'city_id',
  'id',
  'kind',
  'detail',
  'target',
  'funded',
];

const citiesSheetName = 'Cities';
const userDataSheetName = 'UserData';
const tilesSheetName = 'Tiles';
const propsSheetName = 'Props';
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

/// Reads the whole save from the raw CSV documents. Missing documents
/// read as empty tables, so an absent save is an empty [MultiCityTables]
/// (a fresh world). Rows referencing a city missing from the index
/// fail visibly — an unmigrated pre-multi-city save fails here too,
/// which is intended: there is no migration code.
MultiCityTables decodeMultiCityTables({
  String cities = '',
  String userData = '',
  String tiles = '',
  String props = '',
  String ownedParcels = '',
  String projects = '',
}) {
  final records = <CityRecord>[];
  final known = <String>{};
  for (final row in _padRows(decodeCsvRows(cities), citiesHeaders.length)) {
    cityIdNumber(row[0]);
    if (!known.add(row[0])) {
      throw FormatException('The Cities sheet lists "${row[0]}" twice.');
    }
    records.add(CityRecord(id: row[0], name: row[1], founded: row[2]));
  }
  records.sort((a, b) => cityIdNumber(a.id).compareTo(cityIdNumber(b.id)));

  /// Splits one document's rows into per-city blocks, dropping the
  /// leading city column. Rows belonging to no indexed city fail.
  Map<String, List<List<String>>> partition(String text, int width) {
    final blocks = <String, List<List<String>>>{};
    for (final row in _padRows(decodeCsvRows(text), width + 1)) {
      if (!known.contains(row[0])) {
        throw FormatException(
          'A row belongs to unknown city "${row[0]}" — the save may not '
          'be in the multi-city format.',
        );
      }
      (blocks[row[0]] ??= []).add(row.sublist(1));
    }
    return blocks;
  }

  final userDataRows = partition(userData, userDataHeaders.length - 1);
  final tilesRows = partition(tiles, tilesHeaders.length - 1);
  final propsRows = partition(props, propsHeaders.length - 1);
  final parcelRows = partition(ownedParcels, ownedParcelsHeaders.length - 1);
  final projectRows = partition(projects, projectsHeaders.length - 1);

  // Parcels are exclusive across cities — the one rule that spans
  // blocks, so it is checked where the blocks meet: the decode.
  final parcelOwner = <String, String>{};
  for (final entry in parcelRows.entries) {
    for (final row in entry.value) {
      final key = '${row[0]},${row[1]}';
      final owner = parcelOwner[key];
      if (owner != null) {
        throw FormatException(
          'Parcel ($key) is owned by both $owner and ${entry.key}.',
        );
      }
      parcelOwner[key] = entry.key;
    }
  }

  return MultiCityTables(
    cities: records,
    tablesById: {
      for (final id in known)
        id: SheetTables(
          userData: {
            for (final row in userDataRows[id] ?? const [])
              if (row[0].isNotEmpty) row[0]: row[1],
          },
          tiles: tilesRows[id] ?? const [],
          props: propsRows[id] ?? const [],
          ownedParcels: parcelRows[id] ?? const [],
          projects: projectRows[id] ?? const [],
        ),
    },
  );
}

/// Encodes the whole save into the six CSV documents. Every sheet's
/// rows are city-major — grouped by ascending city id — so each city
/// is one contiguous block and a future store can read or write a
/// single city as a single range.
Map<String, String> encodeMultiCityTables(MultiCityTables tables) {
  // Blocks without index rows would decode as corruption; encode is
  // as strict as decode.
  final indexed = tables.cities.map((record) => record.id).toSet();
  for (final id in tables.tablesById.keys) {
    if (!indexed.contains(id)) {
      throw FormatException('City "$id" has a block but no index row.');
    }
  }
  final ids = {
    ...tables.tablesById.keys,
    ...tables.cities.map((r) => r.id),
  }.toList()..sort((a, b) => cityIdNumber(a).compareTo(cityIdNumber(b)));

  Iterable<List<String>> cityMajor(
    List<List<String>> Function(SheetTables tables) rows,
  ) sync* {
    for (final id in ids) {
      final cityTables = tables.tablesById[id];
      if (cityTables == null) continue;
      for (final row in rows(cityTables)) {
        yield [id, ...row];
      }
    }
  }

  return {
    citiesSheetName: encodeCsvRows(citiesHeaders, [
      for (final record in tables.cities)
        [record.id, record.name, record.founded],
    ]),
    userDataSheetName: encodeCsvRows(userDataHeaders, [
      for (final id in ids)
        for (final entry in (_sortedUserData(tables.tablesById[id]?.userData)))
          [id, entry.key, entry.value],
    ]),
    tilesSheetName: encodeCsvRows(
      tilesHeaders,
      cityMajor((t) => t.tiles).toList(),
    ),
    propsSheetName: encodeCsvRows(
      propsHeaders,
      cityMajor((t) => t.props).toList(),
    ),
    ownedParcelsSheetName: encodeCsvRows(
      ownedParcelsHeaders,
      cityMajor((t) => t.ownedParcels).toList(),
    ),
    projectsSheetName: encodeCsvRows(
      projectsHeaders,
      cityMajor((t) => t.projects).toList(),
    ),
  };
}

List<MapEntry<String, String>> _sortedUserData(Map<String, String>? userData) =>
    (userData?.entries.toList() ?? const [])
      ..sort((a, b) => a.key.compareTo(b.key));

/// Normalizes row width so short hand-edited rows still line up with the
/// header layout.
List<List<String>> _padRows(List<List<String>> rows, int width) => [
  for (final row in rows) [...row, for (var i = row.length; i < width; i++) ''],
];

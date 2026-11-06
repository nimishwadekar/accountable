/// Translates between [ParcelWorldState] and the four storage sheets.
///
/// The sheets store only player facts — IDs, coordinates, and construction
/// stages. Everything else is re-derived on load: parcel terrain is
/// re-sampled from the (codebase) terrain provider, footprints come from
/// the catalogue model, bridge spans come from their tile runs, road plan
/// order comes from the connected-road frontier, unlocks and builder
/// capacity come from population, and entity counters come from the rows
/// themselves. No versions are stored; a content edit is a live update.
library;

import '../content/content_bundle.dart';
import '../world/coordinates.dart';
import '../world/terrain_provider.dart';
import '../world/world_content.dart';
import '../world/world_state.dart';
import 'sheet_tables.dart';

const _seedKey = 'seed';
const _coinsKey = 'coins';
const _coinsEarnedKey = 'coins_earned';
const _coinsSpentKey = 'coins_spent';
const _simulatedDateKey = 'simulated_date';
const _highWaterDateKey = 'high_water_date';
const _lastCheckInDateKey = 'last_checkin_date';
const _checkInCountKey = 'checkin_count';
const _constructionDayKey = 'construction_day';

/// Writes the world's player-visible facts into the four sheets.
SheetTables worldToSheetTables(ParcelWorldState state) {
  final userData = <String, String>{
    _seedKey: '${state.seed}',
    _coinsKey: '${state.coins}',
    _coinsEarnedKey: '${state.totalCoinsEarned}',
    _coinsSpentKey: '${state.totalCoinsSpent}',
    _simulatedDateKey: state.dateKey,
    _highWaterDateKey: worldDateKey(state.checkInHighWaterDate),
    if (state.lastCheckInDate != null)
      _lastCheckInDateKey: worldDateKey(state.lastCheckInDate!),
    _checkInCountKey: '${state.checkInCount}',
    _constructionDayKey: '${state.constructionDay}',
  };

  final tiles = <List<String>>[
    for (final road in state.roads)
      _tileRow(
        road.cell,
        'road',
        'complete',
        road.style.name,
        '',
        '',
        _projectColumn(road.projectId),
      ),
    for (final structure in state.structures)
      _tileRow(
        structure.origin,
        'structure',
        'complete',
        structure.catalogueId,
        structure.assetRole ?? '',
        structure.facing ?? '',
        '',
      ),
    for (final bridge in state.bridges)
      for (final cell in bridge.waterCells)
        _tileRow(cell, 'bridge', 'complete', '', '', '', ''),
    for (final job in state.constructions)
      ..._plannedTilesFor(job, {for (final road in state.roads) road.cell}),
  ];

  final parcels = [
    for (final parcel in state.parcels)
      ['${parcel.coord.x}', '${parcel.coord.y}'],
  ];

  final projects = [for (final job in state.constructions) _projectRowFor(job)];

  return SheetTables(
    userData: userData,
    tiles: tiles,
    ownedParcels: parcels,
    projects: projects,
  );
}

/// Rebuilds a world from the four sheets. Throws [FormatException] on
/// structurally invalid tables (hand edits, truncated writes); the store
/// then surfaces the failure instead of silently rendering a broken
/// world.
ParcelWorldState sheetTablesToWorld(
  SheetTables tables, {
  required ContentBundle content,
  required TerrainProvider terrainProvider,
}) {
  final userData = tables.userData;
  final seed = _userInt(userData, _seedKey);
  final simulatedDate = _userDate(userData, _simulatedDateKey);
  final highWaterDate = _userDate(userData, _highWaterDateKey);
  final lastCheckInKey = userData[_lastCheckInDateKey];
  final checkInCount = userData.containsKey(_checkInCountKey)
      ? _userInt(userData, _checkInCountKey)
      : 0;
  final constructionDay = userData.containsKey(_constructionDayKey)
      ? _userInt(userData, _constructionDayKey)
      : 0;

  final parcels =
      [
            for (final row in tables.ownedParcels)
              OwnedParcel(
                coord: ParcelCoord(
                  _parseInt(row[0], 'parcel x'),
                  _parseInt(row[1], 'parcel y'),
                ),
                pricePaid: 0,
                purchasedAtDay: 0,
                // Terrain is codebase content: purchased parcels re-sample the
                // provider rather than carrying snapshots.
                terrain: const [],
              ),
          ]
          .map(
            (parcel) => OwnedParcel(
              coord: parcel.coord,
              pricePaid: 0,
              purchasedAtDay: 0,
              terrain: parcel.coord
                  .cells(defaultParcelSize)
                  .map((cell) => terrainProvider.sample(cell, seed))
                  .toList(),
            ),
          )
          .toList();

  final tileRows = <List<String>>[...tables.tiles];
  _validateTileRows(tileRows);
  // The project column references live projects only. Heal older saves
  // whose completed roads kept a finished project's reference: project
  // numbers restart once no project is active, and a stale reference
  // would be mistaken for a later project that reuses the number.
  // Planned tiles are not healed — a planned tile without a live
  // project is genuinely orphaned and must fail below.
  final liveProjectNumbers = {for (final row in tables.projects) row[0].trim()};
  for (var index = 0; index < tileRows.length; index++) {
    final row = tileRows[index];
    if (row[2] != 'road' || row[3] != 'complete' || row[7].isEmpty) continue;
    if (!liveProjectNumbers.contains(row[7].trim())) {
      final healed = [...row];
      healed[7] = '';
      tileRows[index] = healed;
    }
  }
  final parcelCenter = CellCoord(
    defaultParcelSize ~/ 2,
    defaultParcelSize ~/ 2,
  );

  // Completed roads and bridge runs.
  final roadsByCell = <CellCoord, RoadSegment>{};
  for (final row in tileRows) {
    if (row[2] != 'road' || row[3] != 'complete') continue;
    final cell = _cell(row[0], row[1]);
    final isStarter = cell == parcelCenter;
    roadsByCell[cell] = RoadSegment(
      id: isStarter ? 'road-start' : 'road:${cell.key}',
      cell: cell,
      style: _parseStyle(row[4]),
      pricePaid: isStarter ? 0 : content.economy.roadTileCostCoins,
      completedAtDay: 0,
      projectId: _projectId(row[7]),
    );
  }

  final structures = <PlacedStructure>[];
  for (final row in tileRows) {
    if (row[2] != 'structure' || row[3] != 'complete') continue;
    final origin = _cell(row[0], row[1]);
    final definition = content.structure(row[4]);
    if (definition == null) {
      throw FormatException('Unknown structure model "${row[4]}".');
    }
    structures.add(
      PlacedStructure(
        id: 'structure:${origin.key}',
        catalogueId: definition.id,
        kind: definition.kind,
        origin: origin,
        quarterTurns: 0,
        footprint: structureFootprint(definition, origin),
        pricePaid: definition.costCoins,
        completedAtDay: 0,
        population: definition.population,
        assetRole: _orNull(row[5]),
        facing: _orNull(row[6]),
      ),
    );
  }

  final bridges = _bridgeRuns(tileRows, roadsByCell, content);

  // Active projects.
  final projectRows = [...tables.projects]
    ..sort(
      (a, b) => _parseInt(
        a[0],
        'project id',
      ).compareTo(_parseInt(b[0], 'project id')),
    );
  final constructions = <WorldConstruction>[];
  for (var slot = 0; slot < projectRows.length; slot++) {
    final row = projectRows[slot];
    final number = _parseInt(row[0], 'project id');
    final kind = row[1];
    final funded = (row[4]).isEmpty ? 0 : _parseInt(row[4], 'funded');
    switch (kind) {
      case 'structure':
        final target = _parseTarget(row[3]);
        final origin = CellCoord(target[0], target[1]);
        final definition = content.structure(row[2]);
        if (definition == null) {
          throw FormatException('Unknown project model "${row[2]}".');
        }
        final tile = _plannedStructureTile(tileRows, origin);
        constructions.add(
          WorldConstruction(
            id: 'construction-$number',
            kind: WorldConstructionKind.structure,
            catalogueId: definition.id,
            structureKind: definition.kind,
            origin: origin,
            quarterTurns: 0,
            footprint: structureFootprint(definition, origin),
            totalCostCoins: definition.costCoins,
            coinsFunded: funded,
            builderSlot: slot,
            startedAtDay: 0,
            population: definition.population,
            assetRole: _orNull(tile[5]),
            facing: _orNull(tile[6]),
          ),
        );
      case 'road':
        constructions.add(
          _roadConstruction(row, number, slot, tileRows, roadsByCell, content),
        );
      case 'bridge':
        final target = _parseTarget(row[3]);
        final nearBank = CellCoord(target[0], target[1]);
        final farBank = CellCoord(target[2], target[3]);
        final waterCells = _cellsBetween(nearBank, farBank);
        constructions.add(
          WorldConstruction(
            id: 'construction-$number',
            kind: WorldConstructionKind.bridge,
            nearBank: nearBank,
            farBank: farBank,
            waterCells: waterCells,
            totalCostCoins: content.economy.bridgeCost(waterCells.length),
            coinsFunded: funded,
            builderSlot: slot,
            startedAtDay: 0,
          ),
        );
      default:
        throw FormatException('Unknown project kind "$kind".');
    }
  }

  final population = structures.fold<int>(
    0,
    (sum, structure) => sum + structure.population,
  );

  // Every planned tile must belong to a live project — an orphan means
  // the tables were hand-edited or a write was truncated.
  final liveProjects = constructions.map((job) => job.id).toSet();
  final structureTargets = <String>{
    for (final job in constructions)
      if (job.kind == WorldConstructionKind.structure)
        '${job.origin!.column}:${job.origin!.row}',
  };
  for (final row in tileRows) {
    if (row[3] != 'planned') continue;
    if (row[2] == 'road') {
      if (!liveProjects.contains('construction-${row[7]}')) {
        throw FormatException(
          'Planned road tile at ${row[0]},${row[1]} has no project.',
        );
      }
    } else if (row[2] == 'structure') {
      if (!structureTargets.contains('${row[0]}:${row[1]}')) {
        throw FormatException(
          'Planned structure tile at ${row[0]},${row[1]} has no project.',
        );
      }
    }
  }

  return ParcelWorldState(
    worldId: 'parcel-world-$seed',
    seed: seed,
    generatorVersion: terrainProvider.generatorVersion,
    rulesVersion: parcelWorldRulesVersion,
    contentVersion: parcelWorldContentVersion,
    parcelSize: defaultParcelSize,
    builderCapacity: content.economy.builderCapacityForPopulation(population),
    simulatedDate: simulatedDate,
    checkInHighWaterDate: highWaterDate,
    constructionDay: constructionDay,
    coins: _userInt(userData, _coinsKey),
    totalCoinsEarned: _userInt(userData, _coinsEarnedKey),
    totalCoinsSpent: _userInt(userData, _coinsSpentKey),
    nextEntityNumber: projectRows.isEmpty
        ? 1
        : _parseInt(projectRows.last[0], 'project id') + 1,
    nextEventNumber: 1,
    lastCheckInDate: lastCheckInKey == null || lastCheckInKey.isEmpty
        ? null
        : _userDate(userData, _lastCheckInDateKey),
    checkInCount: checkInCount,
    unlockedCatalogueIds: {
      for (final model in content.purchaseableModels)
        if (model.unlockAtPopulation <= population) model.id,
    },
    parcels: parcels,
    roads: roadsByCell.values.toList(),
    structures: structures,
    bridges: bridges,
    constructions: constructions,
    events: const [],
  );
}

// ---------------------------------------------------------------------------
// Save helpers
// ---------------------------------------------------------------------------

List<String> _tileRow(
  CellCoord cell,
  String kind,
  String status,
  String detail,
  String variant,
  String facing,
  String project,
) => [
  '${cell.column}',
  '${cell.row}',
  kind,
  status,
  detail,
  variant,
  facing,
  project,
];

/// Planned tiles for a project: unfunded road cells and planned
/// structure origins. Funded road tiles already have complete rows, and
/// planned bridge spans are derived from the project's target banks.
List<List<String>> _plannedTilesFor(
  WorldConstruction job,
  Set<CellCoord> fundedRoadCells,
) {
  switch (job.kind) {
    case WorldConstructionKind.road:
      final project = _projectColumn(job.id);
      return [
        for (final cell in job.roadCells)
          if (!fundedRoadCells.contains(cell))
            _tileRow(
              cell,
              'road',
              'planned',
              job.roadStyle!.name,
              '',
              '',
              project,
            ),
      ];
    case WorldConstructionKind.structure:
      return [
        _tileRow(
          job.origin!,
          'structure',
          'planned',
          job.catalogueId!,
          job.assetRole ?? '',
          job.facing ?? '',
          '',
        ),
      ];
    case WorldConstructionKind.bridge:
      return const [];
  }
}

List<String> _projectRowFor(WorldConstruction job) {
  final number = job.id.replaceFirst('construction-', '');
  return switch (job.kind) {
    WorldConstructionKind.structure => [
      number,
      'structure',
      job.catalogueId!,
      '${job.origin!.column}:${job.origin!.row}',
      '${job.coinsFunded}',
    ],
    WorldConstructionKind.road => [
      number,
      'road',
      job.roadStyle!.name,
      '',
      // Road funding is per tile; the amount derives from the tiles.
      '',
    ],
    WorldConstructionKind.bridge => [
      number,
      'bridge',
      '',
      '${job.nearBank!.column}:${job.nearBank!.row}:'
          '${job.farBank!.column}:${job.farBank!.row}',
      '${job.coinsFunded}',
    ],
  };
}

String _projectColumn(String? projectId) =>
    projectId == null ? '' : projectId.replaceFirst('construction-', '');

String? _projectId(String column) =>
    column.isEmpty ? null : 'construction-$column';

// ---------------------------------------------------------------------------
// Load helpers
// ---------------------------------------------------------------------------

/// Structural checks before any derivation runs, so hand-edited or
/// truncated tables fail loudly instead of silently rendering a broken
/// world: known kinds and statuses, no planned bridges (spans derive from
/// project targets), and one entity per cell.
void _validateTileRows(List<List<String>> tileRows) {
  final landCells = <CellCoord>{};
  final waterCells = <CellCoord>{};
  for (final row in tileRows) {
    final kind = row[2];
    if (kind != 'road' && kind != 'bridge' && kind != 'structure') {
      throw FormatException('Unknown tile kind "$kind".');
    }
    final status = row[3];
    if (status != 'planned' && status != 'complete') {
      throw FormatException('Unknown tile status "$status".');
    }
    if (kind == 'bridge' && status != 'complete') {
      throw const FormatException(
        'Bridge tiles are never planned; spans derive from the project.',
      );
    }
    final cell = _cell(row[0], row[1]);
    if (kind == 'bridge') {
      if (!waterCells.add(cell)) {
        throw FormatException('Duplicate bridge tile at ${cell.key}.');
      }
    } else if (!landCells.add(cell)) {
      throw FormatException('Duplicate tile at ${cell.key}.');
    }
  }
}

int _userInt(Map<String, String> userData, String key) {
  final value = int.tryParse(userData[key] ?? '');
  if (value == null) {
    throw FormatException('UserData is missing a valid "$key".');
  }
  return value;
}

int _parseInt(String raw, String label) {
  final value = int.tryParse(raw.trim());
  if (value == null) {
    throw FormatException('"$raw" is not a valid $label.');
  }
  return value;
}

DateTime _userDate(Map<String, String> userData, String key) {
  final raw = userData[key];
  final parsed = raw == null ? null : DateTime.tryParse(raw);
  if (parsed == null || worldDateKey(parsed) != raw) {
    throw FormatException('UserData is missing a valid "$key".');
  }
  return DateTime.utc(parsed.year, parsed.month, parsed.day);
}

CellCoord _cell(String x, String y) =>
    CellCoord(_parseInt(x, 'tile x'), _parseInt(y, 'tile y'));

RoadStyle _parseStyle(String name) =>
    RoadStyle.values.firstWhere((style) => style.name == name);

String? _orNull(String value) => value.isEmpty ? null : value;

List<int> _parseTarget(String target) {
  final parts = target.split(':');
  if (parts.length != 2 && parts.length != 4) {
    throw FormatException('"$target" is not a valid project target.');
  }
  return [
    for (final part in parts) _parseInt(part, 'project target coordinate'),
  ];
}

List<String> _plannedStructureTile(
  List<List<String>> tileRows,
  CellCoord origin,
) {
  for (final row in tileRows) {
    if (row[2] != 'structure' || row[3] != 'planned') continue;
    if (_cell(row[0], row[1]) == origin) return row;
  }
  throw FormatException(
    'Planned structure at ${origin.key} has no matching tile row.',
  );
}

/// Rebuilds a road project: its cells are every tile row referencing the
/// project, ordered by walking the four-connected path from the end that
/// touches a completed road outside the project.
WorldConstruction _roadConstruction(
  List<String> row,
  int number,
  int slot,
  List<List<String>> tileRows,
  Map<CellCoord, RoadSegment> roadsByCell,
  ContentBundle content,
) {
  final style = _parseStyle(row[2]);
  final projectId = 'construction-$number';
  final cells = <CellCoord>{};
  for (final tile in tileRows) {
    if (tile[7] != '$number') continue;
    cells.add(_cell(tile[0], tile[1]));
  }
  if (cells.isEmpty) {
    throw FormatException('Road project $number has no planned tiles.');
  }
  final outside = roadsByCell.keys.where((cell) => !cells.contains(cell));
  final ordered = _orderPath(cells, outside.toSet());
  // Road funding is per tile: the funded amount is the count of this
  // project's completed road tiles.
  final fundedTiles = roadsByCell.values
      .where((road) => road.projectId == projectId)
      .length;
  return WorldConstruction(
    id: projectId,
    kind: WorldConstructionKind.road,
    roadStyle: style,
    roadCells: ordered,
    totalCostCoins: ordered.length,
    coinsFunded: fundedTiles,
    builderSlot: slot,
    startedAtDay: 0,
  );
}

/// Orders a four-connected path of cells starting from the end that is
/// adjacent to a completed road outside the path (the funding frontier
/// the game enforces). Ties and single cells resolve deterministically.
List<CellCoord> _orderPath(Set<CellCoord> cells, Set<CellCoord> outside) {
  if (cells.length == 1) return cells.toList();
  CellCoord? bestStart;
  for (final cell in cells) {
    final inPath = cell.neighbors.where(cells.contains).length;
    if (inPath != 1) continue; // Path ends only.
    final touchesOutside = cell.neighbors.any(outside.contains);
    final better =
        bestStart == null ||
        (touchesOutside && !_touchesOutside(bestStart, outside)) ||
        (touchesOutside == _touchesOutside(bestStart, outside) &&
            (cell.column + cell.row) < (bestStart.column + bestStart.row));
    if (better) bestStart = cell;
  }
  if (bestStart == null) {
    throw const FormatException('Road plan is not a simple path.');
  }
  final ordered = <CellCoord>[bestStart];
  final remaining = cells.difference({bestStart});
  var current = bestStart;
  while (remaining.isNotEmpty) {
    final next = current.neighbors.firstWhere(remaining.contains);
    ordered.add(next);
    remaining.remove(next);
    current = next;
  }
  return ordered;
}

bool _touchesOutside(CellCoord cell, Set<CellCoord> outside) =>
    cell.neighbors.any(outside.contains);

/// Groups complete bridge tiles into straight runs and rebuilds one
/// bridge per run. The banks are the road tiles at the run's ends; the
/// near bank is the deterministically smaller end.
List<CompletedBridge> _bridgeRuns(
  List<List<String>> tileRows,
  Map<CellCoord, RoadSegment> roadsByCell,
  ContentBundle content,
) {
  final bridgeCells = <CellCoord>{
    for (final row in tileRows)
      if (row[2] == 'bridge' && row[3] == 'complete') _cell(row[0], row[1]),
  };

  bool isBridge(CellCoord cell) => bridgeCells.contains(cell);

  // Assign every bridge tile to a horizontal (fixed y) or vertical (fixed
  // x) line; single tiles orient toward a neighbouring road bank.
  final assigned = <CellCoord>{};
  final runs = <List<CellCoord>>[];
  for (final cell in bridgeCells) {
    if (assigned.contains(cell)) continue;
    final horizontal =
        isBridge(cell.offset(-1, 0)) ||
        isBridge(cell.offset(1, 0)) ||
        (!isBridge(cell.offset(0, -1)) && !isBridge(cell.offset(0, 1)));
    final run = <CellCoord>[cell];
    assigned.add(cell);
    if (horizontal) {
      for (var step = 1; isBridge(cell.offset(step, 0)); step++) {
        run.add(cell.offset(step, 0));
        assigned.add(cell.offset(step, 0));
      }
      for (var step = 1; isBridge(cell.offset(-step, 0)); step++) {
        run.insert(0, cell.offset(-step, 0));
        assigned.add(cell.offset(-step, 0));
      }
    } else {
      for (var step = 1; isBridge(cell.offset(0, step)); step++) {
        run.add(cell.offset(0, step));
        assigned.add(cell.offset(0, step));
      }
      for (var step = 1; isBridge(cell.offset(0, -step)); step++) {
        run.insert(0, cell.offset(0, -step));
        assigned.add(cell.offset(0, -step));
      }
    }
    runs.add(run);
  }

  return [for (final run in runs) _bridgeFromRun(run, roadsByCell, content)];
}

CompletedBridge _bridgeFromRun(
  List<CellCoord> run,
  Map<CellCoord, RoadSegment> roadsByCell,
  ContentBundle content,
) {
  final first = run.first;
  final last = run.last;
  final horizontal = first.row == last.row;
  final before = horizontal
      ? CellCoord(first.column - 1, first.row)
      : CellCoord(first.column, first.row - 1);
  final after = horizontal
      ? CellCoord(last.column + 1, last.row)
      : CellCoord(last.column, last.row + 1);
  if (!roadsByCell.containsKey(before) || !roadsByCell.containsKey(after)) {
    throw FormatException(
      'Bridge run at ${run.first.key} does not end on roads.',
    );
  }
  // The near bank is the deterministically smaller end; both banks are
  // connected roads once a bridge completes, so the choice is semantic
  // only.
  final (
    nearBank,
    farBank,
  ) = before.column + before.row < after.column + after.row
      ? (before, after)
      : (after, before);
  final waterCells = nearBank == before ? run : run.reversed.toList();
  return CompletedBridge(
    id: 'bridge:${nearBank.key}',
    waterCells: waterCells,
    nearBank: nearBank,
    farBank: farBank,
    pricePaid: content.economy.bridgeCost(run.length),
    completedAtDay: 0,
  );
}

/// The water cells strictly between two banks along a straight line.
List<CellCoord> _cellsBetween(CellCoord nearBank, CellCoord farBank) {
  final dx = farBank.column - nearBank.column;
  final dy = farBank.row - nearBank.row;
  final step = CellCoord(dx.sign, dy.sign);
  return [
    for (var index = 1; index < dx.abs() + dy.abs(); index++)
      nearBank.offset(step.column * index, step.row * index),
  ];
}

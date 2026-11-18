// The reviewer play CLI — a game reviewer's entire interface to the
// town. One shell invocation runs a session's commands against the
// real reducer, saves via the production codec, and logs every day
// in the batch tool's format. Refusals print the game's own rule
// messages verbatim, because the refusal is the finding.
//
// The reviewer plays the "road to a million" variant from
// content_variants.dart: the extended ladder, density housing, the
// scaled services, the blend-40 economy, and the big island map.
//
// Usage:
//   dart run tool/sim/play_cli.dart --state <state.json> --log <log.jsonl>
//        --notes <notes.md> [--content-dir assets/content]
//        "help" "status" "day" "build small-home 12 9" "note ..."
//
// Commands:
//   help                          the tutorial
//   status                        the HUD
//   report                        the last check-in, in full
//   day                           next calendar day, opened and checked in
//   skip <n>                      days the player didn't open the game
//   map [col row]                 ASCII cell window around the town
//   catalogue                     unlocked models with their stats
//   found <px> <py>               claim the free founding parcel
//   parcel <px> <py>              buy land (quoted)
//   road <c1,r1> <c2,r2>          plan one road stretch (quoted)
//   build <model> <col> <row>     place a building (quoted)
//   place <model> <col> <row> <sx> <sy>   place a decoration
//   pickup <propId>               pick a placed or nature prop back up
//   inspect <col> <row>           what stands on a cell
//   note <text>                   append a session note

import 'dart:convert';
import 'dart:io';

import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/storage/sheet_tables.dart';
import 'package:citysim/storage/world_sheet_codec.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:citysim/world/terrain_provider.dart';
import 'package:citysim/world/world_queries.dart';
import 'package:citysim/world/world_reducer.dart';
import 'package:citysim/world/world_rules.dart';
import 'package:citysim/world/world_state.dart';

import 'content_variants.dart';
import 'harness.dart' show DayRecord, SimAction;

Map<String, Object?> readCategory(Directory dir, String name) =>
    decodeJsonObject(File('${dir.path}/$name').readAsStringSync());

ContentBundle loadBundle(Directory dir) => parseContentBundle(
  manifest: readCategory(dir, 'manifest.json'),
  catalogue: readCategory(dir, 'catalogue.json'),
  sprites: readCategory(dir, 'sprites.json'),
  economy: readCategory(dir, 'economy.json'),
  ambience: readCategory(dir, 'ambience.json'),
  terrain: readCategory(dir, 'terrain.json'),
  progression: readCategory(dir, 'progression.json'),
);

String _fmt(num value) {
  final rounded = value.round();
  final sign = rounded < 0 ? '-' : '';
  return '$sign${rounded.abs().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => ',')}';
}

Map<String, Object?> _tablesToJson(SheetTables tables) => {
  'userData': tables.userData,
  'tiles': tables.tiles,
  'props': tables.props,
  'ownedParcels': tables.ownedParcels,
  'projects': tables.projects,
};

SheetTables _tablesFromJson(Object? value) {
  final map = (value as Map).cast<String, Object?>();
  List<List<String>> rows(Object? key) => [
    for (final row in map[key] as List)
      [for (final cell in row as List) cell as String],
  ];
  return SheetTables(
    userData: (map['userData'] as Map).cast<String, String>(),
    tiles: rows('tiles'),
    props: rows('props'),
    ownedParcels: rows('ownedParcels'),
    projects: rows('projects'),
  );
}

/// One reviewer's town across a session of commands.
class _PlaySession {
  _PlaySession({
    required this.content,
    required this.terrain,
    required this.state,
    required this.logFile,
    required this.notesFile,
  });

  final ContentBundle content;
  final ContentTerrainProvider terrain;
  ParcelWorldState state;
  final File logFile;
  final File notesFile;

  final List<SimAction> _actionsToday = [];
  bool _dayOpen = false;

  WorldQueries get queries => WorldQueries(state, terrain);

  void run(String command) {
    final words = command.trim().split(RegExp(r'\s+'));
    final head = words.isEmpty || words.first.isEmpty ? '' : words.first;
    // Mutating commands open the game first — the player cannot act
    // without opening the app, and the first open of a fresh world
    // is day 1 with its check-in.
    const views = {'help', 'status', 'report', 'map', 'catalogue', 'note'};
    const dayCommands = {'day', 'skip'};
    if (!views.contains(head) && !dayCommands.contains(head)) {
      _ensureDayOpened();
    }
    switch (head) {
      case 'help':
        _help();
      case 'status':
        _status();
      case 'report':
        _report();
      case 'day':
        _day();
      case 'skip':
        _skip(words.length > 1 ? int.tryParse(words[1]) ?? 1 : 1);
      case 'map':
        _map(
          words.length > 2
              ? CellCoord(int.parse(words[1]), int.parse(words[2]))
              : null,
        );
      case 'catalogue':
        _catalogue();
      case 'found':
        _parcel(
          ParcelCoord(int.parse(words[1]), int.parse(words[2])),
          founding: true,
        );
      case 'parcel':
        _parcel(ParcelCoord(int.parse(words[1]), int.parse(words[2])));
      case 'road':
        _road(words.sublist(1));
      case 'build':
        _build(words[1], CellCoord(int.parse(words[2]), int.parse(words[3])));
      case 'place':
        _place(words);
      case 'pickup':
        _pickup(words.sublist(1).join(' '));
      case 'inspect':
        _inspect(CellCoord(int.parse(words[1]), int.parse(words[2])));
      case 'note':
        _note(command.trim().substring(5).trim());
      case '':
        // Empty command: ignore.
        break;
      default:
        stdout.writeln('✗ Unknown command "$head" — try help.');
    }
  }

  // ---------------------------------------------------------- days

  /// Opens day 1 of a fresh world — the first time the player acts,
  /// the app opens, the calendar rolls, and the check-in fires.
  void _ensureDayOpened() {
    if (_dayOpen || state.constructionDay > 0) return;
    state = advanceWorldDays(state, 1);
    _dayOpen = true;
    if (canCheckInWorldToday(state)) {
      state = checkInWorldForToday(state, content);
    }
    _report();
  }

  void _day() {
    _flushDay();
    state = advanceWorldDays(state, 1);
    _dayOpen = true;
    if (canCheckInWorldToday(state)) {
      state = checkInWorldForToday(state, content);
    }
    _report();
  }

  void _skip(int days) {
    for (var i = 0; i < days; i++) {
      _flushDay();
      state = advanceWorldDays(state, 1);
      // A day away: no visit, no actions — record it immediately.
      _writeRecord(credited: false);
    }
    stdout.writeln('(skipped to day ${_dayNumber()} — ${state.dateKey})');
  }

  int _dayNumber() => state.constructionDay;

  /// Closes the currently open day, if any, writing its record.
  void _flushDay() {
    if (!_dayOpen && _actionsToday.isEmpty) return;
    _writeRecord(credited: _lastCheckInEvent() != null);
  }

  /// Writes the record for the current day and resets the action
  /// log. Called when a day ends — the next `day`, a `skip`, or the
  /// end of the invocation.
  void _writeRecord({required bool credited}) {
    _dayOpen = false;
    final report = credited ? _lastCheckInEvent() : null;
    final payload = report?.payload ?? const <String, Object?>{};
    final acted = _actionsToday.any((action) => action.ok);
    final record = DayRecord(
      day: state.constructionDay,
      dateKey: state.dateKey,
      credited: credited,
      coins: state.coins,
      population: state.population,
      employed: state.employedPopulation,
      waiting: state.waitingPopulation,
      residentialCapacity: _residentialCapacity(),
      jobCapacity: _jobCapacity(),
      parcels: state.parcels.length,
      roads: state.roads.length,
      structures: state.structures.length,
      constructions: state.constructions.length,
      milestone: state.progressionMilestoneId ?? 'none',
      actions: List.unmodifiable(_actionsToday),
      dead:
          credited &&
          (payload['populationArrived'] as num? ?? 0) == 0 &&
          (payload['completions'] as List?)?.isEmpty != false &&
          !acted,
      taxes: (payload['taxes'] as num?)?.toInt(),
      upkeep: (payload['upkeep'] as num?)?.toInt(),
      net: (payload['net'] as num?)?.toInt(),
      contentment: (payload['contentment'] as num?)?.toInt(),
      arrived: (payload['populationArrived'] as num?)?.toInt() ?? 0,
      completions: (payload['completions'] as List?)?.length ?? 0,
    );
    _actionsToday.clear();
    logFile.writeAsStringSync(
      '${jsonEncode(record.toJson())}\n',
      mode: FileMode.append,
    );
  }

  WorldEvent? _lastCheckInEvent() {
    WorldEvent? found;
    for (final event in state.events) {
      if (event.kind == 'check-in' &&
          event.payload['creditedDate'] == state.dateKey) {
        found = event;
      }
    }
    return found;
  }

  int _residentialCapacity() {
    var capacity = 0;
    for (final structure in state.structures) {
      final model = content.structure(structure.catalogueId);
      if (model?.isResidential ?? false) capacity += model!.population;
    }
    for (final job in state.constructions) {
      if (job.kind != WorldConstructionKind.structure) continue;
      final model = job.catalogueId == null
          ? null
          : content.structure(job.catalogueId!);
      if (model?.isResidential ?? false) capacity += model!.population;
    }
    return capacity;
  }

  int _jobCapacity() {
    var capacity = 0;
    for (final structure in state.structures) {
      final model = content.structure(structure.catalogueId);
      if (model?.isCommerce ?? false) capacity += model!.jobs;
    }
    for (final job in state.constructions) {
      if (job.kind != WorldConstructionKind.structure) continue;
      final model = job.catalogueId == null
          ? null
          : content.structure(job.catalogueId!);
      if (model?.isCommerce ?? false) capacity += model!.jobs;
    }
    return capacity;
  }

  // ---------------------------------------------------------- views

  void _help() {
    stdout.writeln('''
THE GAME, as the game itself teaches it:
  Open the game once a day and check in: taxes arrive, upkeep is
  paid, and every construction advances one stage. Days you don't
  open the game, nothing progresses at all.
  Buildings construct for free. Land, roads, and bridges cost coins.
  Land is bought as whole parcels, adjacent to your town; the first
  (founding) parcel is free and needs buildable ground. Parcel
  prices rise with your population.
  Buildings need a completed road along one full side of their
  footprint. Road plans are paid upfront, then the whole stretch
  lands on the check-in after you buy it. Brush and trees standing
  on a tile must be picked up (free) before you can build or pave
  there.
  Reaching population milestones unlocks new kinds of buildings.
  Services (health, fire, police) are demanded once your town is
  large enough; low coverage saps contentment, and contentment
  multiplies your taxes.

COMMANDS:
  status · report · map [col row] · catalogue
  day (open tomorrow and check in) · skip <n> (days away)
  found <parcelX> <parcelY> · parcel <parcelX> <parcelY>
  road <col,row> [col,row] · build <model> <col> <row>
  place <model> <col> <row> <subtileX> <subtileY> (decorations)
  pickup <propId> · inspect <col> <row> · note <text>''');
  }

  void _status() {
    final ledger = townLedger(state, content);
    final nextRung = _nextMilestone();
    final lines = <String>[
      'Day ${_dayNumber()} (${state.dateKey}) · check-ins ${state.checkInCount} · ${canCheckInWorldToday(state) ? 'check-in available' : 'already checked in today'}',
      'Treasury ${_fmt(state.coins)} coins · earned ${_fmt(state.totalCoinsEarned)} · spent ${_fmt(state.totalCoinsSpent)}',
      'Population ${state.population} · employed ${state.employedPopulation} · waiting list ${state.waitingPopulation}',
      'Housing ${_residentialCapacity()} beds · jobs ${_jobCapacity()}',
      'Contentment ${ledger.contentment}% · coverage: ${ledger.coverage.entries.map((e) => '${e.key} ${(e.value * 100).round()}%').join(', ')}${ledger.coverage.isEmpty ? 'not yet demanded' : ''}',
      'Milestone: ${state.progressionMilestoneId ?? 'none'}${nextRung == null ? '' : ' · next: ${nextRung.name} at ${nextRung.population} population'}',
      'Parcels ${state.parcels.length} · roads ${state.roads.length} · structures ${state.structures.length} · projects in flight ${state.constructions.length}',
    ];
    stdout.writeln(lines.join('\n'));
  }

  MilestoneDefinition? _nextMilestone() {
    MilestoneDefinition? next;
    for (final milestone in content.progression.sorted) {
      if (milestone.population > state.population) {
        next = milestone;
        break;
      }
    }
    return next;
  }

  void _report() {
    final event = _lastCheckInEvent();
    if (event == null) {
      stdout.writeln('No check-in has landed yet.');
      return;
    }
    final payload = event.payload;
    final completions = (payload['completions'] as List?) ?? const [];
    final unemployed = (payload['unemployed'] as num?)?.toInt() ?? 0;
    final floor = content.economy.homeTaxUnemploymentFloorPercent;
    final buffer = StringBuffer(
      'Report for ${payload['creditedDate']}: '
      'taxes ${_fmt((payload['taxes'] as num?) ?? 0)} · '
      'upkeep ${_fmt((payload['upkeep'] as num?) ?? 0)} · '
      'net ${_fmt((payload['net'] as num?) ?? 0)}\n',
    );
    buffer.write(
      'Arrived ${payload['populationArrived'] ?? 0} · '
      'positions staffed ${payload['positionsStaffed'] ?? 0} · '
      'contentment ${payload['contentment'] ?? 100}%',
    );
    if (unemployed > 0) {
      buffer.write(
        floor > 0
            ? '\nUnemployed $unemployed — homes pay the $floor% levy floor'
            : '\nUnemployed $unemployed — only employed residents pay taxes',
      );
    }
    if (completions.isNotEmpty) {
      buffer.write('\nCompleted: ${completions.join(', ')}');
    }
    stdout.writeln(buffer);
  }

  void _map(CellCoord? center) {
    const width = 44;
    const height = 22;
    var centreColumn = 0.0;
    var centreRow = 0.0;
    if (state.parcels.isNotEmpty) {
      for (final parcel in state.parcels) {
        final origin = parcel.coord.origin(state.parcelSize);
        centreColumn += origin.column + state.parcelSize / 2;
        centreRow += origin.row + state.parcelSize / 2;
      }
      centreColumn /= state.parcels.length;
      centreRow /= state.parcels.length;
    } else {
      centreColumn = 0;
      centreRow = 0;
    }
    final focus = center ?? CellCoord(centreColumn.round(), centreRow.round());
    final queries = this.queries;
    final left = focus.column - width ~/ 2;
    final top = focus.row - height ~/ 2;
    // Brush shows wild and placed alike: propsInBounds reads the
    // chunks, which include the map's unowned nature.
    final propCells = <String>{
      for (final prop in queries.propsInBounds(
        left: left,
        right: left + width,
        top: top,
        bottom: top + height,
      ))
        prop.cell.key,
    };
    final byStructure = <String, String>{
      for (final structure in state.structures)
        if (structure.kind == StructureKind.building)
          structure.origin.key: _letterFor(structure.catalogueId),
    };
    final constructionCells = <String>{
      for (final job in state.constructions) ...[
        ...[for (final cell in job.footprint) cell.key],
        ...[for (final cell in job.roadCells) cell.key],
      ],
    };
    final buffer = StringBuffer(
      'Map around (${focus.column},${focus.row}) — '
      '. free owned · : unowned · ~ water · # road · , brush · '
      'h home · c commerce · s civic · u site\n'
      'columns $left..${left + width - 1} left to right · '
      'rows $top..${top + height - 1} top to bottom · '
      'parcel boundaries every 8\n',
    );
    final ruler = StringBuffer('    ');
    for (var column = left; column < left + width; column++) {
      ruler.write(column % 8 == 0 ? '|' : ' ');
    }
    buffer.writeln(ruler);
    for (var row = top; row < top + height; row++) {
      final line = StringBuffer(
        row % 4 == 0 ? row.toString().padLeft(4) : '    ',
      );
      for (var column = left; column < left + width; column++) {
        final cell = CellCoord(column, row);
        final terrain = queries.terrainAt(cell);
        if (terrain.kind == TerrainKind.fog) {
          line.write(' ');
          continue;
        }
        if (!terrain.isLand) {
          line.write('~');
          continue;
        }
        if (!queries.ownsCell(cell)) {
          line.write(propCells.contains(cell.key) ? ';' : ':');
          continue;
        }
        if (queries.roadsByCell.containsKey(cell)) {
          line.write('#');
          continue;
        }
        if (byStructure.containsKey(cell.key)) {
          line.write(byStructure[cell.key]);
          continue;
        }
        if (constructionCells.contains(cell.key)) {
          line.write('u');
          continue;
        }
        if (propCells.contains(cell.key)) {
          line.write(',');
          continue;
        }
        line.write('.');
      }
      buffer.writeln(line);
    }
    stdout.writeln(buffer);
  }

  String _letterFor(String catalogueId) {
    final model = content.structure(catalogueId);
    if (model == null) return '?';
    if (model.isResidential) return 'h';
    if (model.isCommerce) return 'c';
    if (model.serviceCategory != null) return 's';
    return 'b';
  }

  void _catalogue() {
    final lines = <String>[
      for (final model in content.catalogue)
        if (model.enabled && state.unlockedCatalogueIds.contains(model.id))
          '${model.id.padRight(20)} '
              '${model.kind.name.padRight(11)} '
              '${model.isResidential
                  ? '${model.population} residents'
                  : model.isCommerce
                  ? '${model.jobs} jobs'
                  : model.serviceCategory != null
                  ? '${model.serviceCapacity} ${model.serviceCategory}'
                  : '—'}'
              ' · ${model.footprintColumns}x${model.footprintRows} · '
              '${model.constructionStages} stages · '
              'tax ${_fmt(model.taxCoins)} · upkeep ${_fmt(model.upkeepCoins)}',
    ];
    stdout.writeln(lines.join('\n'));
  }

  // ---------------------------------------------------------- actions

  void _parcel(ParcelCoord coord, {bool founding = false}) {
    try {
      final quote = quoteParcelPurchase(state, content, terrain, coord);
      stdout.writeln(
        '${founding ? 'Founding' : 'Buying'} parcel (${coord.x},${coord.y}): '
        '${_fmt(quote.price)} coins · ${quote.landCellCount} land cells',
      );
      state = purchaseParcel(state, content, terrain, coord);
      _act(
        SimAction(
          founding ? 'found' : 'parcel',
          'parcel (${coord.x},${coord.y})',
          coins: quote.price,
        ),
      );
    } on WorldRuleViolation catch (e) {
      stdout.writeln('✗ ${e.message}');
      _act(
        SimAction(
          founding ? 'found' : 'parcel',
          'parcel (${coord.x},${coord.y})',
          ok: false,
          reason: e.message,
        ),
      );
    }
  }

  void _road(List<String> args) {
    final first = args[0].split(',');
    final start = CellCoord(int.parse(first[0]), int.parse(first[1]));
    final end = args.length > 1
        ? CellCoord(
            int.parse(args[1].split(',')[0]),
            int.parse(args[1].split(',')[1]),
          )
        : start;
    final cells = straightLineBetween(start, end);
    try {
      final quote = quoteRoadStretch(state, content, terrain, cells: cells);
      state = planRoadStretch(state, content, terrain, cells: cells);
      stdout.writeln(
        'Road plan bought: ${cells.length} tiles · ${_fmt(quote.price)} coins '
        '· tiles creep in one per check-in',
      );
      _act(SimAction('roads', '${cells.length} tiles', coins: quote.price));
    } on WorldRuleViolation catch (e) {
      stdout.writeln('✗ ${e.message}');
      _act(
        SimAction(
          'roads',
          '${cells.length} tiles',
          ok: false,
          reason: e.message,
        ),
      );
    }
  }

  void _build(String catalogueId, CellCoord origin) {
    final definition = content.structure(catalogueId);
    if (definition == null ||
        !definition.enabled ||
        !state.unlockedCatalogueIds.contains(catalogueId)) {
      stdout.writeln(
        '✗ "$catalogueId" is not an unlocked model — see catalogue.',
      );
      return;
    }
    try {
      state = startStructureConstruction(
        state,
        content,
        terrain,
        catalogueId: catalogueId,
        origin: origin,
      );
      stdout.writeln(
        '${definition.name} site planned at (${origin.column},${origin.row}) '
        '· ${definition.constructionStages} stages of work · free',
      );
      _act(
        SimAction(
          'build',
          '${definition.name} at (${origin.column},${origin.row})',
          coins: 0,
        ),
      );
    } on WorldRuleViolation catch (e) {
      stdout.writeln('✗ ${e.message}');
      _act(
        SimAction(
          'build',
          '${definition.name} at (${origin.column},${origin.row})',
          ok: false,
          reason: e.message,
        ),
      );
    }
  }

  void _place(List<String> words) {
    final catalogueId = words[1];
    final origin = CellCoord(int.parse(words[2]), int.parse(words[3]));
    final subtileX = int.parse(words[4]);
    final subtileY = int.parse(words[5]);
    final definition = content.structure(catalogueId);
    if (definition == null ||
        !definition.enabled ||
        !state.unlockedCatalogueIds.contains(catalogueId)) {
      stdout.writeln(
        '✗ "$catalogueId" is not an unlocked model — see catalogue.',
      );
      return;
    }
    try {
      state = startStructureConstruction(
        state,
        content,
        terrain,
        catalogueId: catalogueId,
        origin: origin,
        subtileX: subtileX,
        subtileY: subtileY,
      );
      stdout.writeln(
        '${definition.name} placed at (${origin.column},${origin.row}) '
        'subtile $subtileX,$subtileY · free',
      );
      _act(
        SimAction(
          'place',
          '${definition.name} at (${origin.column},${origin.row})',
          coins: 0,
        ),
      );
    } on WorldRuleViolation catch (e) {
      stdout.writeln('✗ ${e.message}');
      _act(
        SimAction(
          'place',
          '${definition.name} at (${origin.column},${origin.row})',
          ok: false,
          reason: e.message,
        ),
      );
    }
  }

  void _pickup(String propId) {
    final prop = state.props.where((prop) => prop.id == propId).firstOrNull;
    if (prop == null) {
      stdout.writeln('✗ No prop "$propId" — see inspect for ids.');
      return;
    }
    state = pickUpProp(state, content, propId: propId);
    stdout.writeln('Picked up $propId · free, no refund.');
    _act(SimAction('pickup', propId, coins: 0));
  }

  void _inspect(CellCoord cell) {
    final queries = this.queries;
    final terrain = queries.terrainAt(cell);
    final lines = <String>[
      'Cell (${cell.column},${cell.row}): ${queries.ownsCell(cell)
          ? 'owned'
          : terrain.kind == TerrainKind.fog
          ? 'uncharted'
          : 'unowned'} · ${terrain.isLand ? 'land' : 'water'}',
    ];
    final road = queries.roadsByCell[cell];
    if (road != null) lines.add('  road (${road.style.name})');
    final structure = queries.structuresByCell[cell];
    if (structure != null) {
      final model = content.structure(structure.catalogueId);
      lines.add('  ${model?.name ?? structure.catalogueId} (${structure.id})');
    }
    for (final job in state.constructions) {
      if (job.footprint.contains(cell) || job.roadCells.contains(cell)) {
        final model = job.catalogueId == null
            ? job.kind.name
            : content.structure(job.catalogueId!)?.name ?? job.catalogueId;
        lines.add('  under construction: $model (${job.id})');
      }
    }
    for (final prop in queries.propsByCell[cell] ?? const <PlacedProp>[]) {
      final model = content.structure(prop.catalogueId);
      lines.add('  ${model?.name ?? prop.catalogueId} (${prop.id})');
    }
    if (lines.length == 1) lines.add('  nothing here');
    stdout.writeln(lines.join('\n'));
  }

  void _note(String text) {
    if (text.isEmpty) {
      stdout.writeln('✗ note needs text: note <text>');
      return;
    }
    notesFile.writeAsStringSync(
      '### Day ${_dayNumber()} (${state.dateKey})\n$text\n\n',
      mode: FileMode.append,
    );
    stdout.writeln('(noted)');
  }

  void _act(SimAction action) => _actionsToday.add(action);
}

Future<void> main(List<String> args) async {
  var statePath = 'playtest-state.json';
  var logPath = 'playtest-log.jsonl';
  var notesPath = 'playtest-notes.md';
  var contentDir = 'assets/content';
  final commands = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--state' && i + 1 < args.length) {
      statePath = args[++i];
    } else if (args[i] == '--log' && i + 1 < args.length) {
      logPath = args[++i];
    } else if (args[i] == '--notes' && i + 1 < args.length) {
      notesPath = args[++i];
    } else if (args[i] == '--content-dir' && i + 1 < args.length) {
      contentDir = args[++i];
    } else {
      commands.add(args[i]);
    }
  }

  final base = loadBundle(Directory(contentDir));
  final content = ladderABundle(base);
  final terrain = ContentTerrainProvider(content.terrain);

  final stateFile = File(statePath);
  ParcelWorldState state;
  if (stateFile.existsSync()) {
    final envelope = decodeJsonObject(stateFile.readAsStringSync());
    state = sheetTablesToWorld(
      _tablesFromJson(envelope['tables']),
      content: content,
      terrainProvider: terrain,
    );
  } else {
    state = newParcelWorldState(
      content: content,
      seed: 7,
      today: DateTime.utc(2026, 11, 16),
    );
  }

  for (final path in [statePath, logPath, notesPath]) {
    File(path).parent.createSync(recursive: true);
  }

  final session = _PlaySession(
    content: content,
    terrain: terrain,
    state: state,
    logFile: File(logPath),
    notesFile: File(notesPath),
  );
  for (final command in commands) {
    session.run(command);
  }
  session._flushDay();
  stateFile.writeAsStringSync(
    jsonEncode({
      'schema': 1,
      'day': state.constructionDay,
      'tables': _tablesToJson(worldToSheetTables(session.state)),
    }),
  );
}

// Runs the player-simulation matrix — every persona × every seed —
// through the real reducer, writes each run's day log as JSONL, and
// distills the batch into a markdown feel report: cash flow, pacing,
// dead check-ins, and where the money goes.
//
// Usage:
//   dart run tool/sim/simulate_batch.dart [--days 150] [--seeds 6]
//        [--personas planner,casual]
//        [--content-dir docs/sim/playtests/content-snapshot]
//        [--variant ladder-a]
//
// `--content-dir` freezes the base bundle (the playtest snapshot);
// `--variant ladder-a` applies the same in-memory variant the play
// CLI derives, so the control runs the reviewers' exact content.
//
// Output:
//   build/sim/logs/<persona>-seed<n>.jsonl  — one record per day
//   docs/sim/economy-feel-report.md         — the distilled report

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:citysim/content/content_bundle.dart';

import 'content_variants.dart';
import 'harness.dart';
import 'personas.dart';

Future<Map<String, Object?>> readCategory(
  String name,
  String contentDir,
) async => decodeJsonObject(File('$contentDir/$name').readAsStringSync());

Future<void> main(List<String> args) async {
  var days = 150;
  var seedCount = 6;
  var personaIds = const <String>[];
  var writeReport = true;
  var contentDir = 'assets/content';
  var variant = false;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--days' && i + 1 < args.length) {
      days = int.parse(args[++i]);
    } else if (args[i] == '--seeds' && i + 1 < args.length) {
      seedCount = int.parse(args[++i]);
    } else if (args[i] == '--personas' && i + 1 < args.length) {
      personaIds = args[++i].split(',');
    } else if (args[i] == '--no-report') {
      writeReport = false;
    } else if (args[i] == '--content-dir' && i + 1 < args.length) {
      contentDir = args[++i];
    } else if (args[i] == '--variant' && i + 1 < args.length) {
      variant = args[++i] == 'ladder-a';
    }
  }

  var content = parseContentBundle(
    manifest: await readCategory('manifest.json', contentDir),
    catalogue: await readCategory('catalogue.json', contentDir),
    sprites: await readCategory('sprites.json', contentDir),
    economy: await readCategory('economy.json', contentDir),
    ambience: await readCategory('ambience.json', contentDir),
    terrain: await readCategory('terrain.json', contentDir),
    progression: await readCategory('progression.json', contentDir),
  );
  if (variant) content = ladderABundle(content);
  final personas = personaIds.isEmpty
      ? builtinPersonas
      : [
          for (final persona in builtinPersonas)
            if (personaIds.contains(persona.id)) persona,
        ];

  Directory('build/sim/logs').createSync(recursive: true);
  final batch = <_RunSummary>[];
  final batchWatch = Stopwatch()..start();
  for (final persona in personas) {
    for (var seed = 1; seed <= seedCount; seed++) {
      final harness = SimHarness(bundle: content, persona: persona, seed: seed);
      final runWatch = Stopwatch()..start();
      harness.run(days);
      runWatch.stop();
      File('build/sim/logs/${persona.id}-seed$seed.jsonl').writeAsStringSync(
        '${[for (final record in harness.records) jsonEncode(record.toJson())].join('\n')}\n',
      );
      batch.add(_RunSummary(persona.id, persona.name, seed, harness.records));
      stdout.writeln(
        '${persona.id.padRight(8)} seed $seed · '
        '${harness.state.population} pop · '
        '${_fmt(harness.state.coins)} coins · '
        '${_fmt(harness.state.parcels.length)} parcels · '
        '${runWatch.elapsedMilliseconds} ms',
      );
    }
  }
  batchWatch.stop();
  stdout.writeln(
    '${batch.length} runs in ${(batchWatch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s',
  );

  if (writeReport) {
    final report = _buildReport(content, personas, batch, days, seedCount);
    Directory('docs/sim').createSync(recursive: true);
    File('docs/sim/economy-feel-report.md').writeAsStringSync(report);
    stdout.writeln('report written: docs/sim/economy-feel-report.md');
  } else {
    stdout.writeln('report skipped (--no-report); day logs in build/sim/logs/');
  }
}

// ------------------------------------------------------------
// Per-run and per-persona aggregation.
// ------------------------------------------------------------

class _RunSummary {
  _RunSummary(this.personaId, this.personaName, this.seed, this.records);

  final String personaId;
  final String personaName;
  final int seed;
  final List<DayRecord> records;

  List<DayRecord> get credited => [
    for (final record in records)
      if (record.credited) record,
  ];

  /// Check-ins credited up to and including the day the milestone
  /// was reached; null when it never was.
  int? checkInsTo(String milestone) {
    var count = 0;
    for (final record in records) {
      if (record.credited) count++;
      if (record.milestone == milestone) return count;
    }
    return null;
  }

  int get deadCount => records.where((record) => record.dead).length;

  int get deadFirst30 =>
      credited.take(30).where((record) => record.dead).length;

  int get minCoins => records.map((record) => record.coins).reduce(math.min);

  int get maxCoins => records.map((record) => record.coins).reduce(math.max);

  int get dayOfMinCoins {
    var best = records.first;
    for (final record in records) {
      if (record.coins < best.coins) best = record;
    }
    return best.day;
  }

  int? get firstProfitableCheckIn {
    var count = 0;
    for (final record in records) {
      if (!record.credited) continue;
      count++;
      if ((record.net ?? 0) > 0) return count;
    }
    return null;
  }

  double _avgNet(int count, {required bool fromStart}) {
    final nets = [for (final record in credited) record.net ?? 0];
    if (nets.isEmpty) return 0;
    final slice = fromStart
        ? nets.take(count)
        : nets.skip(math.max(0, nets.length - count));
    final list = slice.toList();
    if (list.isEmpty) return 0;
    return list.reduce((a, b) => a + b) / list.length;
  }

  double get netFirst10 => _avgNet(10, fromStart: true);
  double get netLast10 => _avgNet(10, fromStart: false);

  int _spend(String op) => records.fold(0, (sum, record) {
    for (final action in record.actions) {
      if (action.ok && action.op == op) sum += action.coins ?? 0;
    }
    return sum;
  });

  int get spendParcels => _spend('parcel');
  int get spendRoads => _spend('roads');

  int get refused => records.fold(
    0,
    (sum, record) => sum + record.actions.where((action) => !action.ok).length,
  );

  /// Check-ins where the treasury could not cover the next parcel —
  /// the "too poor to grow" feeling.
  int get poorDays => credited
      .where(
        (record) =>
            record.nextParcelPrice != null &&
            record.coins < record.nextParcelPrice!,
      )
      .length;

  int get finalPopulation => records.last.population;
  int get finalCoins => records.last.coins;
}

num _median(List<num> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

// ------------------------------------------------------------
// The report.
// ------------------------------------------------------------

String _buildReport(
  ContentBundle content,
  List<TraitPersona> personas,
  List<_RunSummary> batch,
  int days,
  int seedCount,
) {
  final economy = content.economy;
  final milestones = content.progression.sorted;
  final buffer = StringBuffer();

  void line(String text) => buffer
    ..write(text)
    ..write('\n');
  // Medians of even seed counts land on halves; group those too.
  String fmt(num value) => value == value.roundToDouble()
      ? _fmt(value.round())
      : '${_fmt(value.floor())}.5';

  line('# Economy feel report');
  line('');
  line(
    'Generated ${DateTime.now().toIso8601String().substring(0, 10)} by '
    '`dart run tool/sim/simulate_batch.dart` — scripted personas '
    'playing fresh cities through the real reducer, quotes, and '
    'wallet. $days days × $seedCount seeds × ${personas.length} '
    'personas = ${batch.length} runs.',
  );
  line('');
  line(
    '**Content scale**: treasury start ${_fmt(economy.startingTreasuryCoins)}, '
    'parcel ${_fmt(economy.parcelBaseCoins)} + ${_fmt(economy.parcelPerPopulationCoins)}/pop, '
    'road ${_fmt(economy.roadTileCostCoins)}/tile (+${economy.roadUpkeepCoinsPerTile}/tile upkeep), '
    'bridge ${_fmt(economy.bridgeTileCostCoins)}/tile. Services demanded at '
    '${economy.serviceRequirementPopulation} pop. Migration '
    '${economy.migrationPercentPerCheckIn}%/check-in, employment '
    '${economy.employmentPercentPerCheckIn}%/check-in, job pull '
    '${economy.jobPullPercentPerCheckIn}% of surplus jobs. Buildings '
    'construct free.',
  );
  line('');

  line('## Personas');
  line('');
  for (final persona in personas) {
    line('- **${persona.name}** — ${persona.traits.blurb}');
  }
  line('');

  line('## Headline numbers');
  line('');
  final ladder = [
    for (final milestone in milestones)
      if (milestone.population > 0) milestone,
  ];
  final header = <String>[
    'persona',
    for (final milestone in ladder)
      '→ ${milestone.name.toLowerCase()} (${milestone.population})',
    'first profit',
    'opening net (first 10)',
    'late net (last 10)',
    'min treasury',
    'max treasury',
    'dead days / first 30',
    'poor days',
    'final pop',
    'final coins',
  ];
  line('| ${header.join(' | ')} |');
  line('|${'---|' * header.length}');
  for (final persona in personas) {
    final runs = batch.where((run) => run.personaId == persona.id).toList();
    String milestoneCell(String id) {
      final med = _median([
        for (final run in runs)
          if (run.checkInsTo(id) != null) run.checkInsTo(id)!.toDouble(),
      ]);
      final reached = runs.where((run) => run.checkInsTo(id) != null).length;
      if (reached == 0) return 'never';
      return reached == runs.length
          ? fmt(med)
          : '${fmt(med)} ($reached/${runs.length})';
    }

    final cells = <String>[
      persona.name,
      for (final milestone in ladder) milestoneCell(milestone.id),
      fmt(
        _median([
          for (final run in runs) (run.firstProfitableCheckIn ?? 0).toDouble(),
        ]),
      ),
      fmt(_median([for (final run in runs) run.netFirst10])),
      fmt(_median([for (final run in runs) run.netLast10])),
      '${fmt(_median([for (final run in runs) run.minCoins.toDouble()]))} (day ${fmt(_median([for (final run in runs) run.dayOfMinCoins.toDouble()]))})',
      fmt(_median([for (final run in runs) run.maxCoins.toDouble()])),
      fmt(_median([for (final run in runs) run.deadFirst30.toDouble()])),
      fmt(_median([for (final run in runs) run.poorDays.toDouble()])),
      fmt(_median([for (final run in runs) run.finalPopulation.toDouble()])),
      fmt(_median([for (final run in runs) run.finalCoins.toDouble()])),
    ];
    line('| ${cells.join(' | ')} |');
  }
  line('');
  line(
    '“Opening net” is the average credited net (taxes − upkeep) over a '
    'run’s first ten check-ins; negative values are the opening bleed '
    'before employment fills in. “Poor days” counts check-ins where the '
    'treasury could not cover the next parcel. “Dead days” are '
    'check-ins where nothing arrived, nothing completed, and no action '
    'succeeded — the logged-in-and-logged-off feeling.',
  );
  line('');

  line('## Where the money goes (median across seeds)');
  line('');
  line(
    '| persona | parcels owned | coins on parcels | coins on roads | refused actions |',
  );
  line('|---|---|---|---|---|');
  for (final persona in personas) {
    final runs = batch.where((run) => run.personaId == persona.id).toList();
    line(
      '| ${persona.name} | '
      '${fmt(_median([for (final run in runs) run.records.last.parcels.toDouble()]))} | '
      '${fmt(_median([for (final run in runs) run.spendParcels.toDouble()]))} | '
      '${fmt(_median([for (final run in runs) run.spendRoads.toDouble()]))} | '
      '${fmt(_median([for (final run in runs) run.refused.toDouble()]))} |',
    );
  }
  line('');

  for (final persona in personas) {
    final runs = batch.where((run) => run.personaId == persona.id).toList();
    if (runs.isEmpty) continue;
    line('## ${persona.name} — the curve');
    line('');
    line('Median across $seedCount seeds, by check-in number:');
    line('');
    line('| check-in | coins | net | population | waiting | contentment |');
    line('|---|---|---|---|---|---|');
    const checkpoints = [1, 3, 5, 10, 20, 30, 50, 75, 100, 125, 150];
    for (final k in checkpoints) {
      final rows = [
        for (final run in runs)
          if (run.credited.length >= k) run.credited[k - 1],
      ];
      if (rows.isEmpty) continue;
      line(
        '| $k | ${fmt(_median([for (final row in rows) row.coins.toDouble()]))} | '
        '${fmt(_median([for (final row in rows) (row.net ?? 0).toDouble()]))} | '
        '${fmt(_median([for (final row in rows) row.population.toDouble()]))} | '
        '${fmt(_median([for (final row in rows) row.waiting.toDouble()]))} | '
        '${fmt(_median([for (final row in rows) (row.contentment ?? 100).toDouble()]))} |',
      );
    }
    line('');
  }

  line('## A diary');
  line('');
  final plannerRuns =
      batch.where((run) => run.personaId == personas.first.id).toList()
        ..sort((a, b) => a.finalPopulation.compareTo(b.finalPopulation));
  if (plannerRuns.isNotEmpty) {
    final run = plannerRuns[plannerRuns.length ~/ 2];
    line(
      'The median ${run.personaName} run (seed ${run.seed}), day by day '
      'for the first 45 days — the onboarding stretch where feel '
      'crystallizes:',
    );
    line('');
    line(
      '| day | in? | net | coins | pop | waiting | milestone | what the player did |',
    );
    line('|---|---|---|---|---|---|---|---|');
    for (final record in run.records.take(45)) {
      if (!record.credited) {
        line('| ${record.day} | away | | | | | | |');
        continue;
      }
      final actions = [
        for (final action in record.actions)
          if (action.ok) action.detail,
      ].join('; ');
      final refused = record.actions.where((action) => !action.ok).length;
      line(
        '| ${record.day} | ✓ | ${_fmt(record.net ?? 0)} | '
        '${_fmt(record.coins)} | ${record.population} | '
        '${record.waiting} | ${record.milestone} | '
        '$actions${refused > 0 ? ' · ($refused refused)' : ''} |',
      );
    }
    line('');
  }

  line('## Method and simplifications');
  line('');
  line(
    '- Every action runs through the production reducer '
    '(`purchaseParcel`, `planRoadStretch`, '
    '`startStructureConstruction`, `pickUpProp`, '
    '`checkInWorldForToday`); no rule or price is re-implemented, '
    'so results cannot drift from the shipped game.',
  );
  line(
    '- Personas are readable heuristics, not optimal players: '
    'they cover playstyles, and their mistakes (reactive services, '
    'unsplit road strokes) are deliberate.',
  );
  line(
    '- Simplified away for this pass: bridges, decorations, '
    'connective roads between parcels (frontage roads alone '
    'satisfy road access), prop re-placement, and demolition — '
    'none exists in the game yet or none moves the economy.',
  );
  line(
    '- Founding and expansion pick the land-richest adjacent '
    'parcel; cadence, budgets, and model choices vary by persona '
    'and seed.',
  );
  line(
    '- Each road job delivers one tile per check-in; parallel '
    'jobs deliver in parallel. The Planner exploits this '
    '(single-tile strokes), the others do not — the pacing '
    'difference between its curve and theirs is that exploit’s '
    'measured size.',
  );
  line('');

  return buffer.toString();
}

String _fmt(num value) {
  final rounded = value.round();
  final sign = rounded < 0 ? '-' : '';
  return '$sign${rounded.abs().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => ',')}';
}

// The smooth-demand experiment: the four deterministic personas play
// identical seeds through the real reducer under both demand models
// — classic (the shipped behaviour) and smooth (the experimental
// appeal-and-stock model, selected by content) — and the probe
// measures progression and clamping: how long each dial sits pinned
// at its bounds, which is where a smooth system would stop feeling
// smooth.
//
// Usage:
//   dart run tool/sim/smooth_demand_probe.dart [--days 183] [--seeds 6]
//
// Output:
//   build/sim/logs/smooth-demand/<model>-<persona>-seed<n>.jsonl
//   docs/sim/smooth-demand-report.md

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:citysim/content/content_bundle.dart';

import 'harness.dart';
import 'personas.dart';

Future<Map<String, Object?>> readCategory(String name) async =>
    decodeJsonObject(File('assets/content/$name').readAsStringSync());

Future<void> main(List<String> args) async {
  var days = 183;
  var seedCount = 6;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--days' && i + 1 < args.length) {
      days = int.parse(args[++i]);
    } else if (args[i] == '--seeds' && i + 1 < args.length) {
      seedCount = int.parse(args[++i]);
    }
  }

  final classic = parseContentBundle(
    manifest: await readCategory('manifest.json'),
    catalogue: await readCategory('catalogue.json'),
    sprites: await readCategory('sprites.json'),
    economy: await readCategory('economy.json'),
    ambience: await readCategory('ambience.json'),
    terrain: await readCategory('terrain.json'),
    progression: await readCategory('progression.json'),
  );
  // The smooth dials, exactly as the paper design proposed them:
  // half the population in the labour market, appeal fading across a
  // 5%–20% unemployment band (floored at the contentment floor), a
  // demand stock capped by 10% of beds, and 25% of vacant homes
  // filling per check-in.
  final smooth = ContentBundle(
    manifest: classic.manifest,
    catalogue: classic.catalogue,
    sprites: classic.sprites,
    economy: classic.economy.copyWith(
      demandModel: 'smooth',
      workforceSharePercent: 50,
      listCapPerBedsPercent: 10,
      homeFillPerDayPercent: 25,
      unemploymentFullPercent: 5,
      unemploymentZeroPercent: 20,
    ),
    ambience: classic.ambience,
    terrain: classic.terrain,
    progression: classic.progression,
  );

  Directory('build/sim/logs/smooth-demand').createSync(recursive: true);
  final runs = <_Run>[];
  final watch = Stopwatch()..start();
  for (final persona in builtinPersonas) {
    for (var seed = 1; seed <= seedCount; seed++) {
      for (final model in ['classic', 'smooth']) {
        final bundle = model == 'smooth' ? smooth : classic;
        final harness = SimHarness(
          bundle: bundle,
          persona: persona,
          seed: seed,
        );
        final runWatch = Stopwatch()..start();
        harness.run(days);
        runWatch.stop();
        File(
          'build/sim/logs/smooth-demand/$model-${persona.id}-seed$seed.jsonl',
        ).writeAsStringSync(
          '${[for (final record in harness.records) jsonEncode(record.toJson())].join('\n')}\n',
        );
        final run = _Run(model, persona, seed, harness.records, bundle);
        runs.add(run);
        stdout.writeln(
          '${model.padRight(8)} ${persona.id.padRight(8)} seed $seed · '
          '${run.records.last.population} pop · '
          '${_fmt(run.records.last.coins)} coins · '
          '${run.records.last.parcels} parcels · '
          '${runWatch.elapsedMilliseconds} ms',
        );
      }
    }
  }
  watch.stop();
  stdout.writeln(
    '${runs.length} runs in ${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s',
  );

  final report = _report(classic, runs, days, seedCount);
  Directory('docs/sim').createSync(recursive: true);
  File('docs/sim/smooth-demand-report.md').writeAsStringSync(report);
  stdout.writeln('report written: docs/sim/smooth-demand-report.md');
}

// ------------------------------------------------------------
// Run analytics.
// ------------------------------------------------------------

class _Run {
  _Run(this.model, this.persona, this.seed, this.records, this.bundle);

  final String model;
  final TraitPersona persona;
  final int seed;
  final List<DayRecord> records;
  final ContentBundle bundle;

  List<DayRecord> get credited => [
    for (final record in records)
      if (record.credited) record,
  ];

  int? checkInsTo(String milestone) {
    var count = 0;
    for (final record in records) {
      if (record.credited) count++;
      if (record.milestone == milestone) return count;
    }
    return null;
  }

  int get finalPopulation => records.last.population;
  int get finalCoins => records.last.coins;
  int get finalParcels => records.last.parcels;
}

/// One clamp condition over a run: total credited days it held, and
/// the longest run of consecutive credited days (uncredited days do
/// not break a streak — the state cannot change between check-ins).
class _Clamp {
  _Clamp(this.label, this.totalDays, this.longestStreak);

  final String label;
  final int totalDays;
  final int longestStreak;
}

List<_Clamp> _clamps(_Run run) {
  final economy = run.bundle.economy;
  final conditions = <String, bool Function(DayRecord)>{};
  if (run.model == 'smooth') {
    final zero = economy.unemploymentZeroPercent / 100;
    final floor = economy.contentmentFloorPercent / 100;
    conditions['list at cap (beds)'] = (r) {
      final cap = r.demand?['listCap'];
      return cap is num && r.waiting >= cap;
    };
    conditions['appeal at floor'] = (r) {
      final appeal = r.demand?['appeal'];
      return appeal is num && appeal <= floor + 1e-9;
    };
    conditions['unemployment past band'] = (r) {
      final rate = r.demand?['unemploymentRate'];
      return rate is num && rate >= zero - 1e-9;
    };
    conditions['no arrivals'] = (r) => r.arrived == 0;
    conditions['housing bottleneck'] = (r) {
      final vacant = r.demand?['vacantHousing'];
      return vacant is num && vacant <= 0 && r.waiting > 0;
    };
    conditions['full employment'] = (r) {
      final workforce = r.demand?['workforce'];
      return workforce is num &&
          workforce > 0 &&
          r.employed >= workforce &&
          r.population > 0;
    };
    conditions['job starved'] = (r) {
      final rate = r.demand?['unemploymentRate'];
      final vacantJobs = r.demand?['vacantJobs'];
      return rate is num && rate > 0 && vacantJobs is num && vacantJobs <= 0;
    };
  } else {
    conditions['list at cap (population)'] = (r) =>
        r.waiting >=
        math.max(1, r.population * economy.waitingPopulationCapPercent ~/ 100);
    conditions['tolerance frozen'] = (r) =>
        r.population - r.employed >
        math.max(1, r.population * economy.unemploymentTolerancePercent ~/ 100);
    conditions['contentment at floor'] = (r) =>
        (r.contentment ?? 100) <= economy.contentmentFloorPercent;
    conditions['no arrivals'] = (r) => r.arrived == 0;
  }

  final clamps = <_Clamp>[];
  for (final entry in conditions.entries) {
    var total = 0;
    var streak = 0;
    var best = 0;
    for (final record in run.records) {
      if (!record.credited) continue;
      if (entry.value(record)) {
        total++;
        streak++;
        if (streak > best) best = streak;
      } else {
        streak = 0;
      }
    }
    clamps.add(_Clamp(entry.key, total, best));
  }
  return clamps;
}

// ------------------------------------------------------------
// The report.
// ------------------------------------------------------------

String _report(
  ContentBundle classic,
  List<_Run> runs,
  int days,
  int seedCount,
) {
  final economy = classic.economy;
  final buffer = StringBuffer();
  void line(String text) => buffer
    ..write(text)
    ..write('\n');
  String fmt(num value) => value == value.roundToDouble()
      ? _fmt(value.round())
      : '${_fmt(value.floor())}.5';

  line('# Smooth-demand probe');
  line('');
  line(
    'Generated ${DateTime.now().toIso8601String().substring(0, 10)} by '
    '`dart run tool/sim/smooth_demand_probe.dart` — the four '
    'deterministic personas playing identical seeds through the real '
    'reducer under both demand models. $days days × $seedCount seeds × '
    '${builtinPersonas.length} personas × 2 models = ${runs.length} runs.',
  );
  line('');
  line(
    'The **smooth model** is the paper design: a labour market of '
    '${economy.workforceSharePercent == 100 ? 50 : 50}% of population '
    '(the probe sets 50), appeal = service coverage × a smoothstep '
    'unemployment response across the '
    '${economy.unemploymentFullPercent}%–${economy.unemploymentZeroPercent}% '
    'band (floored at ${economy.contentmentFloorPercent}%), a waiting '
    'list capped at ${economy.listCapPerBedsPercent}% of beds, and '
    '${economy.homeFillPerDayPercent}% of vacant homes filling per '
    'check-in. Classic keeps the shipped formulas. Content selects the '
    'model — the shipped game defaults to classic.',
  );
  line('');

  line('## Headline numbers (median across seeds)');
  line('');
  final ladder = [
    for (final milestone in classic.progression.sorted)
      if (milestone.population > 0) milestone,
  ];
  final header = [
    'persona',
    'model',
    for (final milestone in ladder)
      '→ ${milestone.name.toLowerCase()} (${milestone.population})',
    'final pop',
    'final coins',
    'final parcels',
  ];
  line('| ${header.join(' | ')} |');
  line('|${'---|' * header.length}');
  for (final persona in builtinPersonas) {
    for (final model in ['classic', 'smooth']) {
      final mine = runs
          .where((run) => run.persona.id == persona.id && run.model == model)
          .toList();
      String milestoneCell(String id) {
        final med = _median([
          for (final run in mine)
            if (run.checkInsTo(id) != null) run.checkInsTo(id)!.toDouble(),
        ]);
        final reached = mine.where((run) => run.checkInsTo(id) != null).length;
        if (reached == 0) return 'never';
        return reached == mine.length
            ? fmt(med)
            : '${fmt(med)} ($reached/${mine.length})';
      }

      line(
        '| ${persona.name} | $model | '
        '${[for (final milestone in ladder) milestoneCell(milestone.id)].join(' | ')} | '
        '${fmt(_median([for (final run in mine) run.finalPopulation.toDouble()]))} | '
        '${fmt(_median([for (final run in mine) run.finalCoins.toDouble()]))} | '
        '${fmt(_median([for (final run in mine) run.finalParcels.toDouble()]))} |',
      );
    }
  }
  line('');

  line('## Clamping — how long each dial sits pinned');
  line('');
  line(
    'Total credited days a condition held, and the longest streak of '
    'consecutive credited days (uncredited days do not break a streak '
    '— the state cannot change between check-ins). Medians across '
    'seeds.',
  );
  line('');
  line('| persona | model | condition | total days | longest streak |');
  line('|---|---|---|---|---|');
  for (final persona in builtinPersonas) {
    for (final model in ['classic', 'smooth']) {
      final mine = runs
          .where((run) => run.persona.id == persona.id && run.model == model)
          .toList();
      final byLabel = <String, List<_Clamp>>{};
      for (final run in mine) {
        for (final clamp in _clamps(run)) {
          byLabel.putIfAbsent(clamp.label, () => []).add(clamp);
        }
      }
      for (final entry in byLabel.entries) {
        line(
          '| ${persona.name} | $model | ${entry.key} | '
          '${fmt(_median([for (final c in entry.value) c.totalDays.toDouble()]))} | '
          '${fmt(_median([for (final c in entry.value) c.longestStreak.toDouble()]))} |',
        );
      }
    }
  }
  line('');

  line('## Progression curves (median across seeds, by check-in)');
  line('');
  for (final persona in builtinPersonas) {
    line('### ${persona.name}');
    line('');
    line(
      '| check-in | pop (classic) | pop (smooth) | waiting (classic) | '
      'waiting (smooth) | contentment (classic) | appeal (smooth) |',
    );
    line('|---|---|---|---|---|---|---|');
    const checkpoints = [1, 5, 10, 20, 30, 50, 75, 100, 125, 150, 175];
    for (final k in checkpoints) {
      String cell(
        String model,
        DayRecord Function(DayRecord r) pick,
        num Function(DayRecord r) value,
      ) {
        final rows = [
          for (final run in runs)
            if (run.persona.id == persona.id && run.model == model)
              if (run.credited.length >= k) pick(run.credited[k - 1]),
        ];
        if (rows.isEmpty) return '—';
        return fmt(_median([for (final row in rows) value(row)]));
      }

      final classicRows = [
        for (final run in runs)
          if (run.persona.id == persona.id && run.model == 'classic')
            if (run.credited.length >= k) run.credited[k - 1],
      ];
      if (classicRows.isEmpty) continue;
      line(
        '| $k | '
        '${cell('classic', (r) => r, (r) => r.population)} | '
        '${cell('smooth', (r) => r, (r) => r.population)} | '
        '${cell('classic', (r) => r, (r) => r.waiting)} | '
        '${cell('smooth', (r) => r, (r) => r.waiting)} | '
        '${cell('classic', (r) => r, (r) => r.contentment ?? 100)}% | '
        '${cell('smooth', (r) => r, (r) => ((r.demand?['appeal'] as num?) ?? 0) * 100)}% |',
      );
    }
    line('');
  }

  line('## Method notes');
  line('');
  line(
    '- Both models run through the production reducer — quotes, '
    'wallet, construction, taxes, milestones, persona behaviours '
    'identical. Only the demand pass differs, selected by the '
    'economy\'s `demandModel` (classic by default; the shipped game '
    'is untouched).',
  );
  line(
    '- Taxes under smooth: the home levy measures employment against '
    'the housing\'s workforce (full levy at full workforce '
    'employment, floor unchanged); the commerce levy keeps its '
    'staffing-over-jobs rate, so over-shopped towns earn '
    'proportionally less than under a 100% workforce.',
  );
  line(
    '- Identical seeds pair the runs, but trajectories diverge after '
    'the first differing day (persona choices depend on state), so '
    'compare distributions, not pairs.',
  );
  line('');
  return buffer.toString();
}

num _median(List<num> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

String _fmt(num value) {
  final rounded = value.round();
  final sign = rounded < 0 ? '-' : '';
  return '$sign${rounded.abs().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => ',')}';
}

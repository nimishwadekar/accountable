// Balance sweep: runs the persona matrix against in-memory economy
// variants — taxes, upkeep, infrastructure, and parcel prices scaled
// — and measures the balance signals per variant: the opening bleed,
// the late-game flood, parcel runway (check-ins of net income the
// next parcel costs), poor days, wallet refusals, and milestone
// pacing. Never touches the content files; every variant derives
// from the shipped bundle in memory, so the live content is never at
// risk and the baseline runs under identical code.
//
// Usage:
//   dart run tool/sim/balance_sweep.dart [--days 150] [--seeds 4]

import 'dart:io';
import 'dart:math' as math;

import 'package:citysim/content/content_bundle.dart';

import 'harness.dart';
import 'personas.dart';

Future<Map<String, Object?>> readCategory(String name) async =>
    decodeJsonObject(File('assets/content/$name').readAsStringSync());

/// One candidate economy: multipliers on the shipped catalogue's
/// per-model taxes and upkeep, plus overrides on the infrastructure
/// and parcel prices.
class EconomyVariant {
  const EconomyVariant(
    this.id,
    this.note, {
    this.taxMult = 1.0,
    this.upkeepMult = 1.0,
    this.roadTileCost,
    this.parcelBaseCoins,
    this.parcelPerPopulationCoins,
  });

  final String id;
  final String note;
  final double taxMult;
  final double upkeepMult;
  final int? roadTileCost;
  final int? parcelBaseCoins;
  final int? parcelPerPopulationCoins;

  ContentBundle apply(ContentBundle base) => ContentBundle(
    manifest: base.manifest,
    catalogue: [
      for (final model in base.catalogue)
        model.copyWith(
          taxCoins: (model.taxCoins * taxMult).round(),
          upkeepCoins: (model.upkeepCoins * upkeepMult).round(),
        ),
    ],
    sprites: base.sprites,
    economy: base.economy.copyWith(
      roadTileCostCoins: roadTileCost,
      parcelBaseCoins: parcelBaseCoins,
      parcelPerPopulationCoins: parcelPerPopulationCoins,
    ),
    ambience: base.ambience,
    terrain: base.terrain,
    progression: base.progression,
  );
}

/// The balance signals for one run.
class RunStats {
  RunStats(this.records);

  final List<DayRecord> records;

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

  int get minCoins => records.map((r) => r.coins).reduce(math.min);
  int get maxCoins => records.map((r) => r.coins).reduce(math.max);
  int get finalPopulation => records.last.population;

  double _avgNet(int count, {required bool fromStart}) {
    final nets = [for (final r in credited) r.net ?? 0];
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

  /// Upkeep's share of gross taxes over the last ten check-ins —
  /// whether running the town actually costs.
  double get upkeepShare {
    final recent = credited.skip(math.max(0, credited.length - 10));
    var taxes = 0;
    var upkeep = 0;
    for (final record in recent) {
      taxes += record.taxes ?? 0;
      upkeep += record.upkeep ?? 0;
    }
    return taxes <= 0 ? 0 : upkeep / taxes;
  }

  int get poorDays => credited
      .where((r) => r.nextParcelPrice != null && r.coins < r.nextParcelPrice!)
      .length;

  int get refusals => records.fold(
    0,
    (sum, record) => sum + record.actions.where((a) => !a.ok).length,
  );

  /// Median check-ins of net income the next parcel costs, over the
  /// last thirty check-ins. The balance number: below one and money
  /// is trivial, far into the dozens and the game is a grind. Days
  /// with no positive income count as the cap (99).
  double get lateRunway {
    final recent = credited.skip(math.max(0, credited.length - 30));
    final runways = <double>[];
    for (final record in recent) {
      final price = record.nextParcelPrice;
      if (price == null) continue;
      final net = record.net ?? 0;
      runways.add(net <= 0 ? 99 : math.min(99, price / net).ceilToDouble());
    }
    if (runways.isEmpty) return 0;
    runways.sort();
    final middle = runways.length ~/ 2;
    return runways.length.isOdd
        ? runways[middle]
        : (runways[middle - 1] + runways[middle]) / 2;
  }
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

Future<void> main(List<String> args) async {
  var days = 150;
  var seedCount = 4;
  var only = const <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--days' && i + 1 < args.length) {
      days = int.parse(args[++i]);
    } else if (args[i] == '--seeds' && i + 1 < args.length) {
      seedCount = int.parse(args[++i]);
    } else if (args[i] == '--only' && i + 1 < args.length) {
      only = args[++i].split(',');
    }
  }

  final base = parseContentBundle(
    manifest: await readCategory('manifest.json'),
    catalogue: await readCategory('catalogue.json'),
    sprites: await readCategory('sprites.json'),
    economy: await readCategory('economy.json'),
    ambience: await readCategory('ambience.json'),
    terrain: await readCategory('terrain.json'),
    progression: await readCategory('progression.json'),
  );

  const variants = [
    EconomyVariant('baseline', "today's economy"),
    EconomyVariant('half-tax', 'taxes ×0.5', taxMult: 0.5),
    EconomyVariant('third-tax', 'taxes ×0.35', taxMult: 0.35),
    EconomyVariant(
      'pricey-land',
      'parcel 40k + 500/pop',
      parcelBaseCoins: 40000,
      parcelPerPopulationCoins: 500,
    ),
    EconomyVariant(
      'blend-50',
      'tax ×0.5 · parcel 40k + 500/pop',
      taxMult: 0.5,
      parcelBaseCoins: 40000,
      parcelPerPopulationCoins: 500,
    ),
    EconomyVariant(
      'blend-40',
      'tax ×0.4 · parcel 30k + 400/pop',
      taxMult: 0.4,
      parcelBaseCoins: 30000,
      parcelPerPopulationCoins: 400,
    ),
    EconomyVariant(
      'blend-35',
      'tax ×0.35 · parcel 20k + 300/pop',
      taxMult: 0.35,
      parcelBaseCoins: 20000,
      parcelPerPopulationCoins: 300,
    ),
    EconomyVariant(
      'blend-45u',
      'tax ×0.45 · upkeep ×1.5 · parcel 30k + 450/pop',
      taxMult: 0.45,
      upkeepMult: 1.5,
      parcelBaseCoins: 30000,
      parcelPerPopulationCoins: 450,
    ),
  ];

  // stats[variantId][personaId] = per-seed RunStats.
  final stats = <String, Map<String, List<RunStats>>>{};
  final sweepWatch = Stopwatch()..start();
  for (final variant in variants) {
    if (only.isNotEmpty && !only.contains(variant.id)) continue;
    final content = variant.apply(base);
    final watch = Stopwatch()..start();
    stats[variant.id] = {};
    for (final persona in builtinPersonas) {
      final runs = <RunStats>[];
      for (var seed = 1; seed <= seedCount; seed++) {
        final harness = SimHarness(
          bundle: content,
          persona: persona,
          seed: seed,
        );
        harness.run(days);
        runs.add(RunStats(harness.records));
      }
      stats[variant.id]![persona.id] = runs;
    }
    watch.stop();
    stdout.writeln('${variant.id} done in ${watch.elapsedMilliseconds} ms');
  }
  sweepWatch.stop();
  stdout.writeln(
    '${variants.length} variants in ${(sweepWatch.elapsedMilliseconds / 1000).toStringAsFixed(0)}s',
  );

  String milestoneCell(
    Map<String, List<RunStats>> runs,
    String personaId,
    String milestone,
  ) {
    final med = _median([
      for (final run in runs[personaId] ?? const <RunStats>[])
        if (run.checkInsTo(milestone) != null)
          run.checkInsTo(milestone)!.toDouble(),
    ]);
    if (med == 0) return 'never';
    return med == med.roundToDouble() ? '${med.round()}' : med.toString();
  }

  stdout.writeln('');
  for (final variant in variants) {
    final runs = stats[variant.id];
    if (runs == null) continue;
    stdout.writeln('=== ${variant.id} — ${variant.note} ===');
    for (final persona in builtinPersonas) {
      final list = runs[persona.id]!;
      stdout.writeln(
        '  ${persona.id.padRight(8)} '
        'v${milestoneCell(runs, persona.id, 'village').padLeft(4)} '
        't${milestoneCell(runs, persona.id, 'town').padLeft(4)} '
        'c${milestoneCell(runs, persona.id, 'city').padLeft(4)} · '
        'pop ${_fmt(_median([for (final r in list) r.finalPopulation.toDouble()])).padLeft(6)} · '
        'min ${_fmt(_median([for (final r in list) r.minCoins.toDouble()]))} · '
        'peak ${_fmt(_median([for (final r in list) r.maxCoins.toDouble()]))} · '
        'open ${_median([for (final r in list) r.netFirst10]).round().toString().padLeft(6)} · '
        'late ${_fmt(_median([for (final r in list) r.netLast10])).padLeft(7)} · '
        'upkeep ${(_median([for (final r in list) r.upkeepShare]) * 100).round()}% · '
        'poor ${_fmt(_median([for (final r in list) r.poorDays.toDouble()])).padLeft(3)} · '
        'refused ${_fmt(_median([for (final r in list) r.refusals.toDouble()])).padLeft(3)} · '
        'runway ${_median([for (final r in list) r.lateRunway]).toStringAsFixed(1)}',
      );
    }
    stdout.writeln('');
  }
}

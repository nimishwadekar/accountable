// The road-to-a-million experiment: extended milestone ladders,
// test-only medium- and high-density housing, scaled civic
// buildings, a synthetic big map, and devoted players whose
// construction pipelines grow with the town. Several configurations
// run against each other to find the sweet spots — rung spacing,
// building capacities, and the economy at megacity scale.
//
// Everything derives in memory from the shipped bundle via
// content_variants.dart; the content files are never touched.
//
// Usage:
//   dart run tool/sim/ladder_experiment.dart [--days 800] [--seeds 2]
//        [--only ladder-a] [--dump]

import 'dart:io';
import 'dart:math' as math;

import 'package:citysim/content/content_bundle.dart';

import 'content_variants.dart';
import 'harness.dart';
import 'personas.dart';

Future<Map<String, Object?>> readCategory(String name) async =>
    decodeJsonObject(File('assets/content/$name').readAsStringSync());

class LadderConfig {
  const LadderConfig(
    this.id,
    this.note, {
    this.extension = const [],
    this.extraModelIds = const [],
    this.taxMult = 1.0,
    this.parcelBaseCoins,
    this.parcelPerPopulationCoins,
    this.bigMap = true,
  });

  final String id;
  final String note;

  /// Milestones appended after the shipped rungs.
  final List<MilestoneDefinition> extension;

  /// Which test-only models join the catalogue.
  final List<String> extraModelIds;

  final double taxMult;
  final int? parcelBaseCoins;
  final int? parcelPerPopulationCoins;
  final bool bigMap;

  ContentBundle apply(ContentBundle base) {
    final extras = [
      for (final id in extraModelIds)
        StructureDefinition.fromJson(
          densityModels
              .firstWhere((json) => json['id'] == id)
              .cast<String, Object?>(),
        ),
    ];
    return ContentBundle(
      manifest: base.manifest,
      // The economy multiplier applies to every model alike —
      // shipped and test-only — so densities stay on one price
      // scale ($170/resident, $250/job before the multiplier).
      catalogue: [
        for (final model in [...base.catalogue, ...extras])
          model.copyWith(taxCoins: (model.taxCoins * taxMult).round()),
      ],
      sprites: base.sprites,
      economy: base.economy.copyWith(
        parcelBaseCoins: parcelBaseCoins,
        parcelPerPopulationCoins: parcelPerPopulationCoins,
      ),
      ambience: base.ambience,
      terrain: bigMap ? bigIslandMap() : base.terrain,
      progression: ProgressionContent(
        milestones: [...base.progression.milestones, ...extension],
      ),
    );
  }
}

/// One configuration's measured experience.
class LadderStats {
  LadderStats(this.records);

  final List<DayRecord> records;

  List<DayRecord> get credited => [
    for (final record in records)
      if (record.credited) record,
  ];

  int? dayOf(String milestone) {
    for (final record in records) {
      if (record.milestone == milestone) return record.day;
    }
    return null;
  }

  int get finalPopulation => records.last.population;
  int get finalCoins => records.last.coins;
  int get parcelsOwned => records.last.parcels;
  int get peakProjects =>
      records.map((record) => record.constructions).reduce(math.max);

  /// Player actions (builds plus road strokes) per credited day,
  /// bucketed by town size — the click cost of growth.
  Map<String, double> actionsPerDayByEra() {
    const eras = ['0-2k', '2k-20k', '20k-200k', '200k+'];
    final actions = List<int>.filled(eras.length, 0);
    final days = List<int>.filled(eras.length, 0);
    for (final record in credited) {
      final era = record.population >= 200000
          ? 3
          : record.population >= 20000
          ? 2
          : record.population >= 2000
          ? 1
          : 0;
      days[era]++;
      actions[era] += record.actions.where((action) => action.ok).length;
    }
    return {
      for (var i = 0; i < eras.length; i++)
        eras[i]: days[i] == 0 ? 0.0 : actions[i] / days[i],
    };
  }

  double get netAtEnd {
    final nets = [for (final record in credited) record.net ?? 0];
    if (nets.isEmpty) return 0;
    final recent = nets.skip(math.max(0, nets.length - 10)).toList();
    return recent.reduce((a, b) => a + b) / recent.length;
  }

  double get runwayAtEnd {
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

String _fmt(num value) {
  final rounded = value.round();
  final sign = rounded < 0 ? '-' : '';
  return '$sign${rounded.abs().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => ',')}';
}

Future<void> main(List<String> args) async {
  var days = 800;
  var seedCount = 2;
  var only = const <String>[];
  var dump = false;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--days' && i + 1 < args.length) {
      days = int.parse(args[++i]);
    } else if (args[i] == '--seeds' && i + 1 < args.length) {
      seedCount = int.parse(args[++i]);
    } else if (args[i] == '--only' && i + 1 < args.length) {
      only = args[++i].split(',');
    } else if (args[i] == '--dump') {
      dump = true;
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

  final configs = [
    LadderConfig(
      'today',
      'shipped content and economy, real map — the ceiling as it stands',
      bigMap: false,
    ),
    LadderConfig(
      'ladder-a',
      '×3 rungs · mid 100/tower 400/mega 1,200 · scaled services · blend-40 economy',
      extension: designedExtension,
      extraModelIds: [
        'midrise',
        'tower',
        'mega-tower',
        'office-plaza',
        'regional-hospital',
        'metro-police',
        'metro-fire',
      ],
      taxMult: 0.4,
      parcelBaseCoins: 30000,
      parcelPerPopulationCoins: 400,
    ),
    LadderConfig(
      'ladder-b',
      'sparse ×5 rungs (10k/50k/250k/1M), same content and economy',
      extension: [
        rung('district', 'District', 10000, ['midrise']),
        rung('borough', 'Borough', 50000, [
          'tower',
          'office-plaza',
          'regional-hospital',
          'metro-police',
          'metro-fire',
        ]),
        rung('conurbation', 'Conurbation', 250000, ['mega-tower']),
        rung('megalopolis', 'Megalopolis', 1000000, []),
      ],
      extraModelIds: [
        'midrise',
        'tower',
        'mega-tower',
        'office-plaza',
        'regional-hospital',
        'metro-police',
        'metro-fire',
      ],
      taxMult: 0.4,
      parcelBaseCoins: 30000,
      parcelPerPopulationCoins: 400,
    ),
    LadderConfig(
      'ladder-c',
      'designed rungs, no mega tower — 400-pop cap',
      extension: designedExtension,
      extraModelIds: [
        'midrise',
        'tower',
        'office-plaza',
        'regional-hospital',
        'metro-police',
        'metro-fire',
      ],
      taxMult: 0.4,
      parcelBaseCoins: 30000,
      parcelPerPopulationCoins: 400,
    ),
    LadderConfig(
      'ladder-d',
      'designed rungs, 200-pop towers only — the grind bracket',
      extension: designedExtension,
      extraModelIds: [
        'midrise',
        'tower-small',
        'office-plaza',
        'regional-hospital',
        'metro-police',
        'metro-fire',
      ],
      taxMult: 0.4,
      parcelBaseCoins: 30000,
      parcelPerPopulationCoins: 400,
    ),
    LadderConfig(
      'ladder-e',
      'designed ladder, shipped economy — money at megacity scale',
      extension: designedExtension,
      extraModelIds: [
        'midrise',
        'tower',
        'mega-tower',
        'office-plaza',
        'regional-hospital',
        'metro-police',
        'metro-fire',
      ],
    ),
  ];

  // Two players chase the summit: the comfortable player whose
  // session stays a fixed size, and the grinder whose session grows
  // with the city. The gap between them is the click cost of scale.
  final players = <String, TraitPersona>{
    'summiteer': TraitPersona(
      PersonaTraits(
        id: 'summiteer',
        name: 'The Summiteer',
        blurb:
            'Plays near-daily, builds dense, keeps a construction '
            'pipeline proportional to the town, and chases the '
            'million-person summit within a comfortable session.',
        checkInProbability: 0.95,
        parcelBuffer: 1.1,
        roomCells: 80,
        maxBuildsPerDay: 10,
        jobTargetPercent: 25,
        housingStyle: HousingStyle.dense,
        housingVacancyPercent: 8,
        splitsRoadStrokes: true,
        serviceTarget: 1.0,
        foundingShortlist: 49,
      ),
    ),
    'grinder': TraitPersona(
      PersonaTraits(
        id: 'grinder',
        name: 'The Grinder',
        blurb:
            'The same player, but willing to let the session grow '
            'with the city — one action per 10,000 residents, the '
            'content-ceiling measurement.',
        checkInProbability: 0.95,
        parcelBuffer: 1.1,
        roomCells: 80,
        maxBuildsPerDay: 10,
        buildsPerDayPopDivisor: 10000,
        jobTargetPercent: 25,
        housingStyle: HousingStyle.dense,
        housingVacancyPercent: 8,
        splitsRoadStrokes: true,
        serviceTarget: 1.0,
        foundingShortlist: 49,
      ),
    ),
  };

  final stats = <String, LadderStats>{};
  final watch = Stopwatch()..start();
  for (final config in configs) {
    if (only.isNotEmpty && !only.contains(config.id)) continue;
    final content = config.apply(base);
    final configWatch = Stopwatch()..start();
    for (final player in players.entries) {
      for (var seed = 1; seed <= seedCount; seed++) {
        final harness = SimHarness(
          bundle: content,
          persona: player.value,
          seed: seed,
        );
        harness.run(days);
        stats['${config.id}/${player.key}/$seed'] = LadderStats(
          harness.records,
        );
        if (dump) {
          for (final record
              in harness.records.reversed
                  .where((record) => record.credited)
                  .take(12)) {
            stdout.writeln(
              '    d${record.day} pop ${record.population} '
              'cap ${record.residentialCapacity} wait ${record.waiting} '
              'arrived ${record.arrived} net ${record.net} '
              'projects ${record.constructions} '
              'actions ${record.actions.where((a) => a.ok).length}',
            );
          }
        }
      }
    }
    configWatch.stop();
    stdout.writeln(
      '${config.id} done in ${(configWatch.elapsedMilliseconds / 1000).toStringAsFixed(0)}s',
    );
  }
  watch.stop();
  stdout.writeln(
    'total ${(watch.elapsedMilliseconds / 1000).toStringAsFixed(0)}s',
  );

  const rungOrder = [
    'regional-capital',
    'district',
    'borough',
    'conurbation',
    'megacity',
    'metroplex',
    'megalopolis',
  ];

  String cell(LadderStats stats, String rung) {
    final day = stats.dayOf(rung);
    if (day == null) return '—'.padLeft(9);
    return 'd$day'.padLeft(9);
  }

  stdout.writeln('');
  for (final config in configs) {
    final entries = stats.entries
        .where((entry) => entry.key.startsWith('${config.id}/'))
        .toList();
    if (entries.isEmpty) continue;
    stdout.writeln('=== ${config.id} — ${config.note} ===');
    for (final entry in entries) {
      final run = entry.value;
      final label = entry.key.split('/').skip(1).join('/');
      final actions = run.actionsPerDayByEra();
      stdout.writeln(
        '  $label · '
        '${[for (final rung in rungOrder) cell(run, rung)].join(' ')} · '
        'final ${_fmt(run.finalPopulation)} pop · '
        '${_fmt(run.finalCoins)} coins · '
        '${run.parcelsOwned} parcels · '
        'peak ${run.peakProjects} projects',
      );
      stdout.writeln(
        '    actions/day: 0-2k ${actions['0-2k']!.toStringAsFixed(1)} · '
        '2k-20k ${actions['2k-20k']!.toStringAsFixed(1)} · '
        '20k-200k ${actions['20k-200k']!.toStringAsFixed(1)} · '
        '200k+ ${actions['200k+']!.toStringAsFixed(1)} · '
        'net@end ${_fmt(run.netAtEnd)} · '
        'runway@end ${run.runwayAtEnd.toStringAsFixed(1)}',
      );
    }
    stdout.writeln('');
  }
}

// Player archetypes for the simulation harness. Each persona is a
// bundle of habits: how often it opens the game, what it builds,
// when it buys land, and how savvy it is about the game's quieter
// mechanics. The traits are deliberately readable — the point is
// coverage of playstyles, not optimal play.
//
// Not part of the app or tests; drive through
// tool/sim/simulate_batch.dart.

import 'dart:math' as math;

import 'package:citysim/content/content_bundle.dart';

import 'harness.dart';

/// How a persona picks its homes.
enum HousingStyle {
  /// Cheapest to keep — small and mobile homes forever.
  cheap,

  /// Most residents per footprint cell — density once it unlocks.
  dense,

  /// The biggest home model available — the suburban sprawler.
  roomy,
}

class PersonaTraits {
  const PersonaTraits({
    required this.id,
    required this.name,
    required this.blurb,
    required this.checkInProbability,
    this.weekdaysOnly = false,
    this.parcelBuffer = 1.2,
    this.roomCells = 24,
    this.maxBuildsPerDay = 2,
    this.buildsPerDayPopDivisor,
    this.jobTargetPercent = 0,
    this.housingStyle = HousingStyle.cheap,
    this.housingVacancyTarget = 4,
    this.housingVacancyPercent,
    this.splitsRoadStrokes = false,
    this.serviceTarget = 0.85,
    this.foundingShortlist = 4,
  });

  final String id;
  final String name;

  /// One line of who this player is, for the report.
  final String blurb;

  /// Chance of opening the game on any given calendar day.
  final double checkInProbability;

  /// Only plays on weekdays.
  final bool weekdaysOnly;

  /// Buys land once coins reach the parcel price times this — the
  /// saver's cushion.
  final double parcelBuffer;

  /// Free land cells below which the player wants another parcel.
  /// Null buys whenever the wallet allows — the sprawler, who wants
  /// land because it is there.
  final int? roomCells;

  /// Successful builds per day — the player's attention budget.
  final int maxBuildsPerDay;

  /// When set, the budget grows with the town: the maximum of the
  /// flat budget and the population over this divisor — the
  /// grinding devotee whose session length scales with the city.
  /// Null keeps the flat budget.
  final int? buildsPerDayPopDivisor;

  /// Open job positions kept in the town, as a share of population
  /// (minimum six). Zero is the reactive player, who builds commerce
  /// only when the last job fills.
  final int jobTargetPercent;

  final HousingStyle housingStyle;

  /// Vacant beds the persona keeps ahead of the waiting list.
  final int housingVacancyTarget;

  /// When set, the vacancy target becomes this share of the
  /// population instead — the scaled player whose construction
  /// pipeline grows with the town. Null keeps the flat target.
  final int? housingVacancyPercent;

  /// Plans each frontage tile as its own road job, so they deliver
  /// in parallel — the savvy-player trick.
  final bool splitsRoadStrokes;

  /// Service coverage the persona keeps above the requirement
  /// population; low targets are the reactive player who lets
  /// contentment sag before reacting.
  final double serviceTarget;

  /// How many spots the player scouts before founding.
  final int foundingShortlist;
}

class TraitPersona implements PlayerPersona {
  TraitPersona(this.traits);

  final PersonaTraits traits;

  @override
  String get id => traits.id;

  @override
  String get name => traits.name;

  @override
  bool checksInToday(int day, math.Random rng) {
    if (traits.weekdaysOnly) {
      final date = DateTime.utc(2026, 11, 16).add(Duration(days: day));
      if (date.weekday == DateTime.saturday ||
          date.weekday == DateTime.sunday) {
        return false;
      }
    }
    return rng.nextDouble() < traits.checkInProbability;
  }

  @override
  void playDay(SimHarness h) {
    if (h.state.parcels.isEmpty) {
      h.foundAt(h.chooseFoundingParcel(shortlist: traits.foundingShortlist));
    }
    var builds = traits.maxBuildsPerDay;
    if (traits.buildsPerDayPopDivisor != null) {
      builds = math.max(
        builds,
        h.state.population ~/ traits.buildsPerDayPopDivisor!,
      );
    }

    // Services first — contentment multiplies every coin the town
    // makes, so the planner never lets it sag. A planned frontage
    // road counts as progress: the building lands the day the tiles
    // creep in.
    if (h.state.population >= h.content.economy.serviceRequirementPopulation) {
      for (final category in h.content.economy.requiredServiceCategories) {
        if (builds <= 0) break;
        if (h.serviceCoveragePlanned(category) < traits.serviceTarget) {
          final model = _pickService(h, category);
          if (model == null) continue;
          final outcome = h.attemptBuild(
            model,
            splitStrokes: traits.splitsRoadStrokes,
          );
          if (outcome == BuildOutcome.built ||
              outcome == BuildOutcome.roadPlanned) {
            builds--;
          }
        }
      }
    }

    // Commerce: ahead of the curve or right behind it.
    while (builds > 0) {
      final vacancy = h.jobCapacityPlanned - h.state.employedPopulation;
      final target = traits.jobTargetPercent == 0
          ? 2
          : math.max(6, h.state.population * traits.jobTargetPercent ~/ 100);
      if (vacancy >= target) break;
      final ladder = _commerceLadder(h, dense: traits.jobTargetPercent > 0);
      if (ladder.isEmpty) break;
      // The street first: a smaller model that lines up today beats
      // paving toward the big one — the corner market employs the
      // jobless while the office waits for its street. When nothing
      // lines up, the ladder's head paves.
      String? pick;
      for (final model in ladder) {
        if (h.canLineUp(model)) {
          pick = model;
          break;
        }
      }
      pick ??= ladder.first;
      final outcome = h.attemptBuild(
        pick,
        splitStrokes: traits.splitsRoadStrokes,
      );
      if (outcome == BuildOutcome.built ||
          outcome == BuildOutcome.roadPlanned) {
        builds--;
        continue;
      }
      break;
    }

    // Homes for the waiting list. The vacancy target scales with the
    // town when the persona sets a percent: a devoted player's
    // construction pipeline grows with the city.
    final vacancyTarget = traits.housingVacancyPercent == null
        ? traits.housingVacancyTarget
        : math.max(
            traits.housingVacancyTarget,
            h.state.population * traits.housingVacancyPercent! ~/ 100,
          );
    while (builds > 0) {
      final vacancy = h.residentialCapacityPlanned - h.state.population;
      if (h.state.waitingPopulation <= 0 || vacancy >= vacancyTarget) {
        break;
      }
      final model = _pickHome(h);
      if (model == null) break;
      final outcome = h.attemptBuild(
        model,
        splitStrokes: traits.splitsRoadStrokes,
      );
      if (outcome == BuildOutcome.built ||
          outcome == BuildOutcome.roadPlanned) {
        builds--;
        continue;
      }
      break;
    }

    // Land: when the town is running out of room, on the persona's
    // cushion — or, for the sprawler, whenever the wallet allows.
    final price = h.nextParcelPrice();
    if (price != null && h.state.coins >= price * traits.parcelBuffer) {
      final wantsLand =
          traits.roomCells == null || h.freeLandCells < traits.roomCells!;
      if (wantsLand || h.noSpaceThisSession) {
        h.buyBestAdjacentParcel();
      }
    }
  }

  String? _pickHome(SimHarness h) {
    final options = _unlocked(h, (model) => model.isResidential);
    if (options.isEmpty) return null;
    switch (traits.housingStyle) {
      case HousingStyle.cheap:
        return _minBy(options, (model) => model.upkeepCoins).id;
      case HousingStyle.dense:
        return _maxBy(options, (model) => model.population / _area(model)).id;
      case HousingStyle.roomy:
        return _maxBy(options, (model) => model.population.toDouble()).id;
    }
  }

  List<String> _commerceLadder(SimHarness h, {required bool dense}) {
    final options = _unlocked(h, (model) => model.isCommerce);
    if (options.isEmpty) return const [];
    options.sort(
      dense
          ? (a, b) => (b.jobs / _area(b)).compareTo(a.jobs / _area(a))
          : (a, b) => a.upkeepCoins.compareTo(b.upkeepCoins),
    );
    return [for (final model in options) model.id];
  }

  String? _pickService(SimHarness h, String category) {
    final options = _unlocked(h, (model) => model.serviceCategory == category);
    if (options.isEmpty) return null;
    // The smallest building that covers the whole town, so small
    // towns get clinics and metropolises get regional hospitals —
    // picking by upkeep alone would place hundreds of small ones in
    // a big city. When nothing covers the town yet, take the largest
    // and let the loop add more.
    final covering = [
      for (final model in options)
        if (model.serviceCapacity >= h.state.population) model,
    ];
    if (covering.isNotEmpty) {
      return _minBy(covering, (model) => model.serviceCapacity).id;
    }
    return _maxBy(options, (model) => model.serviceCapacity).id;
  }

  List<StructureDefinition> _unlocked(
    SimHarness h,
    bool Function(StructureDefinition) filter,
  ) => [
    for (final model in h.content.catalogue)
      if (model.enabled &&
          filter(model) &&
          h.state.unlockedCatalogueIds.contains(model.id))
        model,
  ];

  double _area(StructureDefinition model) =>
      (model.footprintColumns * model.footprintRows).toDouble();

  T _minBy<T>(List<T> items, num Function(T) score) {
    var best = items.first;
    var bestScore = score(best);
    for (final item in items.skip(1)) {
      final value = score(item);
      if (value < bestScore) {
        best = item;
        bestScore = value;
      }
    }
    return best;
  }

  T _maxBy<T>(List<T> items, num Function(T) score) {
    var best = items.first;
    var bestScore = score(best);
    for (final item in items.skip(1)) {
      final value = score(item);
      if (value > bestScore) {
        best = item;
        bestScore = value;
      }
    }
    return best;
  }
}

/// The shipped archetype set.
final List<TraitPersona> builtinPersonas = [
  TraitPersona(
    PersonaTraits(
      id: 'planner',
      name: 'The Planner',
      blurb:
          'Plays near-daily, surveys the whole map before founding, '
          'keeps a quarter of the population in open jobs, builds '
          'dense, keeps services covered, and knows parallel road '
          'jobs deliver in parallel.',
      checkInProbability: 0.95,
      parcelBuffer: 1.1,
      roomCells: 40,
      maxBuildsPerDay: 4,
      jobTargetPercent: 25,
      housingStyle: HousingStyle.dense,
      housingVacancyTarget: 10,
      splitsRoadStrokes: true,
      serviceTarget: 1.0,
      foundingShortlist: 49,
    ),
  ),
  TraitPersona(
    PersonaTraits(
      id: 'casual',
      name: 'The Casual',
      blurb:
          'Plays a bit more than half the days, takes the first decent '
          'founding spot, builds small cheap homes, reacts to problems '
          'rather than anticipating them, and lets contentment sag '
          'before fixing it.',
      checkInProbability: 0.6,
      parcelBuffer: 1.3,
      roomCells: 24,
      maxBuildsPerDay: 2,
      jobTargetPercent: 0,
      housingStyle: HousingStyle.cheap,
      housingVacancyTarget: 3,
      splitsRoadStrokes: false,
      serviceTarget: 0.6,
      foundingShortlist: 4,
    ),
  ),
  TraitPersona(
    PersonaTraits(
      id: 'saver',
      name: 'The Saver',
      blurb:
          'Plays weekdays, hoards a cushion of more than double the '
          'parcel price before buying land, builds slowly, and keeps '
          'services tidy. The player who wants the treasury never to '
          'feel thin.',
      checkInProbability: 0.9,
      weekdaysOnly: true,
      parcelBuffer: 2.2,
      roomCells: 24,
      maxBuildsPerDay: 2,
      jobTargetPercent: 8,
      housingStyle: HousingStyle.cheap,
      housingVacancyTarget: 4,
      splitsRoadStrokes: false,
      serviceTarget: 0.9,
      foundingShortlist: 6,
    ),
  ),
  TraitPersona(
    PersonaTraits(
      id: 'sprawler',
      name: 'The Sprawler',
      blurb:
          'Plays most days, buys every parcel the moment the wallet '
          'allows, and fills them with the biggest homes available. '
          'The suburban spread, roads and all.',
      checkInProbability: 0.8,
      parcelBuffer: 1.0,
      roomCells: null,
      maxBuildsPerDay: 3,
      jobTargetPercent: 15,
      housingStyle: HousingStyle.roomy,
      housingVacancyTarget: 8,
      splitsRoadStrokes: false,
      serviceTarget: 0.8,
      foundingShortlist: 8,
    ),
  ),
];

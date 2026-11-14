"""Reworks townLedger, validation, and the parcel quote to the
aggregate state."""

PATH = 'lib/world/world_rules.dart'


def rep(label, old, new):
    src = open(PATH).read()
    assert old in src, f'missing: {label}'
    open(PATH, 'w').write(src.replace(old, new, 1))
    print(f'applied: {label}')


rep(
    'ledger class',
    """class TownLedger {
  const TownLedger({
    required this.grossTaxes,
    required this.taxes,
    required this.upkeep,
    required this.contentment,
    required this.residentialDemand,
    required this.commercialDemand,
    required this.coverage,
  });

  /// Taxes before contentment: each building's flat tax scaled by
  /// its occupancy fraction.
  final double grossTaxes;

  /// Taxes after contentment, rounded once on the total.
  final int taxes;
  final int upkeep;
  int get net => taxes - upkeep;

  /// Contentment as a percentage — average service coverage above
  /// the requirement population, 100 below it, never under the
  /// floor.
  final int contentment;

  /// Positive demand in household units, clamped at zero.
  final int residentialDemand;
  final int commercialDemand;

  /// Coverage per required service category (0..1). Empty below the
  /// requirement population — nothing is demanded yet.
  final Map<String, double> coverage;
}""",
    """class TownLedger {
  const TownLedger({
    required this.grossTaxes,
    required this.taxes,
    required this.upkeep,
    required this.contentment,
    required this.residentialDemand,
    required this.employmentDemand,
    required this.residentialVacancy,
    required this.jobVacancy,
    required this.coverage,
  });

  /// Taxes before contentment: home taxes scaled by the employment
  /// rate over residential capacity, commerce taxes by the staffing
  /// rate over job capacity. Only employed people pay.
  final double grossTaxes;

  /// Taxes after contentment, rounded once on the total.
  final int taxes;
  final int upkeep;
  int get net => taxes - upkeep;

  /// Contentment as a percentage — average service coverage above
  /// the requirement population, 100 below it, never under the
  /// floor.
  final int contentment;

  /// The residential waiting list: households that want in but
  /// cannot (no housing).
  final int residentialDemand;

  /// Unemployed citizens: households living in town without a job.
  final int employmentDemand;

  /// Vacant home capacity and vacant job positions. Negative
  /// residential vacancy grandfathers a population above capacity.
  final int residentialVacancy;
  final int jobVacancy;

  /// Coverage per required service category (0..1). Empty below the
  /// requirement population — nothing is demanded yet.
  final Map<String, double> coverage;
}""",
)

rep(
    'ledger body',
    """TownLedger townLedger(ParcelWorldState state, ContentBundle content) {
  final economy = content.economy;
  var gross = 0.0;
  var upkeep = 0;
  for (final structure in state.structures) {
    final model = content.structure(structure.catalogueId);
    if (model == null) continue;
    final capacity = model.isResidential
        ? model.households
        : model.isCommerce
        ? model.jobs
        : 0;
    // Occupancy scales tax; upkeep is always owed in full. Civic
    // buildings (capacity zero) are simply always active.
    gross += capacity <= 0
        ? model.taxCoins
        : model.taxCoins * structure.occupancy / capacity;
    upkeep += model.upkeepCoins;
  }
  var bridgeTiles = 0;
  for (final bridge in state.bridges) {
    bridgeTiles += bridge.waterCells.length;
  }
  for (final job in state.constructions) {
    if (job.kind != WorldConstructionKind.bridge) continue;
    bridgeTiles += (job.stagesDone - 1).clamp(0, job.waterCells.length);
  }
  gross += state.roads.length * economy.roadTaxCoinsPerTile;
  upkeep += state.roads.length * economy.roadUpkeepCoinsPerTile;
  gross += bridgeTiles * economy.bridgeTaxCoinsPerTile;
  upkeep += bridgeTiles * economy.bridgeUpkeepCoinsPerTile;

  final population = state.populationOf(content);
  final jobs = state.jobsOf(content);

  // Contentment: average coverage across the required service
  // categories once the town is big enough to be demanding; full
  // contentment below that; the floor applies always.
  final coverage = <String, double>{};
  var contentment = 100;
  if (population >= economy.serviceRequirementPopulation) {
    var sum = 0.0;
    for (final category in economy.requiredServiceCategories) {
      var capacity = 0;
      for (final structure in state.structures) {
        final model = content.structure(structure.catalogueId);
        if (model?.serviceCategory == category) {
          capacity += model?.serviceCapacity ?? 0;
        }
      }
      final ratio = population <= 0
          ? 1.0
          : (capacity / population).clamp(0.0, 1.0);
      coverage[category] = ratio;
      sum += ratio;
    }
    final average = economy.requiredServiceCategories.isEmpty
        ? 1.0
        : sum / economy.requiredServiceCategories.length;
    contentment = (average * 100).round();
  }
  if (contentment < economy.contentmentFloorPercent) {
    contentment = economy.contentmentFloorPercent;
  }

  final taxes = (gross * contentment / 100).round();
  return TownLedger(
    grossTaxes: gross,
    taxes: taxes,
    upkeep: upkeep,
    contentment: contentment,
    residentialDemand: (economy.frontierAppealHouseholds + jobs - population)
        .clamp(0, 1 << 30),
    commercialDemand: (population - jobs).clamp(0, 1 << 30),
    coverage: coverage,
  );
}""",
    """TownLedger townLedger(ParcelWorldState state, ContentBundle content) {
  final economy = content.economy;
  final population = state.population;
  final employed = state.employedPopulation;

  // Capacities and taxes are content; occupancy is the stored
  // aggregate. Only employed people pay: home taxes scale by the
  // employment rate over residential capacity, commerce taxes by
  // the staffing rate over job capacity — every home pays the
  // average rate, so unemployment reads as a town condition, not a
  // named household's. Civic buildings are always active. Upkeep
  // is always owed in full, vacant or not.
  var residentialCapacity = 0;
  var jobCapacity = 0;
  var homeTax = 0;
  var commerceTax = 0;
  var civicTax = 0;
  var upkeep = 0;
  for (final structure in state.structures) {
    final model = content.structure(structure.catalogueId);
    if (model == null) continue;
    if (model.isResidential) {
      residentialCapacity += model.households;
      homeTax += model.taxCoins;
    } else if (model.isCommerce) {
      jobCapacity += model.jobs;
      commerceTax += model.taxCoins;
    } else {
      civicTax += model.taxCoins;
    }
    upkeep += model.upkeepCoins;
  }
  var gross = 0.0;
  if (residentialCapacity > 0) {
    gross += homeTax * employed / residentialCapacity;
  }
  if (jobCapacity > 0) {
    gross += commerceTax * employed / jobCapacity;
  }
  gross += civicTax;
  var bridgeTiles = 0;
  for (final bridge in state.bridges) {
    bridgeTiles += bridge.waterCells.length;
  }
  for (final job in state.constructions) {
    if (job.kind != WorldConstructionKind.bridge) continue;
    bridgeTiles += (job.stagesDone - 1).clamp(0, job.waterCells.length);
  }
  gross += state.roads.length * economy.roadTaxCoinsPerTile;
  upkeep += state.roads.length * economy.roadUpkeepCoinsPerTile;
  gross += bridgeTiles * economy.bridgeTaxCoinsPerTile;
  upkeep += bridgeTiles * economy.bridgeUpkeepCoinsPerTile;

  // Contentment: average coverage across the required service
  // categories once the town is big enough to be demanding; full
  // contentment below that; the floor applies always.
  final coverage = <String, double>{};
  var contentment = 100;
  if (population >= economy.serviceRequirementPopulation) {
    var sum = 0.0;
    for (final category in economy.requiredServiceCategories) {
      var capacity = 0;
      for (final structure in state.structures) {
        final model = content.structure(structure.catalogueId);
        if (model?.serviceCategory == category) {
          capacity += model?.serviceCapacity ?? 0;
        }
      }
      final ratio = population <= 0
          ? 1.0
          : (capacity / population).clamp(0.0, 1.0);
      coverage[category] = ratio;
      sum += ratio;
    }
    final average = economy.requiredServiceCategories.isEmpty
        ? 1.0
        : sum / economy.requiredServiceCategories.length;
    contentment = (average * 100).round();
  }
  if (contentment < economy.contentmentFloorPercent) {
    contentment = economy.contentmentFloorPercent;
  }

  final taxes = (gross * contentment / 100).round();
  return TownLedger(
    grossTaxes: gross,
    taxes: taxes,
    upkeep: upkeep,
    contentment: contentment,
    residentialDemand: state.waitingHouseholds,
    employmentDemand: state.unemployment,
    residentialVacancy: residentialCapacity - population,
    jobVacancy: jobCapacity - employed,
    coverage: coverage,
  );
}""",
)

rep(
    'parcel quote',
    "    price: base + perPopulation * state.populationOf(content),",
    "    price: base + perPopulation * state.population,",
)

rep(
    'capacity validation',
    """          content.economy.builderCapacityForPopulation(
            state.populationOf(content),
          ) ||""",
    """          content.economy.builderCapacityForPopulation(
            state.population,
          ) ||""",
)

rep(
    'structure occupancy validation',
    """        structure.pricePaid < 0 ||
        structure.occupancy < 0 ||
        structure.completedAtDay < 0 ||""",
    """        structure.pricePaid < 0 ||
        structure.completedAtDay < 0 ||""",
)

rep(
    'unlock validation',
    """      .where(
        (model) => state.populationOf(content) >= model.unlockAtPopulation,
      )""",
    """      .where((model) => state.population >= model.unlockAtPopulation)""",
)

rep(
    'counter invariants',
    """      state.coins < 0 ||
      state.totalCoinsEarned < 0 ||
      state.totalCoinsSpent < 0 ||""",
    """      state.coins < 0 ||
      state.totalCoinsEarned < 0 ||
      state.totalCoinsSpent < 0 ||
      state.waitingHouseholds < 0 ||
      state.population < 0 ||
      state.employedPopulation < 0 ||
      state.employedPopulation > state.population ||""",
)

"""App UI: Town card, header, inspector, report — aggregate state."""

PATH = 'lib/parcel_city_app.dart'


def rep(label, old, new):
    src = open(PATH).read()
    assert old in src, f'missing: {label}'
    open(PATH, 'w').write(src.replace(old, new, 1))
    print(f'applied: {label}')


rep(
    'town card',
    """  Widget _townCard(ParcelWorldState world) {
    final ledger = townLedger(world, _requireContent);
    final population = world.populationOf(_requireContent);
    final jobs = world.jobsOf(_requireContent);
    final barMax = _requireContent.economy.frontierAppealHouseholds < 1
        ? 1
        : _requireContent.economy.frontierAppealHouseholds;
    final contentmentColor = ledger.contentment >= 90
        ? const Color(0xFF1E6552)
        : ledger.contentment >= 60
        ? const Color(0xFF9A5B2B)
        : const Color(0xFFA03D2B);
    return _PanelCard(
      title: 'Town',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Contentment ${ledger.contentment}% · taxes ×'
            '${(ledger.contentment / 100).toStringAsFixed(2)}',
            style: TextStyle(color: contentmentColor),
          ),
          if (ledger.coverage.isEmpty)
            Text(
              'No services demanded yet — they matter from '
              '${_requireContent.economy.serviceRequirementPopulation} '
              'households.',
              style: const TextStyle(fontSize: 11, color: Color(0xFF617267)),
            )
          else
            for (final category in ledger.coverage.keys)
              Text(
                '${category[0].toUpperCase()}${category.substring(1)} '
                'coverage ${(ledger.coverage[category]! * 100).round()}%',
                style: const TextStyle(fontSize: 11, color: Color(0xFF617267)),
              ),
          const SizedBox(height: 6),
          _demandRow(
            'Residential demand',
            ledger.residentialDemand,
            barMax,
            'households wanting homes',
          ),
          _demandRow(
            'Commercial demand',
            ledger.commercialDemand,
            barMax,
            'positions waiting for staff',
          ),
          Text(
            '$population households · $jobs jobs',
            style: const TextStyle(fontSize: 11, color: Color(0xFF617267)),
          ),
        ],
      ),
    );
  }""",
    """  Widget _townCard(ParcelWorldState world) {
    final ledger = townLedger(world, _requireContent);
    final economy = _requireContent.economy;
    // The bars' scales: the waiting list's cap and the population.
    final resiBarMax = (world.population * economy.waitingHouseholdsCapPercent /
                100)
            .floor() <
            1
        ? 1
        : (world.population * economy.waitingHouseholdsCapPercent / 100)
              .floor();
    final employmentBarMax = world.population < 1
        ? 1
        : world.population;
    final contentmentColor = ledger.contentment >= 90
        ? const Color(0xFF1E6552)
        : ledger.contentment >= 60
        ? const Color(0xFF9A5B2B)
        : const Color(0xFFA03D2B);
    return _PanelCard(
      title: 'Town',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Contentment ${ledger.contentment}% · taxes ×'
            '${(ledger.contentment / 100).toStringAsFixed(2)}',
            style: TextStyle(color: contentmentColor),
          ),
          if (ledger.coverage.isEmpty)
            Text(
              'No services demanded yet — they matter from '
              '${economy.serviceRequirementPopulation} '
              'households.',
              style: const TextStyle(fontSize: 11, color: Color(0xFF617267)),
            )
          else
            for (final category in ledger.coverage.keys)
              Text(
                '${category[0].toUpperCase()}${category.substring(1)} '
                'coverage ${(ledger.coverage[category]! * 100).round()}%',
                style: const TextStyle(fontSize: 11, color: Color(0xFF617267)),
              ),
          const SizedBox(height: 6),
          _demandRow(
            'Residential demand',
            ledger.residentialDemand,
            resiBarMax,
            'households waiting to move in',
          ),
          _demandRow(
            'Employment demand',
            ledger.employmentDemand,
            employmentBarMax,
            'citizens needing jobs',
          ),
          Text(
            '${world.population} households · ${world.employedPopulation} '
            'employed · ${ledger.residentialVacancy} vacant homes · '
            '${ledger.jobVacancy} open jobs',
            style: const TextStyle(fontSize: 11, color: Color(0xFF617267)),
          ),
        ],
      ),
    );
  }""",
)

rep(
    'header call',
    """                nextReportNet: townLedger(world, _requireContent).net,
                population: world.populationOf(_requireContent),""",
    """                nextReportNet: townLedger(world, _requireContent).net,
                population: world.population,""",
)

rep(
    'parcel dialogs population',
    """'${world.populationOf(_requireContent)} population. '""",
    """'${world.population} population. '""",
)

rep(
    'parcel panel population',
    """'${world.populationOf(_requireContent)} population.',""",
    """'${world.population} population.',""",
)

rep(
    'inspector occupancy lines',
    """          if (structure != null) ...[
            Text(
              _requireContent.structure(structure.catalogueId)?.name ??
                  'Structure',
            ),
            if (_occupancyLabel(structure) case final label?) Text(label),
          ],""",
    """          if (structure != null) ...[
            Text(
              _requireContent.structure(structure.catalogueId)?.name ??
                  'Structure',
            ),
            if (_capacityLabel(structure) case final label?) Text(label),
          ],""",
)

rep(
    'occupancy helper to capacity',
    """  /// Occupancy text for the inspector: households for homes,
  /// staffed positions for commerce, nothing for civic.
  String? _occupancyLabel(PlacedStructure structure) {
    final model = _requireContent.structure(structure.catalogueId);
    if (model == null) return null;
    if (model.isResidential) {
      return structure.occupancy == 0
          ? 'Vacant — waiting for a household'
          : '${structure.occupancy} of ${model.households} '
              'household(s) occupied';
    }
    if (model.isCommerce) {
      return structure.occupancy == 0
          ? 'Shuttered — waiting for customers'
          : '${structure.occupancy} of ${model.jobs} '
              'position(s) staffed';
    }
    return null;
  }""",
    """  /// Capacity text for the inspector — occupancy itself is a town
  /// aggregate, so a building shows what it offers.
  String? _capacityLabel(PlacedStructure structure) {
    final model = _requireContent.structure(structure.catalogueId);
    if (model == null) return null;
    if (model.isResidential) {
      return 'Houses up to ${model.households} household(s)';
    }
    if (model.isCommerce) {
      return 'Offers ${model.jobs} job(s)';
    }
    if (model.isService) {
      return 'Covers ${model.serviceCapacity} households of '
          '${model.serviceCategory} service';
    }
    return null;
  }""",
)

rep(
    'report values',
    """    final contentment = value('contentment');
    final advanced = value('stagesAdvanced');
    final completions =
        (payload['completions'] as List?)?.cast<String>() ?? const [];
    final arrivals =
        (payload['arrivals'] as List?)?.cast<String>() ?? const [];""",
    """    final contentment = value('contentment');
    final advanced = value('stagesAdvanced');
    final householdsArrived = value('householdsArrived');
    final positionsStaffed = value('positionsStaffed');
    final completions =
        (payload['completions'] as List?)?.cast<String>() ?? const [];""",
)

rep(
    'report body',
    """            const SizedBox(height: 8),
            for (final arrival in arrivals)
              Text(
                arrival,
                style: const TextStyle(color: Color(0xFF1E6552)),
              ),
            if (advanced > 0) Text('$advanced construction stage(s) advanced'),""",
    """            const SizedBox(height: 8),
            if (householdsArrived > 0)
              Text(
                '$householdsArrived household'
                '${householdsArrived == 1 ? '' : 's'} moved in',
                style: const TextStyle(color: Color(0xFF1E6552)),
              ),
            if (positionsStaffed > 0)
              Text(
                '$positionsStaffed position'
                '${positionsStaffed == 1 ? '' : 's'} staffed',
                style: const TextStyle(color: Color(0xFF1E6552)),
              ),
            if (advanced > 0) Text('$advanced construction stage(s) advanced'),""",
)

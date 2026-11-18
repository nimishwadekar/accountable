import 'package:flutter/material.dart';

import '../edit_fields.dart';

/// Economy editor: costs, wallet, and the demand and contentment
/// dials.
class EconomyPage extends StatefulWidget {
  const EconomyPage({
    required this.categories,
    required this.onChanged,
    super.key,
  });

  final Map<String, Object?> categories;
  final CategoriesChanged onChanged;

  @override
  State<EconomyPage> createState() => _EconomyPageState();
}

class _EconomyPageState extends State<EconomyPage> {
  @override
  Widget build(BuildContext context) {
    final economy = economyMap(widget.categories);
    final bridge = subMap(economy, 'bridgeCost');

    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        Text(
          'Treasury and purchases',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            SizedBox(
              width: 170,
              child: IntField(
                label: 'Starting treasury',
                value: asInt(economy['startingTreasuryCoins']),
                min: 0,
                help:
                    'Coins a brand-new world treasury begins with. '
                    'Existing saves carry their balance over.',
                onChanged: (v) => _edit((e) => e['startingTreasuryCoins'] = v),
              ),
            ),
            SizedBox(
              width: 150,
              child: IntField(
                label: 'Road tile (upfront)',
                value: asInt(economy['roadTileCostCoins']),
                min: 0,
                help:
                    'Upfront coins per tile of a road stretch plan. The '
                    'whole stretch is paid at planning, then lands whole '
                    'on the next check-in.',
                onChanged: (v) => _edit((e) => e['roadTileCostCoins'] = v),
              ),
            ),
            SizedBox(
              width: 150,
              child: IntField(
                label: 'Bridge tile (upfront)',
                value: asInt(bridge['bridgeTileCostCoins']),
                min: 0,
                help:
                    'Upfront coins per span tile of a bridge; banks cost '
                    'the road tile price. The crossing is paid at '
                    'planning, then the deck creeps one tile per '
                    'check-in.',
                onChanged: (v) => _edit(
                  (e) => (e['bridgeCost'] as Map)['bridgeTileCostCoins'] = v,
                ),
              ),
            ),
            SizedBox(
              width: 150,
              child: IntField(
                label: 'Parcel base price',
                value: asInt(economy['parcelBaseCoins']),
                min: 0,
                help:
                    'Flat coins for a neighboring parcel at '
                    'population zero.',
                onChanged: (v) => _edit((e) => e['parcelBaseCoins'] = v),
              ),
            ),
            SizedBox(
              width: 170,
              child: IntField(
                label: 'Parcel per population',
                value: asInt(economy['parcelPerPopulationCoins']),
                min: 0,
                help:
                    'Coins added to the parcel price for every point '
                    'of population — expanding a settlement gets '
                    'pricier as it grows.',
                onChanged: (v) =>
                    _edit((e) => e['parcelPerPopulationCoins'] = v),
              ),
            ),
            SizedBox(
              width: 170,
              child: IntField(
                label: 'Migration % / check-in',
                value: asInt(economy['migrationPercentPerCheckIn'], 2),
                min: 0,
                help:
                    'Citizens that may move in per check-in, as a '
                    'percentage of population (floored at one). Also '
                    "the waiting list's refill rate — growth costs "
                    'check-ins, not money.',
                onChanged: (v) =>
                    _edit((e) => e['migrationPercentPerCheckIn'] = v),
              ),
            ),
            SizedBox(
              width: 180,
              child: IntField(
                label: 'Employment % / check-in',
                value: asInt(economy['employmentPercentPerCheckIn'], 5),
                min: 0,
                help:
                    'Job positions that may staff per check-in, as a '
                    'percentage of population (floored at one). '
                    'Employment adjusts faster than migration.',
                onChanged: (v) =>
                    _edit((e) => e['employmentPercentPerCheckIn'] = v),
              ),
            ),
            SizedBox(
              width: 170,
              child: IntField(
                label: 'Waiting list cap %',
                value: asInt(economy['waitingPopulationCapPercent'], 10),
                min: 0,
                help:
                    "The residential waiting list's cap, as a "
                    'percentage of population (floored at one) — the '
                    "residential demand bar's scale.",
                onChanged: (v) =>
                    _edit((e) => e['waitingPopulationCapPercent'] = v),
              ),
            ),
            SizedBox(
              width: 180,
              child: IntField(
                label: 'Unemployment tolerance %',
                value: asInt(economy['unemploymentTolerancePercent'], 10),
                min: 0,
                help:
                    'Unemployment up to this percentage of population '
                    '(floored at one citizen) does not stop the '
                    'waiting list from refilling — frontier towns '
                    'tolerate some joblessness. Above it, migration '
                    'pauses until staffing catches up.',
                onChanged: (v) =>
                    _edit((e) => e['unemploymentTolerancePercent'] = v),
              ),
            ),
            SizedBox(
              width: 170,
              child: IntField(
                label: 'Job pull % / job',
                value: asInt(economy['jobPullPercentPerCheckIn'], 10),
                min: 0,
                help:
                    'Job-pull: each surplus job beyond the employed '
                    'population adds this percentage of an arrival to '
                    'the migration budget — commerce built ahead '
                    'visibly accelerates migration. Zero disables it.',
                onChanged: (v) =>
                    _edit((e) => e['jobPullPercentPerCheckIn'] = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Per-tile infrastructure ledger',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            SizedBox(
              width: 150,
              child: IntField(
                label: 'Road tax / tile',
                value: asInt(economy['roadTaxCoinsPerTile']),
                min: 0,
                help:
                    'Tax each road tile pays into the treasury per '
                    'check-in. Keep at zero — paving must never mint '
                    'coins.',
                onChanged: (v) => _edit((e) => e['roadTaxCoinsPerTile'] = v),
              ),
            ),
            SizedBox(
              width: 150,
              child: IntField(
                label: 'Road upkeep / tile',
                value: asInt(economy['roadUpkeepCoinsPerTile']),
                min: 0,
                help:
                    'Upkeep each road tile charges the treasury per '
                    'check-in, counted per tile as it appears.',
                onChanged: (v) => _edit((e) => e['roadUpkeepCoinsPerTile'] = v),
              ),
            ),
            SizedBox(
              width: 150,
              child: IntField(
                label: 'Bridge tax / tile',
                value: asInt(economy['bridgeTaxCoinsPerTile']),
                min: 0,
                help:
                    'Tax each bridge tile pays per check-in. Keep at '
                    'zero — paving must never mint coins.',
                onChanged: (v) => _edit((e) => e['bridgeTaxCoinsPerTile'] = v),
              ),
            ),
            SizedBox(
              width: 150,
              child: IntField(
                label: 'Bridge upkeep / tile',
                value: asInt(economy['bridgeUpkeepCoinsPerTile']),
                min: 0,
                help:
                    'Upkeep each bridge tile charges per check-in, '
                    'counted per tile as it appears.',
                onChanged: (v) =>
                    _edit((e) => e['bridgeUpkeepCoinsPerTile'] = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Derived: a 4-tile road plan = ${4 * asInt(economy['roadTileCostCoins'])} coins upfront · '
          'a 4-span bridge = ${asInt(bridge['bridgeTileCostCoins']) * 4 + 2 * asInt(economy['roadTileCostCoins'])} coins upfront · '
          'a parcel at population 25 = ${asInt(economy['parcelBaseCoins']) + 25 * asInt(economy['parcelPerPopulationCoins'])} coins',
          style: const TextStyle(fontSize: 11, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        Text('Contentment', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            SizedBox(
              width: 160,
              child: IntField(
                label: 'Contentment floor %',
                value: asInt(economy['contentmentFloorPercent']),
                min: 0,
                help:
                    'Contentment never drops below this percentage — '
                    'the no-dead-ends guarantee: unhappy citizens still '
                    'pay something, so a neglected town always keeps a '
                    'trickle of income.',
                onChanged: (v) =>
                    _edit((e) => e['contentmentFloorPercent'] = v),
              ),
            ),
            SizedBox(
              width: 180,
              child: IntField(
                label: 'Home tax unemployment floor %',
                value: asInt(economy['homeTaxUnemploymentFloorPercent']),
                min: 0,
                max: 100,
                help:
                    'Homes pay at least this percentage of their levy '
                    'regardless of employment; full employment tops the '
                    'rate back up to 100. The floor keeps a homes-only '
                    'town on the economy’s life support instead of '
                    'soft-locking it out of taxes entirely.',
                onChanged: (v) =>
                    _edit((e) => e['homeTaxUnemploymentFloorPercent'] = v),
              ),
            ),
            SizedBox(
              width: 180,
              child: IntField(
                label: 'Services demanded at pop.',
                value: asInt(economy['serviceRequirementPopulation']),
                min: 0,
                help:
                    'Population below which no service coverage is '
                    'demanded — the early game stays pure.',
                onChanged: (v) =>
                    _edit((e) => e['serviceRequirementPopulation'] = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          children: [
            for (
              var index = 0;
              index < (economy['requiredServiceCategories'] as List).length;
              index++
            )
              InputChip(
                label: Text(
                  '${(economy['requiredServiceCategories'] as List)[index]}',
                ),
                onDeleted: () => _edit((e) {
                  final list = [...(e['requiredServiceCategories'] as List)];
                  list.removeAt(index);
                  e['requiredServiceCategories'] = list;
                }),
              ),
            ActionChip(
              label: const Text('Add category'),
              onPressed: () => _edit((e) {
                final list = [
                  ...(e['requiredServiceCategories'] as List? ?? const []),
                ];
                list.add('service${list.length + 1}');
                e['requiredServiceCategories'] = list;
              }),
            ),
          ],
        ),
        Text(
          'Required service categories feed contentment: average '
          'coverage across them multiplies collected taxes. Capacities '
          'come from the models carrying each category.',
          style: const TextStyle(fontSize: 11, color: Colors.black54),
        ),
      ],
    );
  }

  void _edit(void Function(Map<String, Object?> economy) edit) {
    widget.onChanged((categories) {
      final economy = (categories['economy.json'] as Map)
          .cast<String, Object?>();
      edit(economy);
      categories['economy.json'] = economy;
    });
  }
}

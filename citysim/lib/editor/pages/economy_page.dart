import 'package:flutter/material.dart';

import '../edit_fields.dart';

/// Economy editor: costs, wallet, and the builder-progression table.
/// Starting capacity is fixed at 1 by product rule and shown read-only.
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
    final progression =
        (economy['builderProgression'] as List?)?.cast<Map>() ?? const [];

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
                    'whole stretch is paid at planning, then creeps one '
                    'tile per check-in.',
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
        Text('Builders', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Starting capacity is fixed at 1 (product rule). Builder slots '
          'gate in-flight building projects — roads and bridges creep '
          'without one. Capacity grows when population crosses each '
          'threshold; grants reconcile upward on load, never downward. An '
          'empty table keeps one builder forever.',
          style: const TextStyle(fontSize: 11, color: Colors.black54),
        ),
        const SizedBox(height: 6),
        ..._progressionRows(progression),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _edit((economy) {
                final list =
                    ((economy['builderProgression'] as List?)?.cast<Map>() ??
                            const [])
                        .map((step) => step.cast<String, Object?>())
                        .toList();
                final lastPopulation = list.isEmpty
                    ? 0
                    : asInt(list.last['atPopulation']);
                final lastCapacity = list.isEmpty
                    ? asInt(economy['startingBuilderCapacity'], 1)
                    : asInt(list.last['capacity']);
                list.add({
                  'atPopulation': lastPopulation + 5,
                  'capacity': lastCapacity + 1,
                });
                economy['builderProgression'] = list;
              }),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add step'),
            ),
            if (progression.isNotEmpty)
              TextButton.icon(
                onPressed: () => _edit(
                  (economy) => economy['builderProgression'] = const [],
                ),
                icon: const Icon(Icons.clear_all_rounded, size: 18),
                label: const Text('Clear all'),
              ),
          ],
        ),
      ],
    );
  }

  List<Widget> _progressionRows(List<Map> progression) {
    return [
      for (var index = 0; index < progression.length; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              SizedBox(
                width: 160,
                child: IntField(
                  label: 'At population',
                  value: asInt(progression[index]['atPopulation']),
                  min: 1,
                  help:
                      'Population threshold that grants the capacity on '
                      'this row. Thresholds must strictly increase.',
                  onChanged: (v) => _editStep(index, 'atPopulation', v),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 160,
                child: IntField(
                  label: 'Builder capacity',
                  value: asInt(progression[index]['capacity']),
                  min: 2,
                  help:
                      'Builder slots granted once the population threshold '
                      'on this row is crossed. Capacities must strictly '
                      'increase.',
                  onChanged: (v) => _editStep(index, 'capacity', v),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                onPressed: () => _edit((economy) {
                  final list = (economy['builderProgression'] as List)
                      .cast<Map>()
                      .map((step) => step.cast<String, Object?>())
                      .toList();
                  list.removeAt(index);
                  economy['builderProgression'] = list;
                }),
              ),
            ],
          ),
        ),
    ];
  }

  void _editStep(int index, String key, int value) {
    _edit((economy) {
      ((economy['builderProgression'] as List)[index] as Map)[key] = value;
    });
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

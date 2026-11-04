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
    final parcel = subMap(economy, 'parcelCost');
    final progression =
        (economy['builderProgression'] as List?)?.cast<Map>() ?? const [];

    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        Text('Costs', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            SizedBox(
              width: 170,
              child: IntField(
                label: 'Starting wallet',
                value: asInt(economy['startingWalletCoins']),
                min: 0,
                help: 'Coins a brand-new world begins with.',
                onChanged: (v) => _edit((e) => e['startingWalletCoins'] = v),
              ),
            ),
            SizedBox(
              width: 150,
              child: IntField(
                label: 'Road tile cost',
                value: asInt(economy['roadTileCostCoins']),
                min: 0,
                help:
                    'Coins to fund one road tile. Tiles are funded one at '
                    'a time, working outward from the connected road.',
                onChanged: (v) => _edit((e) => e['roadTileCostCoins'] = v),
              ),
            ),
            SizedBox(
              width: 150,
              child: IntField(
                label: 'Bridge base cost',
                value: asInt(bridge['baseCoins']),
                min: 0,
                help:
                    'Fixed coins for any bridge, before the per-water-tile '
                    'cost.',
                onChanged: (v) =>
                    _edit((e) => (e['bridgeCost'] as Map)['baseCoins'] = v),
              ),
            ),
            SizedBox(
              width: 170,
              child: IntField(
                label: 'Bridge per water tile',
                value: asInt(bridge['perWaterTileCoins']),
                min: 0,
                help:
                    'Extra coins per water cell the bridge spans. Total '
                    'cost = base + this × span length.',
                onChanged: (v) => _edit(
                  (e) => (e['bridgeCost'] as Map)['perWaterTileCoins'] = v,
                ),
              ),
            ),
            SizedBox(
              width: 150,
              child: IntField(
                label: 'Parcel base cost',
                value: asInt(parcel['baseCoins']),
                min: 0,
                help:
                    'Coins for the closest neighboring parcel, before '
                    'distance and portfolio surcharges.',
                onChanged: (v) =>
                    _edit((e) => (e['parcelCost'] as Map)['baseCoins'] = v),
              ),
            ),
            SizedBox(
              width: 190,
              child: IntField(
                label: 'Parcel step per N cells dist.',
                value: asInt(parcel['distanceStepCells'], 8),
                min: 1,
                help:
                    'Adds one coin for every N cells of grid distance '
                    'from the origin parcel.',
                onChanged: (v) => _edit(
                  (e) => (e['parcelCost'] as Map)['distanceStepCells'] = v,
                ),
              ),
            ),
            SizedBox(
              width: 200,
              child: IntField(
                label: 'Parcel step per N owned parcels',
                value: asInt(parcel['ownedStepParcels'], 12),
                min: 1,
                help: 'Adds one coin for every N parcels already owned.',
                onChanged: (v) => _edit(
                  (e) => (e['parcelCost'] as Map)['ownedStepParcels'] = v,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Derived: bridge span 1 = ${asInt(bridge['baseCoins']) + asInt(bridge['perWaterTileCoins'])} coins · '
          'span 4 = ${asInt(bridge['baseCoins']) + 4 * asInt(bridge['perWaterTileCoins'])} coins · '
          'first-ring parcel = ${asInt(parcel['baseCoins'])} coins',
          style: const TextStyle(fontSize: 11, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        Text('Builders', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Starting capacity is fixed at 1 (product rule). Capacity grows '
          'when population crosses each threshold; grants reconcile upward '
          'on load, never downward. An empty table keeps one builder forever.',
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

import 'package:flutter/material.dart';

import '../edit_fields.dart';

/// Landing page: category counts, budget summary, and the population
/// progression curve (models ordered by unlock threshold).
class OverviewPage extends StatelessWidget {
  const OverviewPage({required this.categories, super.key});

  final Map<String, Object?> categories;

  @override
  Widget build(BuildContext context) {
    final models = modelList(categories);
    final sprites = spriteMap(categories);
    final economy = economyMap(categories);
    final progression =
        (economy['builderProgression'] as List?)?.cast<Map>() ?? const [];
    final buildings = models
        .where((model) => model['kind'] == 'building')
        .toList();
    final avgBuildingCost = buildings.isEmpty
        ? 0.0
        : buildings
                  .map((model) => asInt(model['costCoins']))
                  .reduce((a, b) => a + b) /
              buildings.length;
    final checkinsPerBuilding = avgBuildingCost / 5;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Content at a glance',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _stat('Models', '${models.length}'),
            _stat(
              'Enabled models',
              '${models.where((m) => m['enabled'] != false).length}',
            ),
            _stat('Sprites', '${sprites.length}'),
            _stat(
              'Builder progression',
              progression.isEmpty
                  ? 'none (1 builder)'
                  : '${progression.length} step(s)',
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Budget heuristics',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Average building cost $avgBuildingCost coins · '
          '≈${checkinsPerBuilding.toStringAsFixed(1)} check-ins per building at the '
          'mechanics plan\'s 1-per-5-days target.',
        ),
        const SizedBox(height: 20),
        Text(
          'Population progression',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        const Text(
          'Models in unlock order with their population contribution — the '
          'settlement\'s growth curve as players will experience it.',
        ),
        const SizedBox(height: 8),
        ..._progressionRows(models, progression.cast<Map>()),
      ],
    );
  }

  List<Widget> _progressionRows(
    List<Map<String, Object?>> models,
    Iterable<Map> progression,
  ) {
    final ordered = [...models]
      ..sort(
        (a, b) =>
            asInt(a['unlockAtPopulation'])
                .compareTo(asInt(b['unlockAtPopulation'])),
      );
    final rows = <Widget>[];
    var lastThreshold = -1;
    for (final model in ordered) {
      final threshold = asInt(model['unlockAtPopulation']);
      if (threshold != lastThreshold) {
        final grants = progression
            .where((step) => asInt(step['atPopulation']) == threshold)
            .toList();
        rows.add(
          _thresholdHeader(
            threshold,
            grants.isEmpty
                ? null
                : 'builder capacity → ${asInt(grants.first['capacity'])}',
          ),
        );
        lastThreshold = threshold;
      }
      rows.add(_modelRow(model));
    }
    return rows;
  }

  Widget _thresholdHeader(int threshold, String? grant) => Container(
    margin: const EdgeInsets.only(top: 10, bottom: 4),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: threshold == 0 ? Colors.green.shade100 : Colors.teal.shade50,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Icon(
          threshold == 0 ? Icons.flag_rounded : Icons.groups_rounded,
          size: 16,
          color: Colors.green.shade800,
        ),
        const SizedBox(width: 6),
        Text(
          threshold == 0 ? 'Available from the start' : 'Population $threshold',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        if (grant != null) ...[
          const SizedBox(width: 8),
          Text(grant, style: TextStyle(color: Colors.teal.shade800)),
        ],
      ],
    ),
  );

  Widget _modelRow(Map<String, Object?> model) {
    final roles = (model['assetRoles'] as List?)?.cast<String>() ?? const [];
    final role = roles.isNotEmpty ? roles.first : '';
    final sprite = (spriteMap(categories)[role] as Map?)
        ?.cast<String, Object?>();
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 4),
      child: Row(
        children: [
          SpriteFacingsThumb(sprite: sprite, size: 36),
          const SizedBox(width: 8),
          Expanded(child: Text('${model['name']}')),
          Text(
            '+${asInt(model['population'])} pop · ${asInt(model['costCoins'])} coins',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          if (model['enabled'] == false)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Chip(
                label: Text('disabled'),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.green.shade100),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.black54),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

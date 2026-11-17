import 'package:flutter/material.dart';

import '../edit_fields.dart';

/// Progression editor: the milestone layer above the catalogue.
///
/// Milestones decide when models unlock for *placement* — population
/// thresholds with named groups of catalogue items. Rows are drop
/// targets, item chips are draggables: dragging a model between rows
/// re-tiers it, and dragging it to the tray below leaves it in no
/// milestone — not part of the progression, placeable never, and (for
/// nature-capable decorations) existing purely as authored terrain
/// vegetation. The first milestone (population 0) is "from start".
///
/// Milestones have stable ids the game saves as the progression
/// high-water, so renames are save-safe and reordering never shifts
/// what a save has reached. Only empty milestones delete — move the
/// items first.
class ProgressionPage extends StatefulWidget {
  const ProgressionPage({
    required this.categories,
    required this.onChanged,
    super.key,
  });

  final Map<String, Object?> categories;
  final CategoriesChanged onChanged;

  @override
  State<ProgressionPage> createState() => _ProgressionPageState();
}

class _ProgressionPageState extends State<ProgressionPage> {
  List<Map<String, Object?>> _milestones() =>
      ((widget.categories['progression.json'] as Map?)?['milestones'] as List?)
          ?.cast<Map>()
          .map((milestone) => milestone.cast<String, Object?>())
          .toList() ??
      [];

  void _edit(void Function(Map<String, Object?> progression) edit) {
    widget.onChanged((categories) {
      final progression =
          (categories['progression.json'] ??= <String, Object?>{}) as Map;
      edit(progression.cast<String, Object?>());
    });
  }

  /// Removes [modelId] from every milestone, then adds it to
  /// [milestoneIndex]'s (or to none, when null — the nature-only
  /// tray). One edit, one undo state, whatever the drag crossed.
  void _moveModel(String modelId, int? milestoneIndex) {
    _edit((progression) {
      final milestones = (progression['milestones'] as List?) ?? const [];
      for (final milestone in milestones.cast<Map>()) {
        final models = (milestone['models'] as List?) ?? const [];
        milestone['models'] = [
          for (final model in models)
            if (model != modelId) model,
        ];
      }
      if (milestoneIndex != null && milestoneIndex < milestones.length) {
        final models = milestones[milestoneIndex] as Map;
        models['models'] = [...?models['models'] as List?, modelId];
      }
    });
  }

  String _newMilestoneId(List<Map<String, Object?>> milestones) {
    var counter = milestones.length + 1;
    final taken = {for (final milestone in milestones) '${milestone['id']}'};
    while (taken.contains('milestone-$counter')) {
      counter++;
    }
    return 'milestone-$counter';
  }

  @override
  Widget build(BuildContext context) {
    final milestones = _milestones();
    final models = modelList(widget.categories);
    final modelNames = {
      for (final model in models) '${model['id']}': '${model['name']}',
    };
    final assigned = <String>{};
    for (final milestone in milestones) {
      for (final model in (milestone['models'] as List?) ?? const []) {
        assigned.add('$model');
      }
    }
    final unassigned = [
      for (final model in models)
        if (!assigned.contains('${model['id']}')) '${model['id']}',
    ];

    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        Text(
          'Population milestones',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          'Each milestone unlocks its models for placement when the '
          'settlement\'s population reaches it — the first (population 0) '
          'is "from start". Drag items between rows to re-tier them; the '
          'high-water a save has reached never regresses, and renames are '
          'save-safe (saves store the stable id, not the name).',
          style: const TextStyle(fontSize: 11, color: Colors.black54),
        ),
        const SizedBox(height: 10),
        for (var index = 0; index < milestones.length; index++)
          _milestoneRow(milestones, index, modelNames),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => _edit((progression) {
              var milestones = progression['milestones'] as List?;
              milestones ??= progression['milestones'] = <Object?>[];
              final last = milestones.isEmpty
                  ? null
                  : asInt(milestones.last['population']);
              milestones.add({
                'id': _newMilestoneId(milestones.cast<Map<String, Object?>>()),
                'name': 'New milestone',
                'population': (last ?? -5) + 5,
                'models': <String>[],
              });
            }),
            icon: const Icon(Icons.add_rounded, size: 17),
            label: const Text('Add milestone'),
          ),
        ),
        const SizedBox(height: 18),
        _natureTray(unassigned, modelNames),
      ],
    );
  }

  Widget _milestoneRow(
    List<Map<String, Object?>> milestones,
    int index,
    Map<String, String> modelNames,
  ) {
    final milestone = milestones[index];
    final models = [
      for (final model in (milestone['models'] as List?) ?? const []) '$model',
    ];
    final empty = models.isEmpty;
    final threshold = asInt(milestone['population']);
    final previous = index == 0
        ? null
        : asInt(milestones[index - 1]['population']);
    final orderingBroken = previous != null && threshold <= previous;
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => !models.contains(details.data),
      onAcceptWithDetails: (details) => _moveModel(details.data, index),
      builder: (context, candidate, rejected) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        elevation: candidate.isNotEmpty ? 4 : 1,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 210,
                    child: TextFieldBox(
                      label: 'Milestone name',
                      value: '${milestone['name'] ?? ''}',
                      help:
                          'Display label — the game names unlocks after it '
                          '(e.g. "Unlocks at Village"). Renaming never '
                          'affects saves.',
                      onChanged: (v) => _edit((progression) {
                        (progression['milestones'] as List)[index]['name'] = v;
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 150,
                    child: IntField(
                      label: 'Population',
                      value: threshold,
                      min: 0,
                      help:
                          'Population the settlement must reach before this '
                          'milestone\'s models unlock. Thresholds must sort '
                          'strictly upward; 0 is "from start".',
                      onChanged: (v) => _edit((progression) {
                        (progression['milestones']
                                as List)[index]['population'] =
                            v;
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (orderingBroken)
                    const Tooltip(
                      message: 'Thresholds must sort strictly upward',
                      child: Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.deepOrange,
                        size: 18,
                      ),
                    ),
                  const Spacer(),
                  IconButton(
                    tooltip: empty
                        ? 'Delete milestone'
                        : 'Move its items first — only empty milestones '
                              'delete',
                    onPressed: empty
                        ? () => _edit((progression) {
                            (progression['milestones'] as List).removeAt(index);
                          })
                        : null,
                    icon: const Icon(Icons.delete_outline_rounded, size: 19),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (models.isEmpty)
                const Text(
                  'Drop items here — or leave it empty until you tune.',
                  style: TextStyle(fontSize: 11, color: Colors.black38),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final model in models)
                      _modelChip(model, modelNames[model] ?? model),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _natureTray(List<String> unassigned, Map<String, String> modelNames) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => _moveModel(details.data, null),
      builder: (context, candidate, rejected) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        elevation: candidate.isNotEmpty ? 4 : 0,
        color: const Color(0xFFEFF4EC),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.park_outlined, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Not part of progression (${unassigned.length})',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Models in no milestone — not part of the progression, so '
                'they can never be placed through the game. Nature-capable '
                'decorations here can still be sprinkled as terrain '
                'vegetation by the brush; anything else is dead content. '
                'Drag one up into a milestone to make it placeable.',
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
              const SizedBox(height: 6),
              if (unassigned.isEmpty)
                const Text(
                  'Every model belongs to a milestone.',
                  style: TextStyle(fontSize: 11, color: Colors.black38),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final model in unassigned)
                      _modelChip(model, modelNames[model] ?? model),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modelChip(String id, String label) {
    return Draggable<String>(
      data: id,
      feedback: Material(
        color: Colors.transparent,
        child: Chip(
          label: Text(label),
          visualDensity: VisualDensity.compact,
          backgroundColor: Colors.white,
        ),
      ),
      childWhenDragging: Chip(
        label: Text(label),
        visualDensity: VisualDensity.compact,
        backgroundColor: Colors.black12,
      ),
      child: Tooltip(
        message: id,
        child: Chip(label: Text(label), visualDensity: VisualDensity.compact),
      ),
    );
  }
}

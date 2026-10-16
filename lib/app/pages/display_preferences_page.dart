import 'package:flutter/material.dart';

import '../../data/data.dart';
import '../theme/design_tokens.dart';

class DisplayPreferencesPage extends StatefulWidget {
  const DisplayPreferencesPage({
    super.key,
    required this.title,
    required this.entityType,
    required this.data,
    required this.preferences,
    required this.onSave,
  });

  final String title;
  final String entityType;
  final AppDataSnapshot data;
  final List<DisplayPreference> preferences;
  final Future<void> Function(List<DisplayPreference>) onSave;

  @override
  State<DisplayPreferencesPage> createState() => _DisplayPreferencesPageState();
}

class _DisplayPreferencesPageState extends State<DisplayPreferencesPage> {
  late List<DisplayPreference> _preferences = [...widget.preferences];
  bool _saving = false;

  String _nameOf(String id) => switch (widget.entityType) {
    'account' => widget.data.accountsById[id]?.name ?? id,
    'category' => widget.data.categoriesById[id]?.name ?? id,
    _ => widget.data.tagsById[id]?.name ?? id,
  };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Text(
                'Hidden items remain listed here so they can be restored later.',
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                itemCount: _preferences.length,
                buildDefaultDragHandles: false,
                onReorderItem: _reorder,
                itemBuilder: (context, index) {
                  final preference = _preferences[index];
                  return ListTile(
                    key: ValueKey(
                      '${preference.entityType}:${preference.entityId}',
                    ),
                    leading: ReorderableDragStartListener(
                      index: index,
                      child: const Icon(Icons.drag_handle),
                    ),
                    title: Text(_nameOf(preference.entityId)),
                    subtitle: Text(preference.showInApp ? 'Visible' : 'Hidden'),
                    trailing: Wrap(
                      spacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('App'),
                        Switch(
                          value: preference.showInApp,
                          onChanged: (value) => _update(
                            index,
                            preference.copyWith(
                              showInApp: value,
                              showInEntryForms: value
                                  ? preference.showInEntryForms
                                  : false,
                            ),
                          ),
                        ),
                        const Text('Forms'),
                        Switch(
                          value: preference.showInEntryForms,
                          onChanged: preference.showInApp
                              ? (value) => _update(
                                  index,
                                  preference.copyWith(showInEntryForms: value),
                                )
                              : null,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save'),
                ),
              ),
            ),
            if (_saving) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }

  void _update(int index, DisplayPreference preference) {
    setState(() => _preferences[index] = preference);
  }

  void _reorder(int oldIndex, int newIndex) {
    final reordered = [..._preferences];
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    final base = displayPreferenceBases[widget.entityType]!;
    setState(() {
      _preferences = [
        for (var index = 0; index < reordered.length; index++)
          reordered[index].copyWith(displayOrder: base + index),
      ];
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSave(_preferences);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save display preferences: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

import 'package:flutter/material.dart';

import '../../data/data.dart';
import '../error_dialog.dart';
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
                  final name = _nameOf(preference.entityId);
                  return LayoutBuilder(
                    key: ValueKey(
                      '${preference.entityType}:${preference.entityId}',
                    ),
                    builder: (context, constraints) {
                      final compact =
                          constraints.maxWidth < AppBreakpoints.compact ||
                          MediaQuery.textScalerOf(context).scale(14) > 16.8;
                      final compactSpacing = usesCompactVerticalSpacing(
                        context,
                        availableWidth: constraints.maxWidth,
                      );
                      final dragHandle = ReorderableDragStartListener(
                        index: index,
                        child: Tooltip(
                          message: 'Reorder $name',
                          child: const SizedBox(
                            width: 48,
                            height: 48,
                            child: Icon(Icons.drag_handle),
                          ),
                        ),
                      );
                      final identity = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            preference.showInApp ? 'Visible' : 'Hidden',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      );
                      final inAppToggle = _PreferenceToggle(
                        entityName: name,
                        label: 'Show in app',
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
                      );
                      final formsToggle = _PreferenceToggle(
                        entityName: name,
                        label: 'Use in entry forms',
                        value: preference.showInEntryForms,
                        onChanged: preference.showInApp
                            ? (value) => _update(
                                index,
                                preference.copyWith(showInEntryForms: value),
                              )
                            : null,
                      );

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: compactSpacing
                                  ? AppSpacing.xs
                                  : AppSpacing.sm,
                            ),
                            child: compact
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          dragHandle,
                                          const SizedBox(width: AppSpacing.sm),
                                          Expanded(child: identity),
                                        ],
                                      ),
                                      inAppToggle,
                                      formsToggle,
                                    ],
                                  )
                                : Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      dragHandle,
                                      const SizedBox(width: AppSpacing.sm),
                                      Expanded(child: identity),
                                      const SizedBox(width: AppSpacing.sm),
                                      SizedBox(
                                        width: 320,
                                        child: Row(
                                          children: [
                                            Expanded(child: inAppToggle),
                                            Expanded(child: formsToggle),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                          const Divider(height: 1),
                        ],
                      );
                    },
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
      showPersistentErrorDialog(
        context,
        'Could not save display preferences: $error',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _PreferenceToggle extends StatelessWidget {
  const _PreferenceToggle({
    required this.entityName,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String entityName;
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final semanticLabel = switch (label) {
      'Show in app' => 'Show $entityName in app',
      'Use in entry forms' => 'Use $entityName in entry forms',
      _ => '$label: $entityName',
    };
    void toggle() => onChanged?.call(!value);

    return Semantics(
      container: true,
      label: semanticLabel,
      value: value ? 'On' : 'Off',
      toggled: value,
      enabled: onChanged != null,
      onTap: onChanged == null ? null : toggle,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onChanged == null ? null : toggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: Row(
                  children: [
                    Expanded(child: Text(label)),
                    Switch(value: value, onChanged: onChanged),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

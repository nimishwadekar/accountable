import 'package:flutter/material.dart';

import '../../data/data.dart';
import '../error_dialog.dart';
import 'display_preferences_page.dart';
import '../theme/design_tokens.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    this.data,
    this.onSaveDisplayPreferences,
    this.onRebuildDailyTables,
    required this.onReloadData,
    this.textScale = 1,
    this.onTextScaleChanged,
  });

  final AppDataSnapshot? data;
  final Future<void> Function(List<DisplayPreference> preferences)?
  onSaveDisplayPreferences;
  final Future<void> Function()? onRebuildDailyTables;
  final Future<void> Function() onReloadData;
  final double textScale;
  final ValueChanged<double>? onTextScaleChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _working = false;
  bool _refreshing = false;
  bool _savingPreferences = false;
  late Map<String, List<DisplayPreference>> _preferencesByType;

  double get _displayScale => widget.textScale.clamp(0.75, 1.0).toDouble();

  @override
  void initState() {
    super.initState();
    _preferencesByType = _buildPreferences(widget.data);
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _preferencesByType = _buildPreferences(widget.data);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onRebuildDailyTables != null;
    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Settings',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.xl),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Font size',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text('${(_displayScale * 100).round()}%'),
                      Slider(
                        min: 0.75,
                        max: 1,
                        divisions: 10,
                        value: _displayScale,
                        label: '${(_displayScale * 100).round()}%',
                        onChanged: widget.onTextScaleChanged,
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.data != null &&
                  widget.onSaveDisplayPreferences != null) ...[
                const SizedBox(height: AppSpacing.md),
                _buildDisplayPreferencesMenu(),
              ],
              const SizedBox(height: AppSpacing.md),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Derived daily tables',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      const Text(
                        'Rebuild exchange rates, daily account balances, and daily net worth from the source data.',
                      ),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton.icon(
                        onPressed: enabled && !_working
                            ? _confirmRebuild
                            : null,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Rebuild daily tables'),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      FilledButton.tonalIcon(
                        onPressed: _refreshing ? null : _refreshData,
                        icon: const Icon(Icons.sync),
                        label: const Text('Refresh data'),
                      ),
                      if (!enabled) ...[
                        const SizedBox(height: AppSpacing.sm),
                        const Text(
                          'Available when connected to Google Sheets.',
                          style: TextStyle(color: AppColors.mutedText),
                        ),
                      ],
                      if (_working) ...[
                        const SizedBox(height: AppSpacing.md),
                        const LinearProgressIndicator(),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, List<DisplayPreference>> _buildPreferences(
    AppDataSnapshot? data,
  ) {
    if (data == null) return {};
    final existing = data.displayPreferencesByKey;
    DisplayPreference preference(String type, String id, int order) =>
        existing['$type:$id'] ??
        DisplayPreference(
          entityType: type,
          entityId: id,
          displayOrder: order,
          showInApp: true,
          showInEntryForms: true,
        );
    return {
      'account': [
        for (var index = 0; index < data.orderedAccounts.length; index++)
          preference('account', data.orderedAccounts[index].id, 1001 + index),
      ],
      'category': [
        for (var index = 0; index < data.orderedCategories.length; index++)
          preference(
            'category',
            data.orderedCategories[index].id,
            2000 + index,
          ),
      ],
      'tag': [
        for (var index = 0; index < data.orderedTags.length; index++)
          preference('tag', data.orderedTags[index].id, 3000 + index),
      ],
    };
  }

  Widget _buildDisplayPreferencesMenu() {
    return Card(
      child: Column(
        children: [
          const ListTile(
            title: Text('Customize Display Order'),
            subtitle: Text('Choose what you want to customize.'),
          ),
          for (final entry in const [
            ('account', 'Accounts'),
            ('category', 'Categories'),
            ('tag', 'Tags'),
          ])
            ListTile(
              leading: const Icon(Icons.sort),
              title: Text(entry.$2),
              trailing: const Icon(Icons.chevron_right),
              onTap: _savingPreferences
                  ? null
                  : () => _openDisplayPreferences(entry.$1, entry.$2),
            ),
        ],
      ),
    );
  }

  Future<void> _openDisplayPreferences(String type, String title) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.92,
        child: DisplayPreferencesPage(
          title: title,
          entityType: type,
          data: widget.data!,
          preferences: _preferencesByType[type] ?? const [],
          onSave: (preferences) => _saveTypePreferences(type, preferences),
        ),
      ),
    );
  }

  Future<void> _saveTypePreferences(
    String type,
    List<DisplayPreference> preferences,
  ) async {
    final previous = _preferencesByType[type] ?? const [];
    setState(() {
      _savingPreferences = true;
      _preferencesByType[type] = preferences;
    });
    try {
      final allPreferences = [
        for (final key in const ['account', 'category', 'tag'])
          ...?_preferencesByType[key],
      ];
      await widget.onSaveDisplayPreferences!(allPreferences);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Display preferences saved.')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _preferencesByType[type] = previous);
      }
      rethrow;
    } finally {
      if (mounted) setState(() => _savingPreferences = false);
    }
  }

  Future<void> _refreshData() async {
    setState(() => _refreshing = true);
    try {
      await widget.onReloadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Data refreshed.')));
    } catch (error) {
      if (!mounted) return;
      showPersistentErrorDialog(context, 'Could not refresh data: $error');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _confirmRebuild() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rebuild daily tables?'),
        content: const Text(
          'This replaces all rows in the three derived daily tables. The source tables are not changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Rebuild'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    setState(() => _working = true);
    try {
      await widget.onRebuildDailyTables!();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Daily tables rebuilt.')));
    } catch (error) {
      if (!mounted) return;
      showPersistentErrorDialog(
        context,
        'Could not rebuild daily tables: $error',
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}

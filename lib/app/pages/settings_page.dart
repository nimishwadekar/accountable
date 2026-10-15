import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    this.onRebuildDailyTables,
    required this.onReloadData,
  });

  final Future<void> Function()? onRebuildDailyTables;
  final Future<void> Function() onReloadData;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _working = false;
  bool _refreshing = false;

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

  Future<void> _refreshData() async {
    setState(() => _refreshing = true);
    try {
      await widget.onReloadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Data refreshed.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not refresh data: $error')));
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not rebuild daily tables: $error')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}

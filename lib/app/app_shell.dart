import 'package:flutter/material.dart';

import '../data/data.dart';
import 'pages/app_pages.dart';
import 'pages/assets_liabilities_page.dart';
import 'pages/transactions_page.dart';
import 'pages/settings_page.dart';
import '../features/analysis/analysis_page.dart';
import 'theme/design_tokens.dart';

enum AppSection {
  overview,
  transactions,
  analysis,
  accounts,
  assetsLiabilities,
  settings,
}

extension AppSectionDetails on AppSection {
  String get label => switch (this) {
    AppSection.overview => 'Overview',
    AppSection.transactions => 'Transactions',
    AppSection.accounts => 'Accounts',
    AppSection.analysis => 'Analysis',
    AppSection.assetsLiabilities => 'Assets & Liabilities',
    AppSection.settings => 'Settings',
  };

  IconData get icon => switch (this) {
    AppSection.overview => Icons.dashboard_outlined,
    AppSection.transactions => Icons.receipt_long_outlined,
    AppSection.accounts => Icons.account_balance_wallet_outlined,
    AppSection.analysis => Icons.insights_outlined,
    AppSection.assetsLiabilities => Icons.account_balance_outlined,
    AppSection.settings => Icons.settings_outlined,
  };

  IconData get selectedIcon => switch (this) {
    AppSection.overview => Icons.dashboard,
    AppSection.transactions => Icons.receipt_long,
    AppSection.accounts => Icons.account_balance_wallet,
    AppSection.analysis => Icons.insights,
    AppSection.assetsLiabilities => Icons.account_balance,
    AppSection.settings => Icons.settings,
  };
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.dataRepository,
    this.onRebuildDailyTables,
    this.onReloadData,
  });

  final AppDataRepository dataRepository;
  final Future<void> Function()? onRebuildDailyTables;
  final Future<void> Function()? onReloadData;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late Future<AppDataSnapshot> _snapshotFuture;
  AppSection _selectedSection = AppSection.overview;

  @override
  void initState() {
    super.initState();
    _snapshotFuture = widget.dataRepository.load();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < AppBreakpoints.compact;
    final isExtended = width >= 1100;

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (!isCompact) _buildNavigationRail(extended: isExtended),
            Expanded(
              child: FutureBuilder<AppDataSnapshot>(
                future: _snapshotFuture,
                builder: (context, snapshot) {
                  return _buildContent(snapshot);
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: isCompact ? _buildNavigationBar() : null,
    );
  }

  Widget _buildNavigationRail({required bool extended}) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: NavigationRail(
        extended: extended,
        selectedIndex: _selectedSection.index,
        onDestinationSelected: _selectSection,
        leading: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.lg,
          ),
          child: extended
              ? Text(
                  'Accountable',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w800,
                  ),
                )
              : const Icon(Icons.account_balance_outlined),
        ),
        destinations: [
          for (final section in AppSection.values)
            NavigationRailDestination(
              icon: Icon(section.icon),
              selectedIcon: Icon(section.selectedIcon),
              label: Text(section.label),
            ),
        ],
      ),
    );
  }

  Widget _buildNavigationBar() {
    return NavigationBar(
      selectedIndex: _selectedSection.index,
      onDestinationSelected: _selectSection,
      destinations: [
        for (final section in AppSection.values)
          NavigationDestination(
            icon: Icon(section.icon),
            selectedIcon: Icon(section.selectedIcon),
            label: section.label,
          ),
      ],
    );
  }

  Widget _buildContent(AsyncSnapshot<AppDataSnapshot> snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const AppLoadingPage();
    }
    if (snapshot.hasError) {
      final error = snapshot.error!;
      if (error is DataValidationFailure) {
        return DataValidationPage(failure: error, onReload: _reload);
      }
      return AppErrorPage(error: error, onReload: _reload);
    }

    final data = snapshot.data;
    if (data == null) {
      return AppErrorPage(
        error: StateError('The data snapshot was empty.'),
        onReload: _reload,
      );
    }

    return switch (_selectedSection) {
      AppSection.overview => OverviewPage(data: data),
      AppSection.transactions => TransactionsPage(
        data: data,
        onTransactionAdded: _handleTransactionAdded,
      ),
      AppSection.accounts => AccountsPage(data: data),
      AppSection.analysis => AnalysisPage(data: data),
      AppSection.assetsLiabilities => AssetsLiabilitiesPage(
        data: data,
        onValuationAdded: _handleValuationAdded,
      ),
      AppSection.settings => SettingsPage(
        onRebuildDailyTables: widget.onRebuildDailyTables,
        onReloadData: widget.onReloadData ?? _reloadData,
      ),
    };
  }

  void _selectSection(int index) {
    setState(() {
      _selectedSection = AppSection.values[index];
    });
  }

  void _reload() {
    setState(() {
      _snapshotFuture = widget.dataRepository.reload();
    });
  }

  Future<void> _reloadData() async {
    final future = widget.dataRepository.reload();
    setState(() {
      _snapshotFuture = future;
    });
    await future;
  }

  Future<void> _handleValuationAdded(DailyManualValuation valuation) async {
    final future = widget.dataRepository.addManualValuation(valuation);
    setState(() {
      _snapshotFuture = future;
    });
    await future;
  }

  Future<void> _handleTransactionAdded(Transaction transaction) async {
    final future = widget.dataRepository.addTransaction(transaction);
    setState(() {
      _snapshotFuture = future;
    });
    await future;
  }
}

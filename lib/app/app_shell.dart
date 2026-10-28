import 'dart:async';

import 'package:flutter/material.dart';

import '../data/data.dart';
import 'pages/app_pages.dart';
import 'pages/assets_liabilities_page.dart';
import 'pages/transactions_page.dart';
import 'pages/settings_page.dart';
import 'navigation_history.dart';
import '../features/analysis/analysis_page.dart';
import '../features/migration_assistance/migration_assistance_page.dart';
import 'theme/design_tokens.dart';

enum AppSection {
  overview,
  transactions,
  analysis,
  accounts,
  assetsLiabilities,
  settings,
  migrationAssistance,
}

extension AppSectionDetails on AppSection {
  String get label => switch (this) {
    AppSection.overview => 'Overview',
    AppSection.transactions => 'Transactions',
    AppSection.accounts => 'Accounts',
    AppSection.analysis => 'Analysis',
    AppSection.assetsLiabilities => 'Assets & Liabilities',
    AppSection.settings => 'Settings',
    AppSection.migrationAssistance => 'Migration Assistance',
  };

  String get compactLabel => switch (this) {
    AppSection.overview => 'Overview',
    AppSection.transactions => 'Transactions',
    AppSection.accounts => 'Accounts',
    AppSection.analysis => 'Analysis',
    AppSection.assetsLiabilities => 'Assets',
    AppSection.settings => 'Settings',
    AppSection.migrationAssistance => 'Migration Assistance',
  };

  IconData get icon => switch (this) {
    AppSection.overview => Icons.dashboard_outlined,
    AppSection.transactions => Icons.receipt_long_outlined,
    AppSection.accounts => Icons.account_balance_wallet_outlined,
    AppSection.analysis => Icons.insights_outlined,
    AppSection.assetsLiabilities => Icons.account_balance_outlined,
    AppSection.settings => Icons.settings_outlined,
    AppSection.migrationAssistance => Icons.compare_arrows_outlined,
  };

  IconData get selectedIcon => switch (this) {
    AppSection.overview => Icons.dashboard,
    AppSection.transactions => Icons.receipt_long,
    AppSection.accounts => Icons.account_balance_wallet,
    AppSection.analysis => Icons.insights,
    AppSection.assetsLiabilities => Icons.account_balance,
    AppSection.settings => Icons.settings,
    AppSection.migrationAssistance => Icons.compare_arrows,
  };
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.dataRepository,
    this.restrictedStartup = false,
    this.onStartupSignIn,
    this.startupError,
    this.onRetryOutbox,
    this.onTransactionFormActiveChanged,
    this.migrationAssistance = false,
    this.onRebuildDailyTables,
    this.onReconcileDailyTables,
    this.onRefreshFormSnapshot,
    this.onRebuildNetWorth,
    this.onReloadData,
    this.textScale = 1,
    this.onTextScaleChanged,
  });

  final AppDataRepository dataRepository;
  final bool restrictedStartup;
  final Future<void> Function()? onStartupSignIn;
  final String? startupError;
  final Future<void> Function()? onRetryOutbox;
  final ValueChanged<bool>? onTransactionFormActiveChanged;
  final bool migrationAssistance;
  final Future<void> Function()? onRebuildDailyTables;
  final Future<void> Function()? onReconcileDailyTables;
  final Future<void> Function()? onRefreshFormSnapshot;
  final Future<void> Function(DateTime startDate)? onRebuildNetWorth;
  final Future<void> Function()? onReloadData;
  final double textScale;
  final ValueChanged<double>? onTextScaleChanged;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late Future<AppDataSnapshot> _snapshotFuture;
  late final NavigationHistory _navigationHistory;
  StreamSubscription<String>? _navigationSubscription;
  AppSection _selectedSection = AppSection.overview;
  final Set<AppSection> _visitedSections = {};
  final Map<AppSection, Widget> _pageCache = {};
  final TransactionWriteCoordinator _writeCoordinator =
      const TransactionWriteCoordinator();

  @override
  void initState() {
    super.initState();
    _navigationHistory = NavigationHistory();
    _selectedSection = widget.restrictedStartup
        ? AppSection.transactions
        : _sectionFromPath(_navigationHistory.currentPath);
    _visitedSections.add(_selectedSection);
    // Mark the authenticated app entry so Back cannot return to pre-auth UI.
    _navigationHistory.replace(
      _navigationHistory.authenticatedPath(_navigationHistory.currentPath),
    );
    _navigationSubscription = _navigationHistory.changes.listen((path) {
      if (!mounted) return;
      if (!_navigationHistory.isAuthenticatedPath(path)) {
        setState(() => _selectedSection = AppSection.overview);
        _navigationHistory.push(_pathForSection(AppSection.overview));
        return;
      }
      final section = _sectionFromPath(path);
      _visitedSections.add(section);
      setState(() => _selectedSection = section);
    });
    _snapshotFuture = widget.dataRepository.load();
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataRepository != widget.dataRepository ||
        oldWidget.restrictedStartup != widget.restrictedStartup) {
      _pageCache.clear();
      _snapshotFuture = widget.dataRepository.load();
      if (oldWidget.restrictedStartup && !widget.restrictedStartup) {
        _selectedSection = AppSection.transactions;
        _navigationHistory.push(
          _navigationHistory.authenticatedPath(
            _pathForSection(AppSection.transactions),
          ),
        );
      } else {
        _selectedSection = widget.restrictedStartup
            ? AppSection.transactions
            : _sectionFromPath(_navigationHistory.currentPath);
      }
    }
  }

  @override
  void dispose() {
    _navigationSubscription?.cancel();
    _navigationHistory.dispose();
    super.dispose();
  }

  List<AppSection> get _navigationSections => [
    for (final section in AppSection.values)
      if (section != AppSection.migrationAssistance ||
          widget.migrationAssistance)
        section,
  ];

  int get _selectedNavigationIndex =>
      _navigationSections.indexOf(_selectedSection);

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
              child: RefreshIndicator.adaptive(
                onRefresh: _reloadData,
                notificationPredicate: (_) => true,
                child: FutureBuilder<AppDataSnapshot>(
                  future: _snapshotFuture,
                  builder: (context, snapshot) {
                    return _buildContent(snapshot);
                  },
                ),
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
        selectedIndex: _selectedNavigationIndex,
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
          for (final section in _navigationSections)
            NavigationRailDestination(
              icon: Icon(section.icon),
              selectedIcon: Icon(section.selectedIcon),
              label: Text(section.label),
              disabled:
                  widget.restrictedStartup &&
                  section != AppSection.transactions,
            ),
        ],
      ),
    );
  }

  Widget _buildNavigationBar() {
    return NavigationBar(
      selectedIndex: _selectedNavigationIndex,
      onDestinationSelected: _selectSection,
      destinations: [
        for (final section in _navigationSections)
          NavigationDestination(
            icon: Icon(section.icon),
            selectedIcon: Icon(section.selectedIcon),
            label: section.compactLabel,
            enabled:
                !widget.restrictedStartup || section == AppSection.transactions,
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
    if (widget.restrictedStartup &&
        _selectedSection != AppSection.transactions) {
      return const AppLoadingPage();
    }

    final sections = _navigationSections;
    return IndexedStack(
      index: sections.indexOf(_selectedSection),
      children: [
        for (final section in sections)
          _visitedSections.contains(section)
              ? _cachedSection(section, data)
              : const SizedBox.shrink(),
      ],
    );
  }

  Widget _cachedSection(AppSection section, AppDataSnapshot data) {
    if (widget.restrictedStartup && section == AppSection.transactions) {
      return _createSection(section, data);
    }
    return _pageCache.putIfAbsent(section, () => _createSection(section, data));
  }

  Widget _createSection(AppSection section, AppDataSnapshot data) {
    return switch (section) {
      AppSection.overview => OverviewPage(data: data),
      AppSection.transactions => TransactionsPage(
        data: data,
        onTransactionAdded: _handleTransactionAdded,
        onTransactionsAdded: _handleTransactionsAdded,
        onTemplateAdded: _handleTemplateAdded,
        onTemplateUpdated: _updateTemplate,
        allowTemplateManagement: !widget.restrictedStartup,
        restrictedStartup: widget.restrictedStartup,
        onStartupSignIn: widget.onStartupSignIn,
        startupError: widget.startupError,
        onRetryOutbox: widget.onRetryOutbox,
        onTransactionFormActiveChanged: widget.onTransactionFormActiveChanged,
      ),
      AppSection.accounts => AccountsPage(data: data),
      AppSection.analysis => AnalysisPage(
        data: data,
        onIncomeAllocationAdded: _handleIncomeAllocationAdded,
        onRebuildDailyTables: _rebuildAndReloadDailyTables,
      ),
      AppSection.assetsLiabilities => AssetsLiabilitiesPage(
        data: data,
        onValuationsAdded: _handleValuationsAdded,
      ),
      AppSection.migrationAssistance => MigrationAssistancePage(data: data),
      AppSection.settings => SettingsPage(
        data: data,
        onSaveDisplayPreferences: _saveDisplayPreferences,
        onRebuildDailyTables: widget.onRebuildDailyTables == null
            ? null
            : _rebuildAndReloadDailyTables,
        onReloadData: widget.onReloadData ?? _reloadData,
        textScale: widget.textScale,
        onTextScaleChanged: widget.onTextScaleChanged,
      ),
    };
  }

  void _selectSection(int index) {
    final section = _navigationSections[index];
    if (widget.restrictedStartup && section != AppSection.transactions) {
      return;
    }
    _visitedSections.add(section);
    setState(() => _selectedSection = section);
    _navigationHistory.push(
      _navigationHistory.authenticatedPath(_pathForSection(section)),
    );
  }

  AppSection _sectionFromPath(String path) {
    final segments = Uri.parse(path).pathSegments;
    final segment = segments.isEmpty ? null : segments.last;
    return switch (segment) {
      'transactions' => AppSection.transactions,
      'analysis' => AppSection.analysis,
      'accounts' => AppSection.accounts,
      'assets-liabilities' => AppSection.assetsLiabilities,
      'settings' => AppSection.settings,
      'migration-assistance' when widget.migrationAssistance =>
        AppSection.migrationAssistance,
      _ => AppSection.overview,
    };
  }

  String _pathForSection(AppSection section) {
    final currentPath = _navigationHistory.currentPath;
    final segments = Uri.parse(currentPath).pathSegments;
    final knownSection = const {
      'transactions',
      'analysis',
      'accounts',
      'assets-liabilities',
      'settings',
      'migration-assistance',
    }.contains(segments.isEmpty ? null : segments.last);
    final baseSegments = knownSection && segments.isNotEmpty
        ? segments.sublist(0, segments.length - 1)
        : segments;
    final base = baseSegments.isEmpty ? '' : '/${baseSegments.join('/')}';
    final suffix = switch (section) {
      AppSection.overview => '',
      AppSection.transactions => '/transactions',
      AppSection.analysis => '/analysis',
      AppSection.accounts => '/accounts',
      AppSection.assetsLiabilities => '/assets-liabilities',
      AppSection.settings => '/settings',
      AppSection.migrationAssistance => '/migration-assistance',
    };
    return base.isEmpty ? (suffix.isEmpty ? '/' : suffix) : '$base$suffix';
  }

  void _reload() {
    _pageCache.clear();
    setState(() {
      _snapshotFuture = widget.dataRepository.reload();
    });
  }

  Future<void> _reloadData() async {
    await widget.onReconcileDailyTables?.call();
    final future = widget.dataRepository.reload();
    _pageCache.clear();
    setState(() {
      _snapshotFuture = future;
    });
    await future;
  }

  Future<void> _rebuildAndReloadDailyTables() async {
    await widget.onRebuildDailyTables?.call();
    await _reloadData();
  }

  Future<void> _handleValuationsAdded(
    List<DailyManualValuation> valuations,
  ) async {
    final future = _writeCoordinator.run(
      () => widget.dataRepository.addManualValuations(valuations),
    );
    _pageCache.clear();
    setState(() {
      _snapshotFuture = future;
    });
    await future;
    final rebuildNetWorth = widget.onRebuildNetWorth;
    if (rebuildNetWorth != null && valuations.isNotEmpty) {
      final earliest = valuations
          .map((valuation) => valuation.date)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      await rebuildNetWorth(earliest);
      await _reloadData();
    }
  }

  Future<void> _updateTemplate(TransactionTemplate template) async {
    final future = _writeCoordinator.run(() async {
      final current = await widget.dataRepository.reload();
      final latest = current.transactionTemplatesById[template.id];
      if (latest == null) {
        throw StateError('Template ${template.id} no longer exists.');
      }
      return widget.dataRepository.updateTransactionTemplate(
        latest.copyWith(isFavorite: template.isFavorite),
      );
    });
    _pageCache.clear();
    setState(() {
      _snapshotFuture = future;
    });
    await future;
    await widget.onRefreshFormSnapshot?.call();
  }

  Future<void> _saveDisplayPreferences(
    List<DisplayPreference> preferences,
  ) async {
    final future = _writeCoordinator.run(
      () => widget.dataRepository.saveDisplayPreferences(preferences),
    );
    _pageCache.clear();
    setState(() {
      _snapshotFuture = future;
    });
    await future;
  }

  Future<void> _handleIncomeAllocationAdded(IncomeAllocation allocation) async {
    final future = _writeCoordinator.run(
      () => widget.dataRepository.addIncomeAllocation(allocation),
    );
    _pageCache.clear();
    setState(() {
      _snapshotFuture = future;
    });
    await future;
  }

  Future<void> _handleTemplateAdded(TransactionTemplate template) async {
    final future = _writeCoordinator.run(() async {
      await widget.dataRepository.reload();
      return widget.dataRepository.addTransactionTemplate(template);
    });
    _pageCache.clear();
    setState(() {
      _snapshotFuture = future;
    });
    await future;
    await widget.onRefreshFormSnapshot?.call();
  }

  Future<void> _handleTransactionsAdded(List<Transaction> transactions) async {
    var saved = false;
    try {
      Future<void> write() async {
        await widget.dataRepository.reload();
        final future = widget.dataRepository.addTransactions(transactions);
        _pageCache.clear();
        setState(() => _snapshotFuture = future);
        await future;
      }

      if (widget.restrictedStartup) {
        await write();
        return;
      }
      await _writeCoordinator.run(write);
      saved = true;
      await widget.onReconcileDailyTables?.call();
      await _reloadDataWithoutReconciliation();
    } catch (error) {
      if (error is TransactionSavedHistoryRepairException) rethrow;
      if (saved && widget.onReconcileDailyTables != null) {
        throw TransactionSavedHistoryRepairException(error);
      }
      rethrow;
    }
  }

  Future<void> _handleTransactionAdded(Transaction transaction) async {
    var saved = false;
    try {
      Future<void> write() async {
        await widget.dataRepository.reload();
        final future = widget.dataRepository.addTransaction(transaction);
        _pageCache.clear();
        setState(() => _snapshotFuture = future);
        await future;
      }

      if (widget.restrictedStartup) {
        await write();
        return;
      }
      await _writeCoordinator.run(write);
      saved = true;
      await widget.onReconcileDailyTables?.call();
      await _reloadDataWithoutReconciliation();
    } catch (error) {
      if (error is TransactionSavedHistoryRepairException) rethrow;
      if (saved && widget.onReconcileDailyTables != null) {
        throw TransactionSavedHistoryRepairException(error);
      }
      rethrow;
    }
  }

  Future<void> _reloadDataWithoutReconciliation() async {
    final future = widget.dataRepository.reload();
    _pageCache.clear();
    setState(() => _snapshotFuture = future);
    await future;
  }
}

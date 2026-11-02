import 'dart:async';

import 'package:flutter/material.dart';

import '../data/data.dart';
import 'pages/app_pages.dart';
import 'pages/assets_liabilities_page.dart';
import 'pages/transactions_page.dart';
import 'pages/settings_page.dart';
import 'navigation_history.dart';
import '../features/analysis/analysis_page.dart';
import '../features/milestones/milestones_page.dart';
import '../features/migration_assistance/migration_assistance_page.dart';
import 'theme/design_tokens.dart';

enum AppSection {
  transactions,
  analysis,
  accounts,
  milestones,
  settings,
  migrationAssistance,
}

extension AppSectionDetails on AppSection {
  String get label => switch (this) {
    AppSection.transactions => 'Transactions',
    AppSection.analysis => 'Analysis',
    AppSection.accounts => 'Accounts',
    AppSection.milestones => 'Milestones',
    AppSection.settings => 'Settings',
    AppSection.migrationAssistance => 'Migration Assistance',
  };

  String get compactLabel => switch (this) {
    AppSection.transactions => 'Transactions',
    AppSection.analysis => 'Analysis',
    AppSection.accounts => 'Accounts',
    AppSection.milestones => 'Milestones',
    AppSection.settings => 'Settings',
    AppSection.migrationAssistance => 'Migration Assistance',
  };

  IconData get icon => switch (this) {
    AppSection.transactions => Icons.receipt_long_outlined,
    AppSection.analysis => Icons.insights_outlined,
    AppSection.accounts => Icons.account_balance_wallet_outlined,
    AppSection.milestones => Icons.celebration_outlined,
    AppSection.settings => Icons.settings_outlined,
    AppSection.migrationAssistance => Icons.compare_arrows_outlined,
  };

  IconData get selectedIcon => switch (this) {
    AppSection.transactions => Icons.receipt_long,
    AppSection.analysis => Icons.insights,
    AppSection.accounts => Icons.account_balance_wallet,
    AppSection.milestones => Icons.celebration,
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
    this.onFinalizeMigrationTransactions,
    this.onMigrateTransactions,
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
  final Future<AppDataSnapshot> Function()? onRebuildDailyTables;
  final Future<AppDataSnapshot> Function()? onReconcileDailyTables;
  final Future<MigrationBatchStatus> Function()?
  onFinalizeMigrationTransactions;
  final Future<MigrationExecutionResult> Function()? onMigrateTransactions;
  final Future<void> Function()? onRefreshFormSnapshot;
  final Future<AppDataSnapshot> Function(DateTime startDate)? onRebuildNetWorth;
  final Future<void> Function()? onReloadData;
  final double textScale;
  final ValueChanged<double>? onTextScaleChanged;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _compactPrimarySections = [
    AppSection.transactions,
    AppSection.analysis,
    AppSection.accounts,
    AppSection.milestones,
    AppSection.settings,
  ];

  late Future<AppDataSnapshot> _snapshotFuture;
  late final NavigationHistory _navigationHistory;
  StreamSubscription<String>? _navigationSubscription;
  AppSection _selectedSection = AppSection.transactions;
  final Set<AppSection> _visitedSections = {};
  Set<String> _pendingAchievementIds = {};
  final Map<AppSection, Widget> _pageWidgets = {};
  AppDataSnapshot? _pageWidgetData;
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
        const fallback = AppSection.transactions;
        _visitedSections.add(fallback);
        setState(() => _selectedSection = fallback);
        _navigationHistory.replace(
          _navigationHistory.authenticatedPath(_pathForSection(fallback)),
        );
        return;
      }
      final section = _sectionFromPath(path);
      if (widget.restrictedStartup && section != AppSection.transactions) {
        setState(() {
          _visitedSections.add(AppSection.transactions);
          _selectedSection = AppSection.transactions;
        });
        _navigationHistory.replace(
          _navigationHistory.authenticatedPath(
            _pathForSection(AppSection.transactions),
          ),
        );
        return;
      }
      _visitedSections.add(section);
      setState(() => _selectedSection = section);
    });
    _snapshotFuture = _loadSnapshotAndUpdateMilestones();
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    _pageWidgets.clear();
    _pageWidgetData = null;
    if (oldWidget.dataRepository != widget.dataRepository ||
        oldWidget.restrictedStartup != widget.restrictedStartup) {
      _snapshotFuture = _loadSnapshotAndUpdateMilestones();
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

  Future<AppDataSnapshot> _loadSnapshotAndUpdateMilestones({
    bool reload = false,
  }) => _observeMilestoneState(
    reload ? widget.dataRepository.reload() : widget.dataRepository.load(),
  );

  Future<AppDataSnapshot> _observeMilestoneState(
    Future<AppDataSnapshot> source,
  ) async {
    var data = await source;
    final startDate = data.achievementStartDate;
    if (startDate == null) {
      if (mounted) setState(() => _pendingAchievementIds = {});
      return data;
    }

    var evaluation = NetWorthAchievementCalculator.evaluate(
      dailyNetWorth: data.dailyNetWorth,
      trackingStartDate: startDate,
      achievements: data.achievements,
      processedThrough: data.dailyProcessedThrough,
    );
    if (evaluation.validationErrors.isNotEmpty) {
      throw DataValidationFailure([
        for (final message in evaluation.validationErrors)
          DataValidationIssue(table: 'Achievements', message: message),
      ]);
    }
    final resetIds = evaluation.earnedFlagsToReset;
    if (resetIds.isNotEmpty) {
      for (final id in resetIds) {
        data = await _writeCoordinator.run(
          () =>
              widget.dataRepository.updateAchievementEarned(id, earned: false),
        );
      }
      evaluation = NetWorthAchievementCalculator.evaluate(
        dailyNetWorth: data.dailyNetWorth,
        trackingStartDate: data.achievementStartDate ?? startDate,
        achievements: data.achievements,
        processedThrough: data.dailyProcessedThrough,
      );
      if (evaluation.validationErrors.isNotEmpty) {
        throw DataValidationFailure([
          for (final message in evaluation.validationErrors)
            DataValidationIssue(table: 'Achievements', message: message),
        ]);
      }
    }
    if (mounted) {
      final pending = {
        for (final item in evaluation.pendingCelebrations) item.achievement.id,
      };
      if (!_setEquals(_pendingAchievementIds, pending)) {
        setState(() => _pendingAchievementIds = pending);
      }
    }
    return data;
  }

  static bool _setEquals(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  Widget _sectionIcon(AppSection section, {required bool selected}) {
    final icon = selected ? section.selectedIcon : section.icon;
    if (section == AppSection.milestones && _pendingAchievementIds.isNotEmpty) {
      return _PulsingMilestoneIcon(icon: icon);
    }
    return Icon(icon);
  }

  Future<void> _acknowledgeAchievement(String achievementId) async {
    await _writeCoordinator.run(
      () => widget.dataRepository.updateAchievementEarned(
        achievementId,
        earned: true,
      ),
    );
    if (!mounted) return;
    setState(() => _pendingAchievementIds.remove(achievementId));
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
              icon: _sectionIcon(section, selected: false),
              selectedIcon: _sectionIcon(section, selected: true),
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
    if (_navigationSections.length > _compactPrimarySections.length &&
        _compactNavigationLabelsNeedMoreSpace(context)) {
      return _buildCompactNavigationToolbar();
    }
    final hasMore = _navigationSections.length > _compactPrimarySections.length;
    final visibleSections = hasMore
        ? _compactPrimarySections
        : _navigationSections;
    final selectedIndex = visibleSections.indexOf(_selectedSection);
    return NavigationBar(
      selectedIndex: selectedIndex < 0 ? visibleSections.length : selectedIndex,
      onDestinationSelected: _selectCompactDestination,
      destinations: [
        for (final section in visibleSections)
          NavigationDestination(
            icon: _sectionIcon(section, selected: false),
            selectedIcon: _sectionIcon(section, selected: true),
            label: section.label,
            enabled:
                !widget.restrictedStartup || section == AppSection.transactions,
          ),
        if (hasMore)
          NavigationDestination(
            icon: _moreNavigationIcon(),
            selectedIcon: _moreNavigationIcon(),
            label: 'More',
            enabled: !widget.restrictedStartup,
          ),
      ],
    );
  }

  bool _compactNavigationLabelsNeedMoreSpace(BuildContext context) {
    final style =
        NavigationBarTheme.of(context).labelTextStyle
            ?.resolve(const {WidgetState.selected}) ??
        Theme.of(context).textTheme.labelSmall;
    final labelFontSize = style?.fontSize ?? 12;
    return MediaQuery.textScalerOf(context).scale(labelFontSize) > 13.5;
  }

  Widget _buildCompactNavigationToolbar() {
    return SafeArea(
      top: false,
      child: Material(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppPageSpacing.compactGutter,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _selectedSection.label,
                  maxLines: 2,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton(
                onPressed: widget.restrictedStartup
                    ? null
                    : () =>
                          unawaited(_openMoreNavigation(showAllSections: true)),
                child: const Text('Navigate'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _moreNavigationIcon() {
    final pending = _pendingAchievementIds.isNotEmpty;
    return Semantics(
      label: pending ? 'More; milestone ready to acknowledge' : 'More',
      child: Badge(
        isLabelVisible: pending,
        smallSize: 8,
        child: const Icon(Icons.more_horiz),
      ),
    );
  }

  void _selectCompactDestination(int index) {
    if (index < _compactPrimarySections.length) {
      _selectSectionValue(_compactPrimarySections[index]);
    } else {
      unawaited(_openMoreNavigation());
    }
  }

  Future<void> _openMoreNavigation({bool showAllSections = false}) async {
    if (widget.restrictedStartup) return;
    final sections = showAllSections
        ? _navigationSections
        : _navigationSections.skip(_compactPrimarySections.length).toList();
    final section = await showModalBottomSheet<AppSection>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _MoreNavigationSheet(
        title: showAllSections ? 'Navigate' : 'More destinations',
        sections: sections,
        selectedSection: _selectedSection,
        pendingMilestone: _pendingAchievementIds.isNotEmpty,
      ),
    );
    if (section != null && mounted) _selectSectionValue(section);
  }

  Widget _buildContent(AsyncSnapshot<AppDataSnapshot> snapshot) {
    if (snapshot.hasError) {
      final error = snapshot.error!;
      if (error is DataValidationFailure) {
        return DataValidationPage(failure: error, onReload: _reload);
      }
      return AppErrorPage(error: error, onReload: _reload);
    }

    final data = snapshot.data;
    if (data == null || snapshot.connectionState == ConnectionState.waiting) {
      if (data != null) return _buildReadyContent(data, refreshing: true);
      return const AppLoadingPage();
    }
    return _buildReadyContent(data);
  }

  Widget _buildReadyContent(AppDataSnapshot data, {bool refreshing = false}) {
    if (widget.restrictedStartup &&
        _selectedSection != AppSection.transactions) {
      return const AppLoadingPage();
    }
    final sections = _navigationSections;
    return Stack(
      fit: StackFit.expand,
      children: [
        IndexedStack(
          index: sections.indexOf(_selectedSection),
          children: [
            for (final section in sections)
              TickerMode(
                enabled: section == _selectedSection,
                child: _visitedSections.contains(section)
                    ? _cachedSection(section, data)
                    : const SizedBox.shrink(),
              ),
          ],
        ),
        if (refreshing)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(child: LinearProgressIndicator()),
          ),
      ],
    );
  }

  Widget _cachedSection(AppSection section, AppDataSnapshot data) {
    if (!identical(_pageWidgetData, data)) {
      _pageWidgets.clear();
      _pageWidgetData = data;
    }
    return _pageWidgets.putIfAbsent(
      section,
      () => _createSection(section, data),
    );
  }

  Widget _createSection(AppSection section, AppDataSnapshot data) {
    return switch (section) {
      AppSection.transactions => TransactionsPage(
        key: ValueKey<AppSection>(section),
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
      AppSection.accounts => AccountsPage(
        key: ValueKey<AppSection>(section),
        data: data,
        onValuationsAdded: _handleValuationsAdded,
      ),
      AppSection.analysis => AnalysisPage(
        key: ValueKey<AppSection>(section),
        data: data,
        onIncomeAllocationAdded: _handleIncomeAllocationAdded,
        onRebuildDailyTables: _rebuildAndReloadDailyTables,
      ),
      AppSection.milestones => MilestonesPage(
        key: ValueKey<AppSection>(section),
        data: data,
        onAchievementAcknowledged: _acknowledgeAchievement,
      ),
      AppSection.migrationAssistance => MigrationAssistancePage(
        key: ValueKey<AppSection>(section),
        data: data,
        onFinalizeTransactions: widget.onFinalizeMigrationTransactions == null
            ? null
            : _finalizeMigrationTransactions,
        onMigrateTransactions: widget.onMigrateTransactions == null
            ? null
            : _migrateTransactions,
      ),
      AppSection.settings => SettingsPage(
        key: ValueKey<AppSection>(section),
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
    _selectSectionValue(_navigationSections[index]);
  }

  void _selectSectionValue(AppSection section) {
    if (widget.restrictedStartup && section != AppSection.transactions) {
      return;
    }
    if (section == _selectedSection) return;
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
      'milestones' => AppSection.milestones,
      'accounts' => AppSection.accounts,
      'settings' => AppSection.settings,
      'migration-assistance' when widget.migrationAssistance =>
        AppSection.migrationAssistance,
      _ => AppSection.transactions,
    };
  }

  String _pathForSection(AppSection section) {
    final currentPath = _navigationHistory.currentPath;
    final segments = Uri.parse(currentPath).pathSegments;
    final knownSection = const {
      'transactions',
      'analysis',
      'milestones',
      'accounts',
      'settings',
      'migration-assistance',
    }.contains(segments.isEmpty ? null : segments.last);
    final baseSegments = knownSection && segments.isNotEmpty
        ? segments.sublist(0, segments.length - 1)
        : segments;
    final base = baseSegments.isEmpty ? '' : '/${baseSegments.join('/')}';
    final suffix = switch (section) {
      AppSection.transactions => '/transactions',
      AppSection.analysis => '/analysis',
      AppSection.milestones => '/milestones',
      AppSection.accounts => '/accounts',
      AppSection.settings => '/settings',
      AppSection.migrationAssistance => '/migration-assistance',
    };
    return base.isEmpty ? (suffix.isEmpty ? '/' : suffix) : '$base$suffix';
  }

  void _reload() {
    setState(() {
      _snapshotFuture = _loadSnapshotAndUpdateMilestones(reload: true);
    });
  }

  Future<void> _reloadData() async {
    final reconcile = widget.onReconcileDailyTables;
    final future = _observeMilestoneState(
      reconcile == null ? widget.dataRepository.reload() : reconcile(),
    );
    setState(() {
      _snapshotFuture = future;
    });
    await future;
  }

  Future<void> _rebuildAndReloadDailyTables() async {
    final rebuild = widget.onRebuildDailyTables;
    if (rebuild == null) {
      await _reloadData();
      return;
    }
    final future = _observeMilestoneState(rebuild());
    setState(() {
      _snapshotFuture = future;
    });
    await future;
  }

  Future<void> _handleValuationsAdded(
    List<DailyManualValuation> valuations,
  ) async {
    final future = _writeCoordinator.run(
      () => widget.dataRepository.addManualValuations(valuations),
    );
    setState(() {
      _snapshotFuture = _observeMilestoneState(future);
    });
    await future;
    if (!mounted) return;
    final rebuildNetWorth = widget.onRebuildNetWorth;
    if (rebuildNetWorth != null && valuations.isNotEmpty) {
      final earliest = valuations
          .map((valuation) => valuation.date)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      final rebuilt = _observeMilestoneState(rebuildNetWorth(earliest));
      setState(() {
        _snapshotFuture = rebuilt;
      });
      await rebuilt;
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
    setState(() {
      _snapshotFuture = _observeMilestoneState(future);
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
    setState(() {
      _snapshotFuture = _observeMilestoneState(future);
    });
    await future;
  }

  Future<void> _handleIncomeAllocationAdded(IncomeAllocation allocation) async {
    final future = _writeCoordinator.run(
      () => widget.dataRepository.addIncomeAllocation(allocation),
    );
    setState(() {
      _snapshotFuture = _observeMilestoneState(future);
    });
    await future;
  }

  Future<void> _handleTemplateAdded(TransactionTemplate template) async {
    final future = _writeCoordinator.run(() async {
      await widget.dataRepository.reload();
      return widget.dataRepository.addTransactionTemplate(template);
    });
    setState(() {
      _snapshotFuture = _observeMilestoneState(future);
    });
    await future;
    await widget.onRefreshFormSnapshot?.call();
  }

  Future<void> _handleTransactionsAdded(List<Transaction> transactions) async {
    var saved = false;
    try {
      Future<AppDataSnapshot> write() async {
        await widget.dataRepository.reload();
        return widget.dataRepository.addTransactions(transactions);
      }

      final savedSnapshot = widget.restrictedStartup
          ? await write()
          : await _writeCoordinator.run(write);
      saved = true;
      final reconcile = widget.onReconcileDailyTables;
      final finalSnapshot = widget.restrictedStartup || reconcile == null
          ? savedSnapshot
          : await reconcile();
      if (!mounted) return;
      setState(() {
        _snapshotFuture = _observeMilestoneState(
          Future<AppDataSnapshot>.value(finalSnapshot),
        );
      });
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
      Future<AppDataSnapshot> write() async {
        await widget.dataRepository.reload();
        return widget.dataRepository.addTransaction(transaction);
      }

      final savedSnapshot = widget.restrictedStartup
          ? await write()
          : await _writeCoordinator.run(write);
      saved = true;
      final reconcile = widget.onReconcileDailyTables;
      final finalSnapshot = widget.restrictedStartup || reconcile == null
          ? savedSnapshot
          : await reconcile();
      if (!mounted) return;
      setState(() {
        _snapshotFuture = _observeMilestoneState(
          Future<AppDataSnapshot>.value(finalSnapshot),
        );
      });
    } catch (error) {
      if (error is TransactionSavedHistoryRepairException) rethrow;
      if (saved && widget.onReconcileDailyTables != null) {
        throw TransactionSavedHistoryRepairException(error);
      }
      rethrow;
    }
  }

  Future<void> _reloadDataWithoutReconciliation() async {
    final future = _loadSnapshotAndUpdateMilestones(reload: true);
    setState(() {
      _snapshotFuture = future;
    });
    await future;
  }

  Future<MigrationBatchStatus> _finalizeMigrationTransactions() async {
    final result = await widget.onFinalizeMigrationTransactions!.call();
    await _reloadDataWithoutReconciliation();
    return result;
  }

  Future<MigrationExecutionResult> _migrateTransactions() async {
    var migrated = false;
    try {
      final result = await widget.onMigrateTransactions!.call();
      migrated = !result.wasAlreadyMigrated;
      final reconcile = widget.onReconcileDailyTables;
      final future = reconcile == null
          ? _loadSnapshotAndUpdateMilestones(reload: true)
          : _observeMilestoneState(reconcile());
      setState(() {
        _snapshotFuture = future;
      });
      await future;
      return result;
    } catch (error) {
      if (migrated) throw MigrationHistoryRepairException(error);
      rethrow;
    }
  }
}

class _MoreNavigationSheet extends StatelessWidget {
  const _MoreNavigationSheet({
    required this.title,
    required this.sections,
    required this.selectedSection,
    required this.pendingMilestone,
  });

  final String title;
  final List<AppSection> sections;
  final AppSection selectedSection;
  final bool pendingMilestone;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.75,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppPageSpacing.compactGutter,
                AppSpacing.xs,
                AppPageSpacing.compactGutter,
                AppSpacing.xs,
              ),
              child: Align(alignment: Alignment.centerLeft, child: Text(title)),
            ),
            for (final section in sections)
              InkWell(
                onTap: () => Navigator.of(context).pop(section),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 64),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppPageSpacing.compactGutter,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 40,
                          child:
                              section == AppSection.milestones &&
                                  pendingMilestone
                              ? Badge(smallSize: 8, child: Icon(section.icon))
                              : Icon(section.icon),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(section.label),
                              if (section == AppSection.milestones &&
                                  pendingMilestone)
                                const Text(
                                  'Milestone ready to acknowledge',
                                  softWrap: true,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        selectedSection == section
                            ? const Icon(Icons.check)
                            : const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PulsingMilestoneIcon extends StatefulWidget {
  const _PulsingMilestoneIcon({required this.icon});

  final IconData icon;

  @override
  State<_PulsingMilestoneIcon> createState() => _PulsingMilestoneIconState();
}

class _PulsingMilestoneIconState extends State<_PulsingMilestoneIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) =>
        Transform.scale(scale: 0.94 + _controller.value * 0.14, child: child),
    child: Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFD166), Color(0xFFEF7D68)],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.warning.withValues(alpha: 0.32),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(widget.icon, color: Colors.white, size: 23),
          const Positioned(
            top: -2,
            right: -3,
            child: Icon(Icons.auto_awesome, color: AppColors.teal, size: 13),
          ),
        ],
      ),
    ),
  );
}

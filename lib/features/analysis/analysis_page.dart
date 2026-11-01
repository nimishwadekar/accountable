import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/formatters.dart';
import '../../app/pages/app_pages.dart';
import '../../app/theme/design_tokens.dart';
import '../../app/pages/transaction_form_selectors.dart';
import '../../app/session_ui_preferences.dart';
import '../../data/data.dart';
import 'analysis_calculator.dart';
import 'category_analysis.dart';
import 'income_allocation_dialog.dart';
import 'analysis_chart_widgets.dart';
import 'category_analysis_section.dart';

enum AnalysisRangePreset {
  oneMonth,
  threeMonths,
  sixMonths,
  yearToDate,
  oneYear,
  fiveYears,
  allHistory,
}

enum AccountChartUnit { native, usd }

enum _AnalysisView { trends, categories }

class AnalysisPage extends StatefulWidget {
  const AnalysisPage({
    super.key,
    required this.data,
    this.onIncomeAllocationAdded,
    this.onRebuildDailyTables,
  });

  final AppDataSnapshot data;
  final Future<void> Function(IncomeAllocation allocation)?
  onIncomeAllocationAdded;
  final Future<void> Function()? onRebuildDailyTables;

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  late AnalysisCalculator _calculator;
  DateTimeRange? _allHistoryRange;
  final Map<String, Object> _calculationCache = {};
  late AnalysisRangePreset _netWorthRangePreset;
  late DateTimeRange? _netWorthRange;
  late AnalysisRangePreset _accountRangePreset;
  late DateTimeRange? _accountRange;
  String? _selectedAccountId;
  AccountChartUnit _accountChartUnit = AccountChartUnit.native;
  late CategoryAnalysisCalculator _categoryCalculator;
  late DateTime _categoryMonth;
  String? _categoryTagId;
  _AnalysisView _selectedView = _AnalysisView.trends;
  bool _rebuildingDailyTables = false;
  String? _rebuildError;

  @override
  void initState() {
    super.initState();
    _calculator = AnalysisCalculator(widget.data);
    _allHistoryRange = _calculator.allHistoryRange;
    _categoryCalculator = CategoryAnalysisCalculator(widget.data);
    final months = _availableAnalysisMonths;
    final session = SessionUiPreferences.instance;
    _categoryMonth =
        _storedMonth(months, session.analysisMonth) ??
        (months.isEmpty ? DateTime.now() : months.last);
    _netWorthRangePreset = _storedPreset(session.netWorthRangePreset);
    _netWorthRange = _rangeForPreset(_netWorthRangePreset);
    _accountRangePreset = _storedPreset(session.accountRangePreset);
    _accountRange = _rangeForPreset(_accountRangePreset);
    _selectedAccountId =
        widget.data.visibleAccounts.any(
          (account) => account.id == session.analysisAccountId,
        )
        ? session.analysisAccountId
        : widget.data.visibleAccounts.isEmpty
        ? null
        : widget.data.visibleAccounts.first.id;
    _accountChartUnit = AccountChartUnit.values.firstWhere(
      (unit) => unit.name == session.analysisAccountUnit,
      orElse: () => AccountChartUnit.native,
    );
    _categoryTagId =
        widget.data.visibleTags.any((tag) => tag.id == session.analysisTagId)
        ? session.analysisTagId
        : null;
  }

  @override
  void didUpdateWidget(covariant AnalysisPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _calculator = AnalysisCalculator(widget.data);
      _categoryCalculator = CategoryAnalysisCalculator(widget.data);
      _allHistoryRange = _calculator.allHistoryRange;
      _calculationCache.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    CategoryAnalysisResult? spending;
    CategoryAnalysisResult? income;
    MissingExchangeRateException? missingRates;
    try {
      spending = _cached(
        'spending:${_categoryMonth.toIso8601String()}:${_categoryTagId ?? ''}',
        () => _categoryCalculator.spending(
          month: _categoryMonth,
          tagId: _categoryTagId,
        ),
      );
    } on MissingExchangeRateException catch (error) {
      missingRates = error;
    }
    try {
      income = _cached(
        'income:${_categoryMonth.toIso8601String()}:${_categoryTagId ?? ''}',
        () => _categoryCalculator.income(
          month: _categoryMonth,
          tagId: _categoryTagId,
        ),
      );
    } on MissingExchangeRateException catch (error) {
      missingRates = missingRates == null ? error : missingRates.merge(error);
    }
    if (missingRates != null) return _buildMissingRatesError(missingRates);

    final netWorthRange = _netWorthRange;
    final accountRangeSelection = _accountRange;
    final netWorthSeries = netWorthRange == null
        ? null
        : _cached(
            'net-worth:${_rangeKey(netWorthRange)}',
            () => _calculator.netWorthSeries(netWorthRange),
          );
    final selectedAccount = _selectedAccountId == null
        ? null
        : widget.data.accountsById[_selectedAccountId!];
    final accountRange =
        accountRangeSelection == null || _selectedAccountId == null
        ? null
        : _calculator.accountRange(
            accountId: _selectedAccountId!,
            requestedRange: accountRangeSelection,
          );
    final accountSeries = accountRange == null || _selectedAccountId == null
        ? null
        : _cached(
            'account:${_selectedAccountId!}:${_rangeKey(accountRange)}',
            () => _calculator.accountBalanceSeries(
              accountId: _selectedAccountId!,
              range: accountRange,
            ),
          );
    final trendsView = _selectedView == _AnalysisView.trends;
    return AppPageFrame(
      title: 'Analysis',
      subtitle: 'Explore daily valuation history.',
      scrollStorageKey: PageStorageKey<String>(
        'analysis-${_selectedView.name}',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAnalysisViewSelector(),
          SizedBox(
            height: usesCompactVerticalSpacing(context)
                ? AppSpacing.sm
                : AppSpacing.md,
          ),
          if (trendsView) ...[
            NetWorthSummarySection(data: widget.data),
            SizedBox(
              height: usesCompactVerticalSpacing(context)
                  ? AppSpacing.md
                  : AppSpacing.lg,
            ),
            _buildMissingDataDisclosure(
              netWorthSeries: netWorthSeries,
              accountSeries: accountSeries,
              selectedAccount: selectedAccount,
            ),
            if (netWorthRange == null && accountRangeSelection == null)
              const EmptyState(message: 'No daily history is available yet.')
            else ...[
              if (netWorthRange != null) _buildNetWorthSection(netWorthSeries!),
              if (netWorthRange != null && accountRangeSelection != null)
                SizedBox(
                  height: usesCompactVerticalSpacing(context)
                      ? AppSpacing.md
                      : AppSpacing.lg,
                ),
              if (accountRangeSelection != null)
                _buildAccountSection(
                  accountSeries,
                  selectedAccount,
                  accountRange: accountRange,
                ),
            ],
          ] else
            _buildCategoryAnalysis(spending: spending!, income: income!),
        ],
      ),
    );
  }

  Widget _buildAnalysisViewSelector() => Semantics(
    label: 'Analysis view',
    child: SegmentedButton<_AnalysisView>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment<_AnalysisView>(
          value: _AnalysisView.trends,
          icon: Icon(Icons.show_chart),
          label: Text('Trends'),
        ),
        ButtonSegment<_AnalysisView>(
          value: _AnalysisView.categories,
          icon: Icon(Icons.pie_chart_outline),
          label: Text('Categories'),
        ),
      ],
      selected: {_selectedView},
      onSelectionChanged: (selection) {
        if (selection.isEmpty || selection.single == _selectedView) return;
        setState(() => _selectedView = selection.single);
      },
    ),
  );

  Widget _buildMissingDataDisclosure({
    required DailySeries<DailyNetWorthPoint>? netWorthSeries,
    required DailySeries<AccountBalancePoint>? accountSeries,
    required Account? selectedAccount,
  }) {
    final series =
        <(String label, List<DateTime> missing, List<DateTime> unavailable)>[
          if (netWorthSeries != null &&
              (netWorthSeries.missingDates.isNotEmpty ||
                  netWorthSeries.unavailableDates.isNotEmpty))
            (
              'Net worth',
              netWorthSeries.missingDates,
              netWorthSeries.unavailableDates,
            ),
          if (accountSeries != null &&
              (accountSeries.missingDates.isNotEmpty ||
                  accountSeries.unavailableDates.isNotEmpty))
            (
              selectedAccount?.name ?? 'Selected account',
              accountSeries.missingDates,
              accountSeries.unavailableDates,
            ),
        ];
    if (series.isEmpty) return const SizedBox.shrink();
    final missingCount = series.fold<int>(
      0,
      (total, item) => total + item.$2.length,
    );
    final unavailableCount = series.fold<int>(
      0,
      (total, item) => total + item.$3.length,
    );
    final summary = [
      if (missingCount > 0) '$missingCount missing daily values',
      if (unavailableCount > 0) '$unavailableCount unavailable values/rates',
    ].join(' · ');
    return Card(
      child: ExpansionTile(
        key: const PageStorageKey<String>('analysis-missing-data-disclosure'),
        leading: Icon(
          Icons.warning_amber_rounded,
          color: Theme.of(context).colorScheme.error,
        ),
        title: const Text('View missing data'),
        subtitle: Text(summary),
        children: [
          for (final item in series)
            if (item.$2.isNotEmpty)
              _MissingDateDetails(
                label: item.$1,
                kind: 'Missing daily snapshots',
                dates: item.$2,
              ),
          for (final item in series)
            if (item.$3.isNotEmpty)
              _MissingDateDetails(
                label: item.$1,
                kind: 'Unavailable values or rates',
                dates: item.$3,
              ),
        ],
      ),
    );
  }

  Widget _buildMissingRatesError(MissingExchangeRateException failure) {
    final missing = [...failure.missingRates]
      ..sort((a, b) {
        final currency = a.currencyId.compareTo(b.currencyId);
        return currency == 0 ? a.date.compareTo(b.date) : currency;
      });
    return AppPageFrame(
      title: 'Analysis',
      subtitle: 'Historical analysis needs complete exchange-rate data.',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Theme.of(context).colorScheme.error,
                size: 36,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Historical exchange rates unavailable',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Analysis is hidden rather than showing incomplete or misleading totals. '
                'Try rebuilding the daily tables from Settings.',
              ),
              const SizedBox(height: AppSpacing.md),
              for (final item in missing)
                Text('${item.currencyId} · ${formatDate(item.date)}'),
              if (_rebuildError != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Rebuild failed: $_rebuildError',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (widget.onRebuildDailyTables != null) ...[
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: _rebuildingDailyTables
                      ? null
                      : _rebuildDailyTables,
                  icon: _rebuildingDailyTables
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(
                    _rebuildingDailyTables
                        ? 'Rebuilding daily tables…'
                        : 'Rebuild daily tables',
                  ),
                ),
              ] else ...[
                const SizedBox(height: AppSpacing.md),
                const Text(
                  'When connected to Google Sheets, use Settings → Rebuild daily tables.',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _rebuildDailyTables() async {
    final rebuild = widget.onRebuildDailyTables;
    if (rebuild == null || _rebuildingDailyTables) return;
    setState(() {
      _rebuildingDailyTables = true;
      _rebuildError = null;
    });
    try {
      await rebuild();
    } catch (error) {
      if (mounted) setState(() => _rebuildError = error.toString());
    } finally {
      if (mounted) setState(() => _rebuildingDailyTables = false);
    }
  }

  Widget _buildRangeSelector({
    required String label,
    required AnalysisRangePreset selectedPreset,
    required DateTimeRange? range,
    required ValueChanged<AnalysisRangePreset> onSelected,
  }) {
    final dateRange = range == null
        ? null
        : '${formatDate(range.start)} – ${formatDate(range.end)}';
    return Tooltip(
      message: dateRange == null ? label : '$label: $dateRange',
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final preset in AnalysisRangePreset.values)
            _buildRangeOption(
              preset: preset,
              selected: selectedPreset == preset,
              onSelected: onSelected,
            ),
        ],
      ),
    );
  }

  Widget _buildRangeOption({
    required AnalysisRangePreset preset,
    required bool selected,
    required ValueChanged<AnalysisRangePreset> onSelected,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: _presetLabel(preset),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        onTap: () => onSelected(preset),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minHeight: 48),
          margin: const EdgeInsets.all(2),
          padding: EdgeInsets.symmetric(
            horizontal:
                MediaQuery.sizeOf(context).width < AppBreakpoints.compact
                ? AppSpacing.sm
                : AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: selected ? colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _presetShortLabel(preset),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected
                      ? colorScheme.onPrimary
                      : colorScheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNetWorthSection(DailySeries<DailyNetWorthPoint> series) {
    final usd = widget.data.currenciesById['USD'];
    final chartPoints = _cached(
      'net-worth-chart:${_rangeKey(_netWorthRange!)}',
      () => [
        for (final point in series.points)
          ChartPoint(
            date: point.date,
            value: usd == null ? 0 : point.amount.toMajorUnits(usd).toDouble(),
          ),
      ],
    );
    return AnalysisChartSection(
      title: 'Net worth (USD)',
      subtitle: null,
      warning: null,
      cardBottomPadding: 0,
      footer: _buildRangeSelector(
        label: 'Net Worth Period',
        selectedPreset: _netWorthRangePreset,
        range: _netWorthRange,
        onSelected: (preset) => _selectPreset(preset, forAccount: false),
      ),
      child: series.points.isEmpty
          ? const EmptyState(message: 'No net-worth values in this period.')
          : LineChartWidget(
              points: chartPoints,
              color: _netChangeColor(chartPoints),
              currency: usd,
              axisLabel: 'Value (${usd?.id ?? 'USD'})',
            ),
    );
  }

  Widget _buildAccountSection(
    DailySeries<AccountBalancePoint>? series,
    Account? account, {
    required DateTimeRange? accountRange,
  }) {
    final currency = account == null
        ? null
        : widget.data.currenciesById[account.currencyId];
    final usd = widget.data.currenciesById['USD'];
    final accountIsUsd = currency?.id == 'USD';
    final useUsd =
        usd != null &&
        (accountIsUsd || _accountChartUnit == AccountChartUnit.usd);
    final chartPoints = series == null
        ? const <ChartPoint>[]
        : _cached(
            'account-chart:${account?.id ?? ''}:${_rangeKey(accountRange!)}:${useUsd ? 'usd' : 'native'}',
            () => [
              for (final point in series.points)
                if (!useUsd || point.usdAmount != null)
                  ChartPoint(
                    date: point.date,
                    value: account?.isLiability == true
                        ? (useUsd
                                  ? point.usdAmount
                                            ?.toMajorUnits(usd)
                                            .toDouble() ??
                                        0
                                  : (currency == null
                                        ? 0.0
                                        : point.nativeAmount
                                              .toMajorUnits(currency)
                                              .toDouble()))
                              .abs()
                        : (useUsd
                              ? point.usdAmount?.toMajorUnits(usd).toDouble() ??
                                    0
                              : (currency == null
                                    ? 0
                                    : point.nativeAmount
                                          .toMajorUnits(currency)
                                          .toDouble())),
                  ),
            ],
          );

    return AnalysisChartSection(
      title: 'Account history',
      subtitle: null,
      warning: null,
      cardBottomPadding: 0,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final accountDropdown = TransactionAccountSelector(
                label: 'Account',
                value: _selectedAccountId,
                accounts: widget.data.visibleAccounts,
                data: widget.data,
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedAccountId = value);
                    final session = SessionUiPreferences.instance;
                    session.analysisAccountId = value;
                    session.analysisAccountUnit = _accountChartUnit.name;
                    unawaited(session.persist());
                  }
                },
              );
              final unitToggle = SegmentedButton<AccountChartUnit>(
                segments: accountIsUsd
                    ? const [
                        ButtonSegment(
                          value: AccountChartUnit.usd,
                          label: Text('USD'),
                        ),
                      ]
                    : [
                        ButtonSegment(
                          value: AccountChartUnit.native,
                          label: Text(currency?.id ?? 'Native'),
                        ),
                        const ButtonSegment(
                          value: AccountChartUnit.usd,
                          label: Text('USD'),
                        ),
                      ],
                selected: {
                  accountIsUsd ? AccountChartUnit.usd : _accountChartUnit,
                },
                onSelectionChanged: accountIsUsd
                    ? null
                    : (selection) {
                        setState(() => _accountChartUnit = selection.first);
                        final session = SessionUiPreferences.instance;
                        session.analysisAccountUnit = selection.first.name;
                        unawaited(session.persist());
                      },
              );

              if (constraints.maxWidth < AppBreakpoints.compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    accountDropdown,
                    const SizedBox(height: AppSpacing.sm),
                    unitToggle,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: accountDropdown),
                  const SizedBox(width: AppSpacing.md),
                  unitToggle,
                ],
              );
            },
          ),
        ],
      ),
      footer: _buildRangeSelector(
        label: 'Account Period',
        selectedPreset: _accountRangePreset,
        range: accountRange ?? _accountRange,
        onSelected: (preset) => _selectPreset(preset, forAccount: true),
      ),
      child: chartPoints.isEmpty
          ? const EmptyState(message: 'No account history is available.')
          : LineChartWidget(
              points: chartPoints,
              color: _netChangeColor(
                chartPoints,
                liability: account?.isLiability == true,
              ),
              currency: useUsd ? usd : currency,
              isLiability: account?.isLiability == true,
              markers: account == null || accountRange == null
                  ? const []
                  : [
                      if (!account.openingDate.isBefore(accountRange.start) &&
                          !account.openingDate.isAfter(accountRange.end))
                        ChartMarker(date: account.openingDate, label: 'Opened'),
                      if (account.closingDate != null &&
                          !account.closingDate!.isBefore(accountRange.start) &&
                          !account.closingDate!.isAfter(accountRange.end))
                        ChartMarker(
                          date: account.closingDate!,
                          label: 'Closed',
                        ),
                    ],
              axisLabel: account?.isLiability == true
                  ? 'Debt Value (${(useUsd ? usd : currency)?.id ?? 'USD'})'
                  : 'Value (${(useUsd ? usd : currency)?.id ?? 'USD'})',
            ),
    );
  }

  Color _netChangeColor(List<ChartPoint> points, {bool liability = false}) {
    if (points.length < 2) return AppColors.mutedText;
    final change = liability
        ? points.first.value - points.last.value
        : points.last.value - points.first.value;
    if (change > 0) return AppColors.success;
    if (change < 0) return AppColors.danger;
    return AppColors.mutedText;
  }

  Future<void> _openIncomeAllocationForm() async {
    final allocation = await showDialog<IncomeAllocation>(
      context: context,
      barrierDismissible: false,
      useSafeArea: false,
      builder: (_) => IncomeAllocationDialog(data: widget.data),
    );
    if (!mounted || allocation == null) return;
    try {
      await widget.onIncomeAllocationAdded!(allocation);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Income allocation saved.')));
    } catch (error, stackTrace) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Could Not Save Income Allocation'),
          content: SingleChildScrollView(
            child: SelectableText('$error\n\nTechnical details:\n$stackTrace'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  List<DateTime> get _availableAnalysisMonths {
    final today = DateTime.now();
    return [
      for (var offset = 11; offset >= 0; offset--)
        DateTime.utc(today.year, today.month - offset),
    ];
  }

  Widget _buildCategoryAnalysis({
    required CategoryAnalysisResult spending,
    required CategoryAnalysisResult income,
  }) {
    final months = _availableAnalysisMonths;
    final usd = widget.data.currenciesById['USD'];
    final tagName = _categoryTagId == null
        ? 'All tags'
        : widget.data.tagsById[_categoryTagId!]?.name ?? 'Selected tag';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Categories', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked =
                constraints.maxWidth < 340 ||
                MediaQuery.textScalerOf(context).scale(14) > 18;
            final width = ((constraints.maxWidth - AppSpacing.sm) / 2)
                .clamp(0.0, 240.0)
                .toDouble();
            final monthDropdown = DropdownButtonFormField<DateTime>(
              isExpanded: true,
              initialValue: months.contains(_categoryMonth)
                  ? _categoryMonth
                  : null,
              decoration: const InputDecoration(labelText: 'Month'),
              items: [
                for (final month in months)
                  DropdownMenuItem(
                    value: month,
                    child: Text(_formatMonth(month)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _categoryMonth = value);
                  final session = SessionUiPreferences.instance;
                  session.analysisMonth = value.toIso8601String();
                  unawaited(session.persist());
                }
              },
            );
            final tagFilter = Tooltip(
              message: 'Filter by tag: $tagName',
              child: OutlinedButton.icon(
                onPressed: _showCategoryTagFilter,
                icon: const Icon(Icons.filter_list),
                label: Text(
                  tagName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  monthDropdown,
                  const SizedBox(height: AppSpacing.sm),
                  tagFilter,
                ],
              );
            }
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(width: width, child: monthDropdown),
                SizedBox(width: width, child: tagFilter),
              ],
            );
          },
        ),
        SizedBox(
          height: usesCompactVerticalSpacing(context)
              ? AppSpacing.sm + AppSpacing.xs
              : AppSpacing.md,
        ),
        CategoryAnalysisSection(
          title: 'Spending by Category',
          result: spending,
          usd: usd,
          data: widget.data,
        ),
        SizedBox(
          height: usesCompactVerticalSpacing(context)
              ? AppSpacing.md
              : AppSpacing.lg,
        ),
        CategoryAnalysisSection(
          title: 'Income by Category',
          result: income,
          usd: usd,
          data: widget.data,
          month: _categoryMonth,
          onAddIncomeAllocation: widget.onIncomeAllocationAdded == null
              ? null
              : _openIncomeAllocationForm,
        ),
      ],
    );
  }

  Future<void> _showCategoryTagFilter() async {
    final selected = await showModalBottomSheet<_CategoryTagSelection>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppPageSpacing.compactGutter,
                AppSpacing.xs,
                AppPageSpacing.compactGutter,
                AppSpacing.xs,
              ),
              child: Text('Filter categories by tag'),
            ),
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: const Text('All tags'),
              trailing: _categoryTagId == null ? const Icon(Icons.check) : null,
              onTap: () =>
                  Navigator.of(context).pop(const _CategoryTagSelection(null)),
            ),
            for (final tag in widget.data.visibleTags)
              ListTile(
                leading: const Icon(Icons.local_offer_outlined),
                title: Text(tag.name),
                trailing: _categoryTagId == tag.id
                    ? const Icon(Icons.check)
                    : null,
                onTap: () =>
                    Navigator.of(context).pop(_CategoryTagSelection(tag.id)),
              ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    final tagId = selected.tagId;
    setState(() => _categoryTagId = tagId);
    final session = SessionUiPreferences.instance;
    session.analysisTagId = tagId;
    unawaited(session.persist());
  }

  String _formatMonth(DateTime month) =>
      '${_monthName(month.month)} ${month.year}';

  String _monthName(int month) => const [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ][month - 1];

  T _cached<T>(String key, T Function() compute) {
    final existing = _calculationCache.remove(key);
    if (existing != null) {
      _calculationCache[key] = existing;
      return existing as T;
    }
    final value = compute();
    const maximumCachedCalculations = 24;
    if (_calculationCache.length >= maximumCachedCalculations) {
      _calculationCache.remove(_calculationCache.keys.first);
    }
    _calculationCache[key] = value as Object;
    return value;
  }

  String _rangeKey(DateTimeRange range) =>
      '${range.start.toIso8601String()}-${range.end.toIso8601String()}';

  AnalysisRangePreset _storedPreset(String? value) {
    return AnalysisRangePreset.values.firstWhere(
      (preset) => preset.name == value,
      orElse: () => AnalysisRangePreset.oneMonth,
    );
  }

  DateTime? _storedMonth(List<DateTime> months, String? value) {
    if (value == null) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    final month = DateTime.utc(parsed.year, parsed.month);
    return months.contains(month) ? month : null;
  }

  DateTimeRange? _rangeForPreset(AnalysisRangePreset preset) {
    final allHistory = _allHistoryRange;
    if (allHistory == null) return null;
    final today = DateTime.now();
    final todayOnly = DateTime.utc(today.year, today.month, today.day);
    final yesterday = todayOnly.subtract(const Duration(days: 1));
    final requested = switch (preset) {
      AnalysisRangePreset.oneMonth => DateTimeRange(
        start: _subtractMonths(todayOnly, 1),
        end: yesterday,
      ),
      AnalysisRangePreset.threeMonths => DateTimeRange(
        start: _subtractMonths(todayOnly, 3),
        end: yesterday,
      ),
      AnalysisRangePreset.sixMonths => DateTimeRange(
        start: _subtractMonths(todayOnly, 6),
        end: yesterday,
      ),
      AnalysisRangePreset.yearToDate => DateTimeRange(
        start: DateTime.utc(today.year),
        end: yesterday,
      ),
      AnalysisRangePreset.oneYear => DateTimeRange(
        start: _subtractMonths(todayOnly, 12),
        end: yesterday,
      ),
      AnalysisRangePreset.fiveYears => DateTimeRange(
        start: _subtractMonths(todayOnly, 60),
        end: yesterday,
      ),
      AnalysisRangePreset.allHistory => allHistory,
    };
    return DateTimeRange(
      start: requested.start.isBefore(allHistory.start)
          ? allHistory.start
          : requested.start,
      end: requested.end.isAfter(allHistory.end)
          ? allHistory.end
          : requested.end,
    );
  }

  DateTime _subtractMonths(DateTime date, int months) {
    final firstOfTargetMonth = DateTime.utc(date.year, date.month - months, 1);
    final lastDay = DateTime.utc(
      firstOfTargetMonth.year,
      firstOfTargetMonth.month + 1,
      0,
    ).day;
    return DateTime.utc(
      firstOfTargetMonth.year,
      firstOfTargetMonth.month,
      date.day > lastDay ? lastDay : date.day,
    );
  }

  void _selectPreset(AnalysisRangePreset preset, {required bool forAccount}) {
    final range = _rangeForPreset(preset);
    setState(() {
      if (forAccount) {
        _accountRangePreset = preset;
        _accountRange = range;
      } else {
        _netWorthRangePreset = preset;
        _netWorthRange = range;
      }
    });
    final session = SessionUiPreferences.instance;
    if (forAccount) {
      session.accountRangePreset = preset.name;
    } else {
      session.netWorthRangePreset = preset.name;
    }
    unawaited(session.persist());
  }

  String _presetLabel(AnalysisRangePreset preset) {
    return switch (preset) {
      AnalysisRangePreset.oneMonth => '1 month',
      AnalysisRangePreset.threeMonths => '3 months',
      AnalysisRangePreset.sixMonths => '6 months',
      AnalysisRangePreset.yearToDate => 'Year to date',
      AnalysisRangePreset.oneYear => '1 year',
      AnalysisRangePreset.fiveYears => '5 years',
      AnalysisRangePreset.allHistory => 'All history',
    };
  }

  String _presetShortLabel(AnalysisRangePreset preset) {
    return switch (preset) {
      AnalysisRangePreset.oneMonth => '1M',
      AnalysisRangePreset.threeMonths => '3M',
      AnalysisRangePreset.sixMonths => '6M',
      AnalysisRangePreset.yearToDate => 'YTD',
      AnalysisRangePreset.oneYear => '1Y',
      AnalysisRangePreset.fiveYears => '5Y',
      AnalysisRangePreset.allHistory => 'MAX',
    };
  }
}

class _MissingDateDetails extends StatelessWidget {
  const _MissingDateDetails({
    required this.label,
    required this.kind,
    required this.dates,
  });

  final String label;
  final String kind;
  final List<DateTime> dates;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.xs,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label · $kind', style: Theme.of(context).textTheme.titleSmall),
        Text(dates.map(formatDate).join(', ')),
      ],
    ),
  );
}

class _CategoryTagSelection {
  const _CategoryTagSelection(this.tagId);

  final String? tagId;
}

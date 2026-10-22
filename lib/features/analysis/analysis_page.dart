import 'package:flutter/material.dart';

import '../../app/formatters.dart';
import '../../app/pages/app_pages.dart';
import '../../app/theme/design_tokens.dart';
import '../../app/pages/transaction_form_selectors.dart';
import '../../data/data.dart';
import 'analysis_calculator.dart';
import 'category_analysis.dart';
import 'income_allocation_dialog.dart';
import 'analysis_chart_widgets.dart';
import 'category_analysis_section.dart';

enum AnalysisRangePreset { thirtyDays, ninetyDays, yearToDate, allHistory }

enum AccountChartUnit { native, usd }

class AnalysisPage extends StatefulWidget {
  const AnalysisPage({
    super.key,
    required this.data,
    this.onIncomeAllocationAdded,
  });

  final AppDataSnapshot data;
  final Future<void> Function(IncomeAllocation allocation)?
  onIncomeAllocationAdded;

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  late final AnalysisCalculator _calculator;
  late AnalysisRangePreset _netWorthRangePreset;
  late DateTimeRange? _netWorthRange;
  late AnalysisRangePreset _accountRangePreset;
  late DateTimeRange? _accountRange;
  String? _selectedAccountId;
  AccountChartUnit _accountChartUnit = AccountChartUnit.native;
  late final CategoryAnalysisCalculator _categoryCalculator;
  late DateTime _categoryMonth;
  String? _categoryTagId;

  @override
  void initState() {
    super.initState();
    _calculator = AnalysisCalculator(widget.data);
    _categoryCalculator = CategoryAnalysisCalculator(widget.data);
    final months = _availableAnalysisMonths;
    _categoryMonth = months.isEmpty ? DateTime.now() : months.last;
    _netWorthRangePreset = AnalysisRangePreset.allHistory;
    _netWorthRange = _calculator.allHistoryRange;
    _accountRangePreset = AnalysisRangePreset.allHistory;
    _accountRange = _calculator.allHistoryRange;
    _selectedAccountId = widget.data.visibleAccounts.isEmpty
        ? null
        : widget.data.visibleAccounts.first.id;
  }

  @override
  Widget build(BuildContext context) {
    final netWorthRange = _netWorthRange;
    final accountRangeSelection = _accountRange;
    final netWorthSeries = netWorthRange == null
        ? null
        : _calculator.netWorthSeries(netWorthRange);
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
        : _calculator.accountBalanceSeries(
            accountId: _selectedAccountId!,
            range: accountRange,
          );
    final spending = _categoryCalculator.spending(
      month: _categoryMonth,
      tagId: _categoryTagId,
    );
    final income = _categoryCalculator.income(
      month: _categoryMonth,
      tagId: _categoryTagId,
    );

    return AppPageFrame(
      title: 'Analysis',
      subtitle: 'Explore daily valuation history.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (netWorthRange == null && accountRangeSelection == null)
            const EmptyState(message: 'No daily history is available yet.')
          else ...[
            if (netWorthRange != null) _buildNetWorthSection(netWorthSeries!),
            if (netWorthRange != null && accountRangeSelection != null)
              const SizedBox(height: AppSpacing.xl),
            if (accountRangeSelection != null)
              _buildAccountSection(accountSeries, selectedAccount),
          ],
          const SizedBox(height: AppSpacing.xl),
          _buildCategoryAnalysis(spending: spending, income: income),
        ],
      ),
    );
  }

  Widget _buildRangeSelector({
    required String label,
    required AnalysisRangePreset selectedPreset,
    required DateTimeRange? range,
    required ValueChanged<AnalysisRangePreset> onSelected,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            for (final preset in AnalysisRangePreset.values)
              ChoiceChip(
                label: Text(_presetLabel(preset)),
                selected: selectedPreset == preset,
                onSelected: (_) => onSelected(preset),
              ),
            if (range != null)
              Text(
                '${formatDate(range.start)} – ${formatDate(range.end)}',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AppColors.mutedText),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetWorthSection(DailySeries<DailyNetWorthPoint> series) {
    final usd = widget.data.currenciesById['USD'];
    return AnalysisChartSection(
      title: 'Net Worth Trend',
      subtitle: null,
      warning: _missingWarning(series.missingDates),
      header: _buildRangeSelector(
        label: 'Net Worth Period',
        selectedPreset: _netWorthRangePreset,
        range: _netWorthRange,
        onSelected: (preset) => _selectPreset(preset, forAccount: false),
      ),
      child: series.points.isEmpty
          ? const EmptyState(message: 'No net-worth values in this period.')
          : LineChartWidget(
              points: [
                for (final point in series.points)
                  ChartPoint(
                    date: point.date,
                    value: usd == null
                        ? 0
                        : point.amount.toMajorUnits(usd).toDouble(),
                  ),
              ],
              color: AppColors.teal,
              currency: usd,
              axisLabel: 'Value (${usd?.id ?? 'USD'})',
            ),
    );
  }

  Widget _buildAccountSection(
    DailySeries<AccountBalancePoint>? series,
    Account? account,
  ) {
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
        : [
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
                            ? point.usdAmount?.toMajorUnits(usd).toDouble() ?? 0
                            : (currency == null
                                  ? 0
                                  : point.nativeAmount
                                        .toMajorUnits(currency)
                                        .toDouble())),
                ),
          ];

    return AnalysisChartSection(
      title: 'Individual Account Valuation Trend',
      subtitle: null,
      warning: series == null
          ? null
          : _missingWarning([
              ...series.missingDates,
              ...series.unavailableDates,
            ], includesUnavailableValues: series.unavailableDates.isNotEmpty),
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildRangeSelector(
            label: 'Account Period',
            selectedPreset: _accountRangePreset,
            range: _accountRange,
            onSelected: (preset) => _selectPreset(preset, forAccount: true),
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final accountDropdown = TransactionAccountSelector(
                label: 'Account',
                value: _selectedAccountId,
                accounts: widget.data.visibleAccounts,
                data: widget.data,
                onChanged: (value) {
                  if (value != null) setState(() => _selectedAccountId = value);
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
      child: chartPoints.isEmpty
          ? const EmptyState(message: 'No account history is available.')
          : LineChartWidget(
              points: chartPoints,
              color: account?.isLiability == true
                  ? AppColors.danger
                  : AppColors.navy,
              currency: useUsd ? usd : currency,
              isLiability: account?.isLiability == true,
              axisLabel: account?.isLiability == true
                  ? 'Debt Value (${(useUsd ? usd : currency)?.id ?? 'USD'})'
                  : 'Value (${(useUsd ? usd : currency)?.id ?? 'USD'})',
            ),
    );
  }

  Future<void> _openIncomeAllocationForm() async {
    final allocation = await showDialog<IncomeAllocation>(
      context: context,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Categorical Analysis',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 520;
                return Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  children: [
                    SizedBox(
                      width: narrow ? constraints.maxWidth : 190,
                      child: DropdownButtonFormField<DateTime>(
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
                          }
                        },
                      ),
                    ),
                    SizedBox(
                      width: narrow ? constraints.maxWidth : 240,
                      child: DropdownButtonFormField<String?>(
                        isExpanded: true,
                        initialValue: _categoryTagId,
                        decoration: const InputDecoration(labelText: 'Tag'),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('All Tags'),
                          ),
                          for (final tag in widget.data.visibleTags)
                            DropdownMenuItem(
                              value: tag.id,
                              child: Text(tag.name),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _categoryTagId = value),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        CategoryAnalysisSection(
          title: 'Spending by Category',
          result: spending,
          usd: usd,
          data: widget.data,
        ),
        const SizedBox(height: AppSpacing.lg),
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

  String? _missingWarning(
    List<DateTime> dates, {
    bool includesUnavailableValues = false,
  }) {
    if (dates.isEmpty) return null;
    final preview = dates.take(3).map(formatDate).join(', ');
    final suffix = dates.length > 3 ? ' and ${dates.length - 3} more' : '';
    final subject = includesUnavailableValues
        ? 'daily data or exchange rates'
        : 'daily data';
    return 'Missing $subject for $preview$suffix.';
  }

  void _selectPreset(AnalysisRangePreset preset, {required bool forAccount}) {
    final allHistory = _calculator.allHistoryRange;
    final today = DateTime.now();
    final todayOnly = DateTime.utc(today.year, today.month, today.day);
    final requested = switch (preset) {
      AnalysisRangePreset.thirtyDays => DateTimeRange(
        start: todayOnly.subtract(const Duration(days: 29)),
        end: todayOnly.subtract(const Duration(days: 1)),
      ),
      AnalysisRangePreset.ninetyDays => DateTimeRange(
        start: todayOnly.subtract(const Duration(days: 89)),
        end: todayOnly.subtract(const Duration(days: 1)),
      ),
      AnalysisRangePreset.yearToDate => DateTimeRange(
        start: DateTime.utc(today.year),
        end: todayOnly.subtract(const Duration(days: 1)),
      ),
      AnalysisRangePreset.allHistory => allHistory,
    };
    final range = allHistory == null
        ? null
        : DateTimeRange(
            start: requested!.start.isBefore(allHistory.start)
                ? allHistory.start
                : requested.start,
            end: requested.end.isAfter(allHistory.end)
                ? allHistory.end
                : requested.end,
          );
    setState(() {
      if (forAccount) {
        _accountRangePreset = preset;
        _accountRange = range;
      } else {
        _netWorthRangePreset = preset;
        _netWorthRange = range;
      }
    });
  }

  String _presetLabel(AnalysisRangePreset preset) {
    return switch (preset) {
      AnalysisRangePreset.thirtyDays => '30 days',
      AnalysisRangePreset.ninetyDays => '90 days',
      AnalysisRangePreset.yearToDate => 'Year to date',
      AnalysisRangePreset.allHistory => 'All history',
    };
  }
}


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
    final session = SessionUiPreferences.instance;
    _categoryMonth = _storedMonth(months, session.analysisMonth) ??
        (months.isEmpty ? DateTime.now() : months.last);
    _netWorthRangePreset = _storedPreset(session.netWorthRangePreset);
    _netWorthRange = _rangeForPreset(_netWorthRangePreset);
    _accountRangePreset = _storedPreset(session.accountRangePreset);
    _accountRange = _rangeForPreset(_accountRangePreset);
    _selectedAccountId = widget.data.visibleAccounts.any(
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
    _categoryTagId = widget.data.visibleTags.any(
            (tag) => tag.id == session.analysisTagId,
          )
        ? session.analysisTagId
        : null;
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
    final dateRange = range == null
        ? null
        : '${formatDate(range.start)} – ${formatDate(range.end)}';
    return Tooltip(
      message: dateRange == null ? label : '$label: $dateRange',
      child: Semantics(
        label: dateRange == null ? label : '$label: $dateRange',
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadii.pill),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final preset in AnalysisRangePreset.values)
                  _buildRangeOption(
                    preset: preset,
                    selected: selectedPreset == preset,
                    onSelected: onSelected,
                  ),
              ],
            ),
          ),
        ),
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
          margin: const EdgeInsets.all(3),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Text(
            _presetShortLabel(preset),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected
                  ? colorScheme.onPrimary
                  : colorScheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNetWorthSection(DailySeries<DailyNetWorthPoint> series) {
    final usd = widget.data.currenciesById['USD'];
    final chartPoints = [
      for (final point in series.points)
        ChartPoint(
          date: point.date,
          value: usd == null ? 0 : point.amount.toMajorUnits(usd).toDouble(),
        ),
    ];
    return AnalysisChartSection(
      title: 'Net Worth Trend',
      subtitle: null,
      warning: _missingWarning(series.missingDates),
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
        range: _accountRange,
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
                            final session = SessionUiPreferences.instance;
                            session.analysisMonth = value.toIso8601String();
                            unawaited(session.persist());
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
                        onChanged: (value) {
                          setState(() => _categoryTagId = value);
                          final session = SessionUiPreferences.instance;
                          session.analysisTagId = value;
                          unawaited(session.persist());
                        },
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
    final allHistory = _calculator.allHistoryRange;
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

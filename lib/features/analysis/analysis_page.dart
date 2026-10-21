import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../app/formatters.dart';
import '../../app/pages/app_pages.dart';
import '../../app/theme/design_tokens.dart';
import '../../app/pages/category_visuals.dart';
import '../../app/pages/transaction_form_selectors.dart';
import '../../data/data.dart';
import 'analysis_calculator.dart';
import 'category_analysis.dart';
import 'income_allocation_analysis.dart';
import 'income_allocation_dialog.dart';

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
  late final IncomeAllocationAnalyzer _allocationAnalyzer;
  late DateTime _categoryMonth;
  String? _categoryTagId;

  @override
  void initState() {
    super.initState();
    _calculator = AnalysisCalculator(widget.data);
    _categoryCalculator = CategoryAnalysisCalculator(widget.data);
    _allocationAnalyzer = IncomeAllocationAnalyzer(widget.data);
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
    return _AnalysisChartSection(
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
          : _LineChart(
              points: [
                for (final point in series.points)
                  _ChartPoint(
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
        ? const <_ChartPoint>[]
        : [
            for (final point in series.points)
              if (!useUsd || point.usdAmount != null)
                _ChartPoint(
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

    return _AnalysisChartSection(
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
          : _LineChart(
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
                          for (final tag in widget.data.entryFormTags)
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
        _buildCategoryWidget('Spending by Category', spending, usd),
        const SizedBox(height: AppSpacing.lg),
        _buildCategoryWidget(
          'Income by Category',
          income,
          usd,
          month: _categoryMonth,
        ),
      ],
    );
  }

  Widget _buildCategoryWidget(
    String title,
    CategoryAnalysisResult result,
    CurrencyDefinition? usd, {
    DateTime? month,
  }) {
    final total = result.totalPositive;
    return _AnalysisChartSection(
      title: title,
      subtitle: null,
      header:
          title == 'Income by Category' &&
              widget.onIncomeAllocationAdded != null
          ? Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _openIncomeAllocationForm,
                icon: const Icon(Icons.add),
                label: const Text('Add Income Allocation'),
              ),
            )
          : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trailingWidth = (constraints.maxWidth * 0.42)
              .clamp(112.0, 180.0)
              .toDouble();
          return result.positiveValues.isEmpty
              ? const EmptyState(
                  message: 'No categorized values for this month.',
                )
              : Column(
                  children: [
                    SizedBox(
                      height: 220,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          PieChart(
                            PieChartData(
                              centerSpaceRadius: 48,
                              sectionsSpace: 2,
                              sections: [
                                for (final value in result.positiveValues)
                                  PieChartSectionData(
                                    value: value.amountUsdMinorUnits.toDouble(),
                                    color: _categoryColor(value.categoryId),
                                    title: '',
                                    radius: 72,
                                  ),
                              ],
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Total',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              Text(
                                _formatCategoryAmount(total, usd),
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    for (final value in result.positiveValues) ...[
                      ListTile(
                        dense: true,
                        leading: Icon(
                          _categoryIcon(value.categoryId),
                          color: _categoryColor(value.categoryId),
                        ),
                        title: Text(
                          _categoryName(value.categoryId),
                          maxLines: 2,
                          softWrap: true,
                        ),
                        trailing: SizedBox(
                          width: trailingWidth,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _formatCategoryAmount(
                                    value.amountUsdMinorUnits,
                                    usd,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              SizedBox(
                                width: 52,
                                child: Text(
                                  '${(value.amountUsdMinorUnits / total * 100).toStringAsFixed(1)}%',
                                  maxLines: 1,
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (month != null && value.categoryId != null)
                        ..._buildAllocationRows(value.categoryId!, month),
                    ],
                    const Divider(height: AppSpacing.lg),
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const SizedBox(width: 40),
                      title: Text(
                        'Total:',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      trailing: SizedBox(
                        width: trailingWidth,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _formatCategoryAmount(total, usd),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            const SizedBox(width: 52),
                          ],
                        ),
                      ),
                    ),
                    if (result.negativeAdjustment < 0)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Net reimbursement adjustment: '
                          '${_formatCategoryAmount(result.negativeAdjustment, usd)}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                );
        },
      ),
    );
  }

  List<Widget> _buildAllocationRows(String categoryId, DateTime month) {
    final progress = _allocationAnalyzer.analyze(
      month: month,
      incomeCategoryId: categoryId,
    );
    return [
      for (final item in progress)
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xl,
            top: AppSpacing.xs,
            bottom: AppSpacing.xs,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppRadii.control),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.subdirectory_arrow_right,
                  size: 20,
                  color: item.missingRateDates.isEmpty
                      ? AppColors.teal
                      : AppColors.warning,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.allocation.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                        child: LinearProgressIndicator(
                          minHeight: 5,
                          value: item.expectedUsdMinorUnits <= 0
                              ? 0
                              : (item.actualUsdMinorUnits /
                                        item.expectedUsdMinorUnits)
                                    .clamp(0.0, 1.0),
                          backgroundColor: AppColors.border,
                          valueColor: AlwaysStoppedAnimation(
                            item.actualUsdMinorUnits >=
                                    item.expectedUsdMinorUnits
                                ? AppColors.success
                                : AppColors.teal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${_formatCategoryAmount(item.actualUsdMinorUnits, widget.data.currenciesById['USD'])} / '
                      '${_formatCategoryAmount(item.expectedUsdMinorUnits, widget.data.currenciesById['USD'])}',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (item.percentage != null)
                      Text(
                        '${item.percentage!.toStringAsFixed(0)}%',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: item.percentage! >= 100
                              ? AppColors.success
                              : AppColors.mutedText,
                        ),
                      ),
                  ],
                ),
                if (item.missingRateDates.isNotEmpty)
                  Tooltip(
                    message:
                        'Exchange rate unavailable for ${item.missingRateDates.map(formatDate).join(', ')}',
                    child: const Padding(
                      padding: EdgeInsets.only(left: AppSpacing.sm),
                      child: Icon(
                        Icons.warning_amber_rounded,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
    ];
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

  String _categoryName(String? id) => id == null
      ? 'Uncategorized'
      : widget.data.categoriesById[id]?.name ?? 'Uncategorized';

  IconData _categoryIcon(String? id) {
    final category = id == null ? null : widget.data.categoriesById[id];
    return category == null ? Icons.category_outlined : categoryIcon(category);
  }

  Color _categoryColor(String? id) {
    final category = id == null ? null : widget.data.categoriesById[id];
    return category == null ? AppColors.mutedText : categoryColor(category);
  }

  String _formatCategoryAmount(int minorUnits, CurrencyDefinition? usd) {
    if (usd == null) return '—';
    return formatMoney(
      Money(minorUnits: minorUnits, currencyId: usd.id),
      widget.data.currenciesById,
    );
  }

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

class _AnalysisChartSection extends StatelessWidget {
  const _AnalysisChartSection({
    required this.title,
    required this.subtitle,
    required this.child,
    this.warning,
    this.header,
  });

  final String title;
  final String? subtitle;
  final String? warning;
  final Widget? header;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: AppColors.mutedText),
          ),
        ],
        if (header != null) ...[const SizedBox(height: AppSpacing.md), header!],
        if (warning != null) ...[
          const SizedBox(height: AppSpacing.md),
          _MissingDataNotice(message: warning!),
        ],
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}

class _MissingDataNotice extends StatelessWidget {
  const _MissingDataNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _ChartPoint {
  const _ChartPoint({required this.date, required this.value});

  final DateTime date;
  final double value;
}

class _LineChart extends StatefulWidget {
  const _LineChart({
    required this.points,
    required this.color,
    required this.currency,
    required this.axisLabel,
    this.isLiability = false,
  });

  final List<_ChartPoint> points;
  final Color color;
  final CurrencyDefinition? currency;
  final String axisLabel;
  final bool isLiability;

  @override
  State<_LineChart> createState() => _LineChartState();
}

class _LineChartState extends State<_LineChart> {
  LineTouchResponse? _touchResponse;

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    final color = widget.color;
    final currency = widget.currency;
    final values = points.map((point) => point.value).toList();
    final minimum = values.reduce((a, b) => a < b ? a : b);
    final maximum = values.reduce((a, b) => a > b ? a : b);
    final difference = maximum - minimum;
    final padding = difference == 0
        ? (maximum.abs() * 0.1).clamp(1, double.infinity)
        : difference * 0.1;
    final firstDate = points.first.date;
    final spanDays = points.last.date.difference(firstDate).inDays;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxLabels = (constraints.maxWidth / 88).floor().clamp(3, 8);
        final xInterval = _niceDayInterval(spanDays, maxLabels);
        final xMargin = spanDays == 0 ? 0.5 : spanDays * 0.05;
        final chartMinX = -xMargin;
        final chartMaxX = spanDays == 0 ? 0.5 : spanDays + xMargin;
        final axisStyle =
            Theme.of(context).textTheme.labelSmall ?? const TextStyle();
        final axisReservedSize = _axisReservedSize(
          minimum: minimum - padding,
          maximum: maximum + padding,
          style: axisStyle,
          currency: currency,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        );

        return SizedBox(
          height: 280,
          child: Column(
            children: [
              SizedBox(
                height: 20,
                child: Align(
                  alignment: Alignment.center,
                  child: Text(
                    widget.axisLabel,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ),
              Expanded(
                child: LineChart(
                  LineChartData(
                    minX: chartMinX,
                    maxX: chartMaxX,
                    minY: minimum - padding,
                    maxY: maximum + padding,
                    gridData: const FlGridData(show: true),
                    lineTouchData: LineTouchData(
                      touchCallback: (event, response) {
                        final spots = response?.lineBarSpots;
                        if (spots == null || spots.isEmpty) {
                          if (_touchResponse != null) {
                            setState(() => _touchResponse = null);
                          }
                          return;
                        }
                        setState(() => _touchResponse = response);
                      },
                      touchTooltipData: LineTouchTooltipData(
                        tooltipMargin: 16,
                        tooltipHorizontalAlignment:
                            FLHorizontalAlignment.center,
                        fitInsideHorizontally: true,
                        fitInsideVertically: true,
                        getTooltipColor: (_) => Colors.white,
                        tooltipBorder: const BorderSide(
                          color: AppColors.border,
                        ),
                        getTooltipItems: (spots) {
                          final seen = <String>{};
                          return [
                            for (final spot in spots)
                              if (seen.add(
                                '${spot.x.toStringAsFixed(6)}:${spot.y.toStringAsFixed(6)}',
                              ))
                                LineTooltipItem(
                                  '${currency?.symbol ?? ''} ${_formatChartValue(spot.y)}',
                                  TextStyle(
                                    color: _pointColor(spot.y),
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              else
                                null,
                          ];
                        },
                      ),
                    ),
                    titlesData: FlTitlesData(
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: AxisTitles(
                        axisNameWidget: null,
                        axisNameSize: 0,
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: axisReservedSize,
                          getTitlesWidget: (value, meta) {
                            if (value <= minimum - padding * 0.9 ||
                                value >= maximum + padding * 0.9) {
                              return const SizedBox.shrink();
                            }
                            return Text(
                              currency == null
                                  ? _formatChartValue(value)
                                  : '${currency.symbol} ${_formatChartValue(value)}',
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.clip,
                              style: Theme.of(context).textTheme.labelSmall,
                            );
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        axisNameWidget: null,
                        axisNameSize: 0,
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: xInterval.toDouble(),
                          reservedSize: 32,
                          getTitlesWidget: (value, meta) {
                            final dayOffset = value.round();
                            if ((value - dayOffset).abs() > 0.001 ||
                                dayOffset < 0 ||
                                dayOffset > spanDays) {
                              return const SizedBox.shrink();
                            }
                            final date = firstDate.add(
                              Duration(days: dayOffset),
                            );
                            return Text(
                              _formatShortDate(date),
                              maxLines: 1,
                              softWrap: false,
                              style: Theme.of(context).textTheme.labelSmall,
                            );
                          },
                        ),
                      ),
                    ),
                    lineBarsData: _lineBars(points, firstDate, color),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  double _axisReservedSize({
    required double minimum,
    required double maximum,
    required TextStyle style,
    required CurrencyDefinition? currency,
    required TextDirection textDirection,
    required TextScaler textScaler,
  }) {
    final labels = [
      _axisLabel(minimum, currency),
      _axisLabel(maximum, currency),
      _axisLabel(0, currency),
    ];
    var width = 0.0;
    for (final label in labels) {
      final measuredStyle = style.copyWith(
        fontSize: textScaler.scale(style.fontSize ?? 14),
      );
      final painter = TextPainter(
        text: TextSpan(text: label, style: measuredStyle),
        textDirection: textDirection,
        maxLines: 1,
      )..layout();
      if (painter.width > width) width = painter.width;
    }
    return width + 14;
  }

  String _axisLabel(double value, CurrencyDefinition? currency) {
    final amount = _formatChartValue(value);
    return currency == null ? amount : '${currency.symbol} $amount';
  }

  List<LineChartBarData> _lineBars(
    List<_ChartPoint> points,
    DateTime firstDate,
    Color fallbackColor,
  ) {
    if (points.length == 1) {
      return [
        LineChartBarData(
          spots: [FlSpot(0, points.first.value)],
          color: _pointColor(points.first.value),
          barWidth: 3,
          dotData: const FlDotData(show: true),
        ),
      ];
    }
    return [
      for (var index = 0; index < points.length - 1; index++)
        LineChartBarData(
          spots: [
            FlSpot(
              points[index].date.difference(firstDate).inDays.toDouble(),
              points[index].value,
            ),
            FlSpot(
              points[index + 1].date.difference(firstDate).inDays.toDouble(),
              points[index + 1].value,
            ),
          ],
          color: _pointColor(
            (points[index].value + points[index + 1].value) / 2,
          ),
          barWidth: 3,
          isCurved: false,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: false,
            color: fallbackColor.withValues(alpha: 0.12),
          ),
        ),
    ];
  }

  Color _pointColor(double value) {
    if (widget.isLiability) return AppColors.danger;
    return _amountColor(value);
  }

  static Color _amountColor(double value) {
    if (value > 0) return AppColors.success;
    if (value < 0) return AppColors.danger;
    return AppColors.navy;
  }

  static String _formatChartValue(double value) {
    final fixed = value.toStringAsFixed(2);
    final parts = fixed.split('.');
    final sign = parts.first.startsWith('-') ? '-' : '';
    final integer = sign.isEmpty ? parts.first : parts.first.substring(1);
    final grouped = integer.replaceAllMapped(
      RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '$sign$grouped.${parts[1]}';
  }

  static String _formatShortDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day.toString().padLeft(2, '0')}-${months[date.month - 1]}';
  }

  static int _niceDayInterval(int spanDays, int maxLabels) {
    if (spanDays <= 0) return 1;
    final rawInterval = (spanDays / (maxLabels - 1)).ceil();
    const sensibleIntervals = [
      1,
      2,
      3,
      5,
      7,
      14,
      21,
      30,
      60,
      90,
      120,
      180,
      365,
      730,
      1095,
    ];
    return sensibleIntervals.firstWhere(
      (interval) => interval >= rawInterval,
      orElse: () => rawInterval,
    );
  }
}

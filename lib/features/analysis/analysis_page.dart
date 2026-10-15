import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../app/formatters.dart';
import '../../app/pages/app_pages.dart';
import '../../app/theme/design_tokens.dart';
import '../../data/data.dart';
import 'analysis_calculator.dart';

enum AnalysisRangePreset { thirtyDays, ninetyDays, yearToDate, allHistory }

enum AccountChartUnit { native, usd }

class AnalysisPage extends StatefulWidget {
  const AnalysisPage({super.key, required this.data});

  final AppDataSnapshot data;

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  late final AnalysisCalculator _calculator;
  late AnalysisRangePreset _rangePreset;
  late DateTimeRange? _range;
  String? _selectedAccountId;
  AccountChartUnit _accountChartUnit = AccountChartUnit.native;

  @override
  void initState() {
    super.initState();
    _calculator = AnalysisCalculator(widget.data);
    _rangePreset = AnalysisRangePreset.allHistory;
    _range = _calculator.allHistoryRange;
    _selectedAccountId = widget.data.accounts.isEmpty
        ? null
        : widget.data.accounts.first.id;
  }

  @override
  Widget build(BuildContext context) {
    final range = _range;
    final netWorthSeries = range == null
        ? null
        : _calculator.netWorthSeries(range);
    final selectedAccount = _selectedAccountId == null
        ? null
        : widget.data.accountsById[_selectedAccountId!];
    final accountRange = range == null || _selectedAccountId == null
        ? null
        : _calculator.accountRange(
            accountId: _selectedAccountId!,
            requestedRange: range,
          );
    final accountSeries = accountRange == null || _selectedAccountId == null
        ? null
        : _calculator.accountBalanceSeries(
            accountId: _selectedAccountId!,
            range: accountRange,
          );

    return AppPageFrame(
      title: 'Analysis',
      subtitle: 'Explore daily valuation history.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRangeSelector(),
          const SizedBox(height: AppSpacing.lg),
          if (range == null)
            const EmptyState(message: 'No daily history is available yet.')
          else ...[
            _buildNetWorthSection(netWorthSeries!),
            const SizedBox(height: AppSpacing.xl),
            _buildAccountSection(accountSeries, selectedAccount),
          ],
        ],
      ),
    );
  }

  Widget _buildRangeSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Period', style: Theme.of(context).textTheme.titleMedium),
            for (final preset in AnalysisRangePreset.values)
              ChoiceChip(
                label: Text(_presetLabel(preset)),
                selected: _rangePreset == preset,
                onSelected: (_) => _selectPreset(preset),
              ),
            if (_range != null)
              Text(
                '${formatDate(_range!.start)} – ${formatDate(_range!.end)}',
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
      title: 'Net worth',
      subtitle: 'Daily USD valuation',
      warning: _missingWarning(series.missingDates),
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
    final useUsd = _accountChartUnit == AccountChartUnit.usd;

    return _AnalysisChartSection(
      title: 'Account balance history',
      subtitle: [
        useUsd ? 'Daily USD valuation' : 'Daily ${currency?.id ?? ''} balance',
        if (account?.closingDate != null)
          'Closed on ${formatDate(account!.closingDate!)}',
      ].join(' · '),
      warning: series == null ? null : _missingWarning(series.missingDates),
      header: LayoutBuilder(
        builder: (context, constraints) {
          final accountDropdown = DropdownButtonFormField<String>(
            initialValue: _selectedAccountId,
            decoration: const InputDecoration(labelText: 'Account'),
            items: [
              for (final item in widget.data.accounts)
                DropdownMenuItem<String>(
                  value: item.id,
                  child: Text(item.name),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _selectedAccountId = value);
            },
          );
          final unitToggle = SegmentedButton<AccountChartUnit>(
            segments: const [
              ButtonSegment(
                value: AccountChartUnit.native,
                label: Text('Native'),
              ),
              ButtonSegment(value: AccountChartUnit.usd, label: Text('USD')),
            ],
            selected: {_accountChartUnit},
            onSelectionChanged: (selection) {
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
      child: series == null || series.points.isEmpty
          ? const EmptyState(message: 'No account history is available.')
          : _LineChart(
              points: [
                for (final point in series.points)
                  _ChartPoint(
                    date: point.date,
                    value: useUsd
                        ? (usd == null
                              ? 0
                              : point.usdAmount.toMajorUnits(usd).toDouble())
                        : (currency == null
                              ? 0
                              : point.nativeAmount
                                    .toMajorUnits(currency)
                                    .toDouble()),
                  ),
              ],
              color: AppColors.navy,
              currency: useUsd ? usd : currency,
            ),
    );
  }

  String? _missingWarning(List<DateTime> dates) {
    if (dates.isEmpty) return null;
    final preview = dates.take(3).map(formatDate).join(', ');
    final suffix = dates.length > 3 ? ' and ${dates.length - 3} more' : '';
    return 'Missing daily data for $preview$suffix.';
  }

  void _selectPreset(AnalysisRangePreset preset) {
    final allHistory = _calculator.allHistoryRange;
    final today = DateTime.now();
    final todayOnly = DateTime.utc(today.year, today.month, today.day);
    final range = switch (preset) {
      AnalysisRangePreset.thirtyDays => DateTimeRange(
        start: todayOnly.subtract(const Duration(days: 29)),
        end: todayOnly,
      ),
      AnalysisRangePreset.ninetyDays => DateTimeRange(
        start: todayOnly.subtract(const Duration(days: 89)),
        end: todayOnly,
      ),
      AnalysisRangePreset.yearToDate => DateTimeRange(
        start: DateTime.utc(today.year),
        end: todayOnly,
      ),
      AnalysisRangePreset.allHistory => allHistory,
    };
    setState(() {
      _rangePreset = preset;
      _range = range;
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
  final String subtitle;
  final String? warning;
  final Widget? header;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: AppColors.mutedText),
        ),
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

class _LineChart extends StatelessWidget {
  const _LineChart({
    required this.points,
    required this.color,
    required this.currency,
  });

  final List<_ChartPoint> points;
  final Color color;
  final CurrencyDefinition? currency;

  @override
  Widget build(BuildContext context) {
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
        final chartMaxX = spanDays == 0 ? 1.0 : spanDays.toDouble();

        return SizedBox(
          height: 280,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: chartMaxX,
              minY: minimum - padding,
              maxY: maximum + padding,
              gridData: const FlGridData(show: true),
              titlesData: FlTitlesData(
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 58,
                    getTitlesWidget: (value, meta) => Text(
                      currency == null
                          ? value.toStringAsFixed(0)
                          : '${currency!.symbol}${value.toStringAsFixed(0)}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: xInterval.toDouble(),
                    reservedSize: 32,
                    getTitlesWidget: (value, meta) {
                      final dayOffset = value.round();
                      if (dayOffset < 0 || dayOffset > spanDays) {
                        return const SizedBox.shrink();
                      }
                      final date = firstDate.add(
                        Duration(days: dayOffset),
                      );
                      return Text(
                        formatDate(date).substring(5),
                        style: Theme.of(context).textTheme.labelSmall,
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (final point in points)
                      FlSpot(
                        point.date.difference(firstDate).inDays.toDouble(),
                        point.value,
                      ),
                  ],
                  color: color,
                  barWidth: 3,
                  isCurved: false,
                  dotData: FlDotData(show: points.length <= 30),
                  belowBarData: BarAreaData(
                    show: true,
                    color: color.withValues(alpha: 0.12),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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

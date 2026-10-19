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
  late AnalysisRangePreset _netWorthRangePreset;
  late DateTimeRange? _netWorthRange;
  late AnalysisRangePreset _accountRangePreset;
  late DateTimeRange? _accountRange;
  String? _selectedAccountId;
  AccountChartUnit _accountChartUnit = AccountChartUnit.native;

  @override
  void initState() {
    super.initState();
    _calculator = AnalysisCalculator(widget.data);
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
    final useUsd = accountIsUsd || _accountChartUnit == AccountChartUnit.usd;

    return _AnalysisChartSection(
      title: 'Individual Account Valuation Trend',
      subtitle: null,
      warning: series == null ? null : _missingWarning(series.missingDates),
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
              final accountDropdown = DropdownButtonFormField<String>(
                initialValue: _selectedAccountId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Account'),
                items: [
                  for (final item in widget.data.visibleAccounts)
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
  });

  final List<_ChartPoint> points;
  final Color color;
  final CurrencyDefinition? currency;

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
                  tooltipHorizontalAlignment: FLHorizontalAlignment.center,
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipColor: (_) => Colors.white,
                  tooltipBorder: const BorderSide(color: AppColors.border),
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
                              color: _amountColor(spot.y),
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
                      final date = firstDate.add(Duration(days: dayOffset));
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
          color: _amountColor(points.first.value),
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
          color: _amountColor(
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

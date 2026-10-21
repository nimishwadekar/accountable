import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../app/theme/design_tokens.dart';
import '../../data/models/models.dart';

class AnalysisChartSection extends StatelessWidget {
  const AnalysisChartSection({
    super.key,
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

class ChartPoint {
  const ChartPoint({required this.date, required this.value});

  final DateTime date;
  final double value;
}

class LineChartWidget extends StatefulWidget {
  const LineChartWidget({
    super.key,
    required this.points,
    required this.color,
    required this.currency,
    required this.axisLabel,
    this.isLiability = false,
  });

  final List<ChartPoint> points;
  final Color color;
  final CurrencyDefinition? currency;
  final String axisLabel;
  final bool isLiability;

  @override
  State<LineChartWidget> createState() => _LineChartWidgetState();
}

class _LineChartWidgetState extends State<LineChartWidget> {
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
    List<ChartPoint> points,
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

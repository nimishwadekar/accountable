import 'dart:math' as math;

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
    this.footer,
    this.cardBottomPadding = AppSpacing.md,
  });

  final String title;
  final String? subtitle;
  final String? warning;
  final Widget? header;
  final Widget? footer;
  final double cardBottomPadding;
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
            padding: EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.md,
              cardBottomPadding,
            ),
            child: child,
          ),
        ),
        if (footer != null) ...[const SizedBox(height: AppSpacing.sm), footer!],
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
  });

  final List<ChartPoint> points;
  final Color color;
  final CurrencyDefinition? currency;
  final String axisLabel;

  @override
  State<LineChartWidget> createState() => _LineChartWidgetState();
}

class _LineChartWidgetState extends State<LineChartWidget> {
  LineTouchResponse? _touchResponse;
  final ValueNotifier<double?> _selectedX = ValueNotifier(null);

  @override
  void dispose() {
    _selectedX.dispose();
    super.dispose();
  }

  static double _horizontalDistance(Offset touch, Offset spot) =>
      (touch.dx - spot.dx).abs();

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
        const chartHeight = 296.0;
        const bottomAxisHeight = 32.0;
        const labelClearance = 52.0;
        final chartMinY = minimum - padding;
        final baseMaxY = maximum + padding;
        final baseYRange = baseMaxY - chartMinY;
        final axisStyle =
            Theme.of(context).textTheme.labelSmall ?? const TextStyle();
        final selectedSpot = _touchResponse?.lineBarSpots?.first;
        final selectedIndex = selectedSpot == null
            ? points.length - 1
            : _pointIndexForX(points, firstDate, selectedSpot.x);
        final displayPoint = points[selectedIndex];
        final previousValue = selectedIndex == 0
            ? null
            : points[selectedIndex - 1].value;
        final baseAxisReservedSize = _axisReservedSize(
          minimum: chartMinY,
          maximum: baseMaxY,
          style: axisStyle,
          currency: currency,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        );
        final overlayWidth = _valueOverlayWidth(
          context,
          label: widget.axisLabel,
          point: displayPoint,
          baseline: previousValue,
          currency: currency,
        );
        final overlayLeft = baseAxisReservedSize + AppSpacing.sm;
        final overlayRight = overlayLeft + overlayWidth;
        final clashValues = [
          for (final point in points)
            if (_xPosition(
                      point.date.difference(firstDate).inDays.toDouble(),
                      chartMinX,
                      chartMaxX,
                      constraints.maxWidth,
                      baseAxisReservedSize,
                    ) >=
                    overlayLeft - AppSpacing.sm &&
                _xPosition(
                      point.date.difference(firstDate).inDays.toDouble(),
                      chartMinX,
                      chartMaxX,
                      constraints.maxWidth,
                      baseAxisReservedSize,
                    ) <=
                    overlayRight + AppSpacing.sm)
              point.value,
        ];
        var maxY = baseMaxY;
        if (clashValues.isNotEmpty) {
          final clashValue = clashValues.reduce(math.max);
          final basePixel =
              (baseMaxY - clashValue) /
              baseYRange *
              (chartHeight - bottomAxisHeight);
          if (basePixel < labelClearance) {
            final extraRange =
                (labelClearance * baseYRange -
                    (chartHeight - bottomAxisHeight) *
                        (baseMaxY - clashValue)) /
                (chartHeight - bottomAxisHeight - labelClearance);
            maxY += extraRange.clamp(0, double.infinity);
          }
        }
        final axisReservedSize = _axisReservedSize(
          minimum: chartMinY,
          maximum: maxY,
          style: axisStyle,
          currency: currency,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        );

        return SizedBox(
          width: double.infinity,
          height: 304,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                bottom: 8,
                child: LineChart(
                  LineChartData(
                    minX: chartMinX,
                    maxX: chartMaxX,
                    minY: chartMinY,
                    maxY: maxY,
                    gridData: FlGridData(
                      show: true,
                      drawHorizontalLine: false,
                      getDrawingVerticalLine: (value) => FlLine(
                        color: AppColors.border.withValues(alpha: 0.65),
                        strokeWidth: 1,
                      ),
                      verticalInterval: xInterval.toDouble(),
                      checkToShowVerticalLine: (value) {
                        final dayOffset = value.round();
                        return value >= 0 &&
                            dayOffset <= spanDays &&
                            (value - dayOffset).abs() < 0.001 &&
                            dayOffset % xInterval == 0;
                      },
                    ),
                    lineTouchData: LineTouchData(
                      touchSpotThreshold: 100000,
                      distanceCalculator: _horizontalDistance,
                      handleBuiltInTouches: false,
                      touchCallback: (event, response) {
                        if (event is FlPointerExitEvent ||
                            event is FlPanCancelEvent) {
                          _selectedX.value = null;
                          if (_touchResponse != null) {
                            setState(() => _touchResponse = null);
                          }
                          return;
                        }
                        final spots = response?.lineBarSpots;
                        if (spots == null || spots.isEmpty) {
                          if (_touchResponse != null) {
                            setState(() => _touchResponse = null);
                          }
                          return;
                        }
                        _selectedX.value = spots.first.x;
                        setState(
                          () => _touchResponse = response!.copyWith(
                            lineBarSpots: [spots.first],
                          ),
                        );
                      },
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
                            if (value <= chartMinY || value >= maxY) {
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
                    lineBarsData: _lineBars(
                      points,
                      firstDate,
                      color,
                      selectedSpot: selectedSpot,
                    ),
                  ),
                ),
              ),
              ValueListenableBuilder<double?>(
                valueListenable: _selectedX,
                builder: (context, selectedX, child) {
                  if (selectedX == null) return const SizedBox.shrink();
                  return Positioned(
                    left: _xPosition(
                      selectedX,
                      chartMinX,
                      chartMaxX,
                      constraints.maxWidth,
                      axisReservedSize,
                    ),
                    top: 0,
                    bottom: 18,
                    width: 1,
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _DashedVerticalLinePainter(color),
                      ),
                    ),
                  );
                },
              ),
              Positioned(
                top: AppSpacing.sm,
                left: axisReservedSize + AppSpacing.sm,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth - axisReservedSize - 24,
                  ),
                  child: _ValueOverlay(
                    label: widget.axisLabel,
                    point: displayPoint,
                    baseline: previousValue,
                    currency: currency,
                  ),
                ),
              ),
              if (selectedSpot != null)
                Positioned(
                  left: _xPosition(
                    selectedSpot.x,
                    chartMinX,
                    chartMaxX,
                    constraints.maxWidth,
                    axisReservedSize,
                  ),
                  bottom: 14,
                  child: FractionalTranslation(
                    translation: const Offset(-0.5, 0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(AppRadii.control),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs,
                        ),
                        child: Text(
                          _formatTooltipDate(displayPoint.date),
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  double _valueOverlayWidth(
    BuildContext context, {
    required String label,
    required ChartPoint point,
    required double? baseline,
    required CurrencyDefinition? currency,
  }) {
    final percentage = baseline == null || baseline == 0
        ? null
        : ((point.value - baseline) / baseline.abs()) * 100;
    final text =
        '$label: ${currency?.symbol ?? ''} '
        '${_formatChartValue(point.value)} '
        '(${percentage == null ? '—' : '${percentage >= 0 ? '+' : ''}${percentage.toStringAsFixed(2)}%'})';
    final style = Theme.of(context).textTheme.labelLarge ?? const TextStyle();
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    return painter.width + AppSpacing.md;
  }

  int _pointIndexForX(List<ChartPoint> points, DateTime firstDate, double x) {
    var closestIndex = 0;
    var closestDistance = double.infinity;
    for (var index = 0; index < points.length; index++) {
      final distance = (points[index].date.difference(firstDate).inDays - x)
          .abs();
      if (distance < closestDistance) {
        closestDistance = distance;
        closestIndex = index;
      }
    }
    return closestIndex;
  }

  double _xPosition(
    double x,
    double chartMinX,
    double chartMaxX,
    double chartWidth,
    double axisReservedSize,
  ) {
    final plotWidth = chartWidth - axisReservedSize;
    final fraction = (x - chartMinX) / (chartMaxX - chartMinX);
    return axisReservedSize + fraction.clamp(0.0, 1.0) * plotWidth;
  }

  String _formatTooltipDate(DateTime date) {
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
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
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
    Color fallbackColor, {
    TouchLineBarSpot? selectedSpot,
  }) {
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
          dotData: _selectedDotData(selectedSpot),
          belowBarData: BarAreaData(
            show: false,
            color: fallbackColor.withValues(alpha: 0.12),
          ),
        ),
    ];
  }

  FlDotData _selectedDotData(TouchLineBarSpot? selectedSpot) {
    return FlDotData(
      show: selectedSpot != null,
      checkToShowDot: (spot, _) =>
          selectedSpot != null &&
          spot.x == selectedSpot.x &&
          spot.y == selectedSpot.y,
      getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
        radius: 6,
        color: _pointColor(spot.y),
        strokeColor: Colors.white,
        strokeWidth: 2,
      ),
    );
  }

  Color _pointColor(double value) => widget.color;

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

class _DashedVerticalLinePainter extends CustomPainter {
  const _DashedVerticalLinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 1.5;
    const dashLength = 5.0;
    const gapLength = 5.0;
    var y = 0.0;
    while (y < size.height) {
      canvas.drawLine(
        Offset(0.5, y),
        Offset(0.5, (y + dashLength).clamp(0.0, size.height)),
        paint,
      );
      y += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedVerticalLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ValueOverlay extends StatelessWidget {
  const _ValueOverlay({
    required this.label,
    required this.point,
    required this.baseline,
    required this.currency,
  });

  final String label;
  final ChartPoint point;
  final double? baseline;
  final CurrencyDefinition? currency;

  static String _formatValue(double value) {
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

  @override
  Widget build(BuildContext context) {
    final baselineValue = baseline;
    final percentage = baselineValue == null || baselineValue == 0
        ? null
        : ((point.value - baselineValue) / baselineValue.abs()) * 100;
    final percentageLabel = percentage == null
        ? '—'
        : '${percentage >= 0 ? '+' : ''}${percentage.toStringAsFixed(2)}%';
    final percentageColor = percentage == null
        ? AppColors.mutedText
        : percentage >= 0
        ? AppColors.success
        : AppColors.danger;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.xs,
          children: [
            Text('$label:', style: Theme.of(context).textTheme.labelMedium),
            Text(
              currency == null
                  ? _formatValue(point.value)
                  : '${currency!.symbol} ${_formatValue(point.value)}',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: percentageColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '($percentageLabel)',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: percentageColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

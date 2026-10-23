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

class ChartMarker {
  const ChartMarker({required this.date, required this.label});

  final DateTime date;
  final String label;
}

class LineChartWidget extends StatefulWidget {
  const LineChartWidget({
    super.key,
    required this.points,
    required this.color,
    required this.currency,
    required this.axisLabel,
    this.isLiability = false,
    this.markers = const [],
  });

  final List<ChartPoint> points;
  final Color color;
  final CurrencyDefinition? currency;
  final String axisLabel;
  final bool isLiability;
  final List<ChartMarker> markers;

  @override
  State<LineChartWidget> createState() => _LineChartWidgetState();
}

class _LineChartWidgetState extends State<LineChartWidget> {
  final ValueNotifier<double?> _selectedX = ValueNotifier(null);

  @override
  void dispose() {
    _selectedX.dispose();
    super.dispose();
  }

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
    final lastDate = points.last.date;
    final spanDays = lastDate.difference(firstDate).inDays;
    final visibleMarkers = widget.markers.where(
      (marker) =>
          !marker.date.isBefore(firstDate) && !marker.date.isAfter(lastDate),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxLabels = (constraints.maxWidth / 88).floor().clamp(3, 8);
        final xInterval = _niceDayInterval(spanDays, maxLabels);
        final xMargin = spanDays == 0 ? 0.5 : spanDays * 0.05;
        final chartMinX = -xMargin;
        final chartMaxX = spanDays == 0 ? 0.5 : spanDays + xMargin;
        const outerChartHeight = 304.0;
        const chartBottomInset = 8.0;
        const narrowChartAspectRatio = 1.975;
        final outerHeight = constraints.maxWidth < AppBreakpoints.compact
            ? (constraints.maxWidth / narrowChartAspectRatio).clamp(
                180.0,
                outerChartHeight,
              )
            : outerChartHeight;
        final chartHeight = outerHeight - chartBottomInset;
        const bottomAxisHeight = 32.0;
        const labelClearance = 52.0;
        final chartMinY = minimum - padding;
        final baseMaxY = maximum + padding;
        final baseYRange = baseMaxY - chartMinY;
        final axisStyle =
            Theme.of(context).textTheme.labelSmall ?? const TextStyle();
        final selectedX = _selectedX.value;
        final selectedIndex = selectedX == null
            ? points.length - 1
            : _pointIndexForX(points, firstDate, selectedX);
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
        final canShowOverlay = constraints.maxWidth > baseAxisReservedSize + 24;
        final overlayWidth = _valueOverlayWidth(
          context,
          label: widget.axisLabel,
          point: displayPoint,
          baseline: previousValue,
          currency: currency,
        );
        final overlayLeft = baseAxisReservedSize + AppSpacing.sm;
        final overlayRight = overlayLeft + overlayWidth;
        final clashValues = canShowOverlay
            ? [
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
              ]
            : const <double>[];
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
          height: outerHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                bottom: chartBottomInset,
                child: CustomPaint(
                  painter: _ChartAreaGradientPainter(
                    points: points,
                    firstDate: firstDate,
                    minX: chartMinX,
                    maxX: chartMaxX,
                    minY: chartMinY,
                    maxY: maxY,
                    axisReservedSize: axisReservedSize,
                    bottomAxisHeight: bottomAxisHeight,
                    color: color,
                  ),
                ),
              ),
              Positioned.fill(
                bottom: chartBottomInset,
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
                      distanceCalculator: (touch, spot) {
                        final distance = spot.dx - touch.dx;
                        return distance >= 0 ? distance : double.infinity;
                      },
                      handleBuiltInTouches: false,
                      touchCallback: (event, response) {
                        if (event is FlPointerExitEvent ||
                            event is FlPanCancelEvent) {
                          _selectedX.value = null;
                          setState(() {});
                          return;
                        }
                        final spots = response?.lineBarSpots;
                        _selectedX.value = spots == null || spots.isEmpty
                            ? points.last.date
                                  .difference(firstDate)
                                  .inDays
                                  .toDouble()
                            : spots.first.x;
                        setState(() {});
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
                      selectedX: selectedX,
                    ),
                  ),
                ),
              ),
              for (final marker in visibleMarkers) ...[
                Positioned(
                  left: _xPosition(
                    marker.date.difference(firstDate).inDays.toDouble(),
                    chartMinX,
                    chartMaxX,
                    constraints.maxWidth,
                    axisReservedSize,
                  ),
                  top: 0,
                  bottom: chartBottomInset + bottomAxisHeight,
                  width: 1,
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: const _DashedVerticalLinePainter(),
                    ),
                  ),
                ),
                Positioned(
                  left: _xPosition(
                    marker.date.difference(firstDate).inDays.toDouble(),
                    chartMinX,
                    chartMaxX,
                    constraints.maxWidth,
                    axisReservedSize,
                  ),
                  bottom: 8,
                  child: FractionalTranslation(
                    translation: const Offset(-0.5, 0),
                    child: Text(
                      marker.label,
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: const Color(0xFF667085)),
                    ),
                  ),
                ),
              ],
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
                        painter: const _DashedVerticalLinePainter(),
                      ),
                    ),
                  );
                },
              ),
              if (canShowOverlay)
                Positioned(
                  top: AppSpacing.sm,
                  left: axisReservedSize + AppSpacing.sm,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: math.max(
                        0,
                        constraints.maxWidth - axisReservedSize - 24,
                      ),
                    ),
                    child: _ValueOverlay(
                      label: widget.axisLabel,
                      point: displayPoint,
                      baseline: previousValue,
                      currency: currency,
                      isLiability: widget.isLiability,
                    ),
                  ),
                ),
              if (selectedX != null)
                Positioned(
                  left: _xPosition(
                    selectedX,
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
        '(${percentage == null || percentage == 0 ? '0.00%' : '${percentage >= 0 ? '+' : ''}${percentage.toStringAsFixed(2)}%'})';
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
    final plotWidth = math.max(1.0, chartWidth - axisReservedSize);
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
    DateTime firstDate, {
    double? selectedX,
  }) {
    return [
      LineChartBarData(
        spots: [
          for (final point in points)
            FlSpot(
              point.date.difference(firstDate).inDays.toDouble(),
              point.value,
            ),
        ],
        color: widget.color,
        barWidth: 3,
        isCurved: false,
        dotData: _selectedDotData(selectedX),
        belowBarData: BarAreaData(show: false),
      ),
    ];
  }

  FlDotData _selectedDotData(double? selectedX) {
    return FlDotData(
      show: selectedX != null,
      checkToShowDot: (spot, _) => selectedX != null && spot.x == selectedX,
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

class _ChartAreaGradientPainter extends CustomPainter {
  const _ChartAreaGradientPainter({
    required this.points,
    required this.firstDate,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.axisReservedSize,
    required this.bottomAxisHeight,
    required this.color,
  });

  final List<ChartPoint> points;
  final DateTime firstDate;
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;
  final double axisReservedSize;
  final double bottomAxisHeight;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || maxX == minX || maxY == minY) return;

    final plotWidth = math.max(1.0, size.width - axisReservedSize);
    final plotHeight = math.max(1.0, size.height - bottomAxisHeight);

    double xFor(ChartPoint point) {
      final x = point.date.difference(firstDate).inDays.toDouble();
      return axisReservedSize + (x - minX) / (maxX - minX) * plotWidth;
    }

    double yFor(ChartPoint point) {
      return (maxY - point.value) / (maxY - minY) * plotHeight;
    }

    final areaPath = Path()..moveTo(xFor(points.first), yFor(points.first));
    for (final point in points.skip(1)) {
      areaPath.lineTo(xFor(point), yFor(point));
    }
    areaPath
      ..lineTo(xFor(points.last), plotHeight)
      ..lineTo(xFor(points.first), plotHeight)
      ..close();

    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [color.withValues(alpha: 0.20), color.withValues(alpha: 0)],
    );
    final paint = Paint()
      ..shader = gradient.createShader(
        Rect.fromLTWH(0, 0, size.width, plotHeight),
      );
    canvas
      ..save()
      ..clipPath(areaPath)
      ..drawRect(Offset.zero & size, paint)
      ..restore();
  }

  @override
  bool shouldRepaint(covariant _ChartAreaGradientPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.minX != minX ||
      oldDelegate.maxX != maxX ||
      oldDelegate.minY != minY ||
      oldDelegate.maxY != maxY ||
      oldDelegate.color != color;
}

class _DashedVerticalLinePainter extends CustomPainter {
  const _DashedVerticalLinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF667085).withValues(alpha: 0.7)
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
  bool shouldRepaint(covariant _DashedVerticalLinePainter oldDelegate) => false;
}

class _ValueOverlay extends StatelessWidget {
  const _ValueOverlay({
    required this.label,
    required this.point,
    required this.baseline,
    required this.currency,
    required this.isLiability,
  });

  final String label;
  final ChartPoint point;
  final double? baseline;
  final CurrencyDefinition? currency;
  final bool isLiability;

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
    final percentageLabel = percentage == null || percentage == 0
        ? '0.00%'
        : '${percentage >= 0 ? '+' : ''}${percentage.toStringAsFixed(2)}%';
    final percentageColor = percentage == null || percentage == 0
        ? const Color(0xFF475467)
        : (percentage >= 0) != isLiability
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

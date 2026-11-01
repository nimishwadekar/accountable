import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../app/formatters.dart';
import '../../app/pages/app_pages.dart';
import '../../app/pages/category_visuals.dart';
import '../../app/theme/design_tokens.dart';
import '../../data/data.dart';
import 'category_analysis.dart';
import 'income_allocation_analysis.dart';
import 'analysis_chart_widgets.dart';

class CategoryAnalysisSection extends StatelessWidget {
  const CategoryAnalysisSection({
    super.key,
    required this.title,
    required this.result,
    required this.usd,
    required this.data,
    this.month,
    this.onAddIncomeAllocation,
  });

  final String title;
  final CategoryAnalysisResult result;
  final CurrencyDefinition? usd;
  final AppDataSnapshot data;
  final DateTime? month;
  final VoidCallback? onAddIncomeAllocation;

  @override
  Widget build(BuildContext context) => _buildCategoryWidget(context);

  Widget _buildCategoryWidget(BuildContext context) {
    final total = result.totalPositive;
    final allocationProgressByCategory =
        month == null || result.positiveValues.isEmpty
        ? const <String, List<IncomeAllocationProgress>>{}
        : IncomeAllocationAnalyzer(data).analyzeAll(
            month: month!,
            incomeCategoryIds: {
              for (final value in result.positiveValues)
                if (value.categoryId != null) value.categoryId!,
            },
          );
    return AnalysisChartSection(
      title: title,
      subtitle: null,
      header: title == 'Income by Category' && onAddIncomeAllocation != null
          ? Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onAddIncomeAllocation,
                icon: const Icon(Icons.add),
                label: const Text('Add Income Allocation'),
              ),
            )
          : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < AppBreakpoints.compact ||
              MediaQuery.textScalerOf(context).scale(14) > 16.8;
          final compactSpacing = usesCompactVerticalSpacing(
            context,
            availableWidth: constraints.maxWidth,
          );
          final trailingWidth = (constraints.maxWidth * 0.42)
              .clamp(200.0, 280.0)
              .toDouble();
          final pieSize = math.min(248.0, constraints.maxWidth);
          final totalText = _formatCategoryAmount(total, usd);
          final totalStyle = Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700);
          final centerDiameter = pieSize * 0.4;
          final centerTotalWidth = _measureTextWidth(
            totalText,
            totalStyle,
            context,
          );
          final centerTotalSize = _measureText(
            totalText,
            totalStyle,
            context,
            maxWidth: centerDiameter,
          );
          final centerLabelSize = _measureText(
            'Total',
            Theme.of(context).textTheme.labelSmall,
            context,
            maxWidth: centerDiameter,
          );
          final showCenterAmount =
              !compact &&
              centerTotalWidth <= centerDiameter &&
              centerTotalSize.height + centerLabelSize.height + AppSpacing.xs <=
                  centerDiameter;
          return result.positiveValues.isEmpty
              ? const EmptyState(
                  message: 'No categorized values for this month.',
                )
              : Column(
                  children: [
                    SizedBox(
                      width: pieSize,
                      height: pieSize,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          PieChart(
                            PieChartData(
                              // fl_chart paints sections to
                              // centerSpaceRadius + section.radius. Keep that
                              // radius within the square chart viewport so the
                              // circle cannot cross the card edge on compact
                              // screens.
                              centerSpaceRadius: pieSize * 0.20,
                              sectionsSpace: 2,
                              sections: [
                                for (final value in result.positiveValues)
                                  PieChartSectionData(
                                    value: value.amountUsdMinorUnits.toDouble(),
                                    color: _categoryColor(value.categoryId),
                                    title: '',
                                    radius: pieSize * 0.28,
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
                              if (showCenterAmount)
                                Text(totalText, style: totalStyle),
                            ],
                          ),
                        ],
                      ),
                    ),
                    for (final value in result.positiveValues) ...[
                      _buildCategoryRow(
                        context,
                        value,
                        total,
                        compact: compact,
                        compactSpacing: compactSpacing,
                        trailingWidth: trailingWidth,
                      ),
                      if (month != null && value.categoryId != null)
                        ..._buildAllocationRows(
                          allocationProgressByCategory[value.categoryId!] ??
                              const [],
                          context,
                          compact: compact,
                          compactSpacing: compactSpacing,
                        ),
                    ],
                    const Divider(height: AppSpacing.lg),
                    _buildTotalRow(
                      context,
                      totalText,
                      style: totalStyle,
                      compact: compact,
                    ),
                    if (result.negativeAdjustment < 0)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Net reimbursement adjustment:',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                            _CompleteMoneyText(
                              text: _formatCategoryAmount(
                                result.negativeAdjustment,
                                usd,
                              ),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
        },
      ),
    );
  }

  Widget _buildCategoryRow(
    BuildContext context,
    CategoryAnalysisValue value,
    int total, {
    required bool compact,
    required bool compactSpacing,
    required double trailingWidth,
  }) {
    final name = _categoryName(value.categoryId);
    final amount = _formatCategoryAmount(value.amountUsdMinorUnits, usd);
    final percentage =
        '${(value.amountUsdMinorUnits / total * 100).toStringAsFixed(1)}%';
    final icon = Icon(
      _categoryIcon(value.categoryId),
      color: _categoryColor(value.categoryId),
    );

    if (compact) {
      final amountStyle = Theme.of(context).textTheme.titleMedium;
      final percentageStyle = Theme.of(context).textTheme.bodyMedium;
      return Padding(
        padding: EdgeInsets.symmetric(
          vertical: compactSpacing ? AppSpacing.xs / 2 : AppSpacing.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                icon,
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(name)),
              ],
            ),
            SizedBox(
              height: compactSpacing ? AppSpacing.xs / 2 : AppSpacing.xs,
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final amountWidth = _measureTextWidth(
                  amount,
                  amountStyle,
                  context,
                );
                final percentageWidth = _measureTextWidth(
                  percentage,
                  percentageStyle,
                  context,
                );
                if (amountWidth + percentageWidth + AppSpacing.sm <=
                    constraints.maxWidth) {
                  return Row(
                    children: [
                      Expanded(
                        child: _CompleteMoneyText(
                          text: amount,
                          style: amountStyle,
                          textAlign: TextAlign.right,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(percentage, style: percentageStyle),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _CompleteMoneyText(text: amount, style: amountStyle),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(percentage, style: percentageStyle),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(width: 40, child: icon),
          Expanded(child: Text(name)),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: trailingWidth,
            child: Row(
              children: [
                Expanded(
                  child: _CompleteMoneyText(
                    text: amount,
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.right,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                SizedBox(
                  width: 52,
                  child: Text(
                    percentage,
                    maxLines: 1,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(
    BuildContext context,
    String amount, {
    required TextStyle? style,
    required bool compact,
  }) {
    final labelStyle = style;
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Total:', style: labelStyle),
          const SizedBox(height: AppSpacing.xs),
          _CompleteMoneyText(text: amount, style: style),
        ],
      );
    }
    return Row(
      children: [
        Text('Total:', style: labelStyle),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _CompleteMoneyText(
            text: amount,
            style: style,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  String _categoryName(String? id) => id == null
      ? 'Uncategorized'
      : data.categoriesById[id]?.name ?? 'Uncategorized';

  IconData _categoryIcon(String? id) {
    final category = id == null ? null : data.categoriesById[id];
    return category == null ? Icons.category_outlined : categoryIcon(category);
  }

  Color _categoryColor(String? id) {
    final category = id == null ? null : data.categoriesById[id];
    return category == null ? AppColors.mutedText : categoryColor(category);
  }

  String _formatCategoryAmount(int minorUnits, CurrencyDefinition? currency) {
    if (currency == null) return '—';
    return formatMoney(
      Money(minorUnits: minorUnits, currencyId: currency.id),
      data.currenciesById,
    );
  }

  List<Widget> _buildAllocationRows(
    List<IncomeAllocationProgress> progress,
    BuildContext context, {
    required bool compact,
    required bool compactSpacing,
  }) {
    return [
      for (final item in progress)
        Padding(
          padding: EdgeInsets.only(
            top: compact ? AppSpacing.xs / 2 : AppSpacing.xs,
            bottom: compact ? AppSpacing.xs / 2 : AppSpacing.xs,
          ),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: compact
                  ? AppSpacing.sm - AppSpacing.xs / 2
                  : AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppRadii.control),
              border: Border.all(color: AppColors.border),
            ),
            child: Padding(
              padding: EdgeInsets.only(left: compact ? 0 : AppSpacing.md),
              child: compact
                  ? _buildCompactAllocation(
                      item,
                      context,
                      compactSpacing: compactSpacing,
                    )
                  : _buildWideAllocation(item, context),
            ),
          ),
        ),
    ];
  }

  Widget _buildCompactAllocation(
    IncomeAllocationProgress item,
    BuildContext context, {
    required bool compactSpacing,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          item.allocation.name,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        SizedBox(height: compactSpacing ? AppSpacing.xs : AppSpacing.sm),
        _allocationProgress(item),
        SizedBox(height: compactSpacing ? AppSpacing.xs : AppSpacing.sm),
        _allocationAmountRow(
          'Actual',
          formatMoney(item.actualAmount, data.currenciesById),
          context,
        ),
        _allocationAmountRow(
          'Expected',
          formatMoney(item.expectedAmount, data.currenciesById),
          context,
        ),
        if (item.percentage != null)
          Align(
            alignment: Alignment.centerRight,
            child: _allocationPercentage(item, context),
          ),
      ],
    );
  }

  Widget _buildWideAllocation(
    IncomeAllocationProgress item,
    BuildContext context,
  ) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.subdirectory_arrow_right,
                    size: 20,
                    color: AppColors.teal,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      item.allocation.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              _allocationProgress(item),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        SizedBox(
          width: 240,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _allocationAmountRow(
                'Actual',
                formatMoney(item.actualAmount, data.currenciesById),
                context,
              ),
              _allocationAmountRow(
                'Expected',
                formatMoney(item.expectedAmount, data.currenciesById),
                context,
              ),
              if (item.percentage != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: _allocationPercentage(item, context),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _allocationProgress(IncomeAllocationProgress item) {
    final percentage = item.percentage;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: LinearProgressIndicator(
        semanticsLabel:
            '${item.allocation.name} progress. '
            'Actual ${formatMoney(item.actualAmount, data.currenciesById)}. '
            'Expected ${formatMoney(item.expectedAmount, data.currenciesById)}.'
            '${percentage == null ? '' : ' ${percentage.toStringAsFixed(0)}%.'}',
        semanticsValue:
            '${(percentage ?? 0).clamp(0, 100).toStringAsFixed(0)}%',
        minHeight: 6,
        value: item.expectedAmount.minorUnits <= 0
            ? 0
            : (item.actualAmount.minorUnits / item.expectedAmount.minorUnits)
                  .clamp(0.0, 1.0),
        backgroundColor: AppColors.border,
        valueColor: AlwaysStoppedAnimation(
          item.actualAmount.minorUnits >= item.expectedAmount.minorUnits
              ? AppColors.success
              : AppColors.teal,
        ),
      ),
    );
  }

  Widget _allocationAmountRow(
    String label,
    String amount,
    BuildContext context,
  ) {
    final labelStyle = Theme.of(context).textTheme.bodySmall;
    final amountStyle = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(fontWeight: FontWeight.w700);
    return LayoutBuilder(
      builder: (context, constraints) {
        final labelWidth = _measureTextWidth(label, labelStyle, context);
        final amountWidth = _measureTextWidth(amount, amountStyle, context);
        if (labelWidth + amountWidth + AppSpacing.sm <= constraints.maxWidth) {
          return Row(
            children: [
              Text(label, style: labelStyle),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _CompleteMoneyText(
                  text: amount,
                  style: amountStyle,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: labelStyle),
            _CompleteMoneyText(text: amount, style: amountStyle),
          ],
        );
      },
    );
  }

  Widget _allocationPercentage(
    IncomeAllocationProgress item,
    BuildContext context,
  ) {
    final percentage = item.percentage!;
    return Text(
      '${percentage.toStringAsFixed(0)}%',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: percentage >= 100 ? AppColors.success : AppColors.mutedText,
      ),
    );
  }
}

class _CompleteMoneyText extends StatelessWidget {
  const _CompleteMoneyText({
    required this.text,
    required this.style,
    this.textAlign = TextAlign.left,
  });

  final String text;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final moneyStyle = style?.copyWith(
      fontFeatures: [
        ...?style?.fontFeatures,
        const FontFeature.tabularFigures(),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final textWidth = _measureTextWidth(text, moneyStyle, context);
        final label = Text(
          text,
          maxLines: 1,
          softWrap: false,
          textAlign: textAlign,
          style: moneyStyle,
        );
        if (textWidth <= constraints.maxWidth ||
            !constraints.maxWidth.isFinite) {
          return label;
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: label,
        );
      },
    );
  }
}

double _measureTextWidth(String text, TextStyle? style, BuildContext context) =>
    _measureText(text, style, context, maxWidth: double.infinity).width;

Size _measureText(
  String text,
  TextStyle? style,
  BuildContext context, {
  required double maxWidth,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout(maxWidth: maxWidth);
  return painter.size;
}

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
          final trailingWidth = (constraints.maxWidth * 0.42)
              .clamp(112.0, 180.0)
              .toDouble();
          final pieSize = math.min(248.0, constraints.maxWidth);
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
                        ..._buildAllocationRows(
                          allocationProgressByCategory[value.categoryId!] ??
                              const [],
                          context,
                        ),
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
    BuildContext context,
  ) {
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
                  color: AppColors.teal,
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
                          value: item.expectedAmount.minorUnits <= 0
                              ? 0
                              : (item.actualAmount.minorUnits /
                                        item.expectedAmount.minorUnits)
                                    .clamp(0.0, 1.0),
                          backgroundColor: AppColors.border,
                          valueColor: AlwaysStoppedAnimation(
                            item.actualAmount.minorUnits >=
                                    item.expectedAmount.minorUnits
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
                      '${formatMoney(item.actualAmount, data.currenciesById)} / '
                      '${formatMoney(item.expectedAmount, data.currenciesById)}',
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
              ],
            ),
          ),
        ),
    ];
  }
}

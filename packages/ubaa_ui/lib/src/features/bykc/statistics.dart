import 'package:ubaa_ui/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

bool uiIsBykcStatistics(FeatureId feature, List<FeatureDetail> details) =>
    feature == FeatureId.bykc &&
    details.where((d) => d.presentation is BykcStatisticsPresentation).length ==
        1 &&
    details.every(
      (d) =>
          d.presentation is BykcStatisticsPresentation ||
          d.presentation is BykcCategoryPresentation,
    );

class BykcStatisticsContent extends StatelessWidget {
  const BykcStatisticsContent({required this.total, required this.details});
  final BykcStatisticsPresentation total;
  final List<FeatureDetail> details;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = details
        .map((d) => d.presentation)
        .whereType<BykcCategoryPresentation>();
    // 大类都相同（通常都是“博雅课程”）时不再逐行重复。
    final mixedParents =
        categories.map((c) => c.categoryName).toSet().length > 1;
    return ListView(
      padding: EdgeInsets.all(
        UbaaTheme.pagePadding(MediaQuery.sizeOf(context).width),
      ),
      children: [
        // 总次数与达标进度压成一行，表格才是主体。
        Card(
          margin: EdgeInsets.zero,
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '总体净有效次数',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  total.totalValidCount?.toString() ?? '未提供',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const Spacer(),
                if (categories.where((c) => c.qualified != null).toList()
                    case final known when known.isNotEmpty)
                  Text(
                    '达标 ${known.where((c) => c.qualified!).length}/${known.length} 类',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                color: theme.colorScheme.surfaceContainerHighest,
                padding: const EdgeInsets.all(12),
                child: const Row(
                  children: [
                    Expanded(flex: 3, child: Text('课程小类')),
                    Expanded(
                      flex: 2,
                      child: Text('通过/指标', textAlign: TextAlign.center),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('达标情况', textAlign: TextAlign.end),
                    ),
                  ],
                ),
              ),
              if (categories.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('没有匹配的分类统计'),
                ),
              for (final category in categories) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              category.subCategoryName ?? '未提供小类',
                              style: theme.textTheme.bodyMedium,
                            ),
                            if (category.categoryName != null && mixedParents)
                              Text(
                                category.categoryName!,
                                style: theme.textTheme.labelSmall,
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          '${category.passedCount ?? '—'} / ${category.requiredCount ?? '—'}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          category.qualified == null
                              ? '未知'
                              : category.qualified!
                              ? '达标'
                              : '未达标',
                          textAlign: TextAlign.end,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: category.qualified == null
                                ? theme.colorScheme.onSurfaceVariant
                                : category.qualified!
                                ? theme.colorScheme.primary
                                : theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

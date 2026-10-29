import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../academic/card.dart' show uiShowAcademicDetails;
import '../../shared/loading.dart' show LoadingGlyph;
import '../../shared/text.dart' show uiNonBlank;

String _gradeNumber(double? value) {
  if (value == null || !value.isFinite) return '--';
  final text = value.toStringAsFixed(2);
  return text.contains('.') && !text.contains('e')
      ? text.replaceFirst(RegExp(r'\.?0+$'), '')
      : text;
}

/// 成绩汇总：主数字为所选学期，全部学期统计压成底部一行。
class GradeSummaryCard extends StatelessWidget {
  const GradeSummaryCard({
    required this.title,
    this.statistics,
    this.showCourseAndCredits = false,
    this.loading = false,
    this.notice,
    this.onRetry,
    this.overallTitle,
    this.overall,
    this.overallLoading = false,
  });
  final String title;
  final GradeStatistics? statistics;
  final bool showCourseAndCredits, loading;

  /// 全部学期统计的说明与重试；仅在提供 [overallTitle] 或单独展示时使用。
  final String? notice;
  final VoidCallback? onRetry;
  final String? overallTitle;
  final GradeStatistics? overall;
  final bool overallLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onPrimaryContainer.withValues(alpha: .72);
    Widget metric(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        ],
      ),
    );
    final stats = statistics;
    final counts = [
      if (showCourseAndCredits && stats != null) '${stats.courseCount} 门',
      if (showCourseAndCredits && (stats?.totalCredits ?? 0) > 0)
        '${_gradeNumber(stats?.totalCredits)} 学分',
    ];
    String brief(GradeStatistics value) => [
      'GPA ${value.gpa?.toStringAsFixed(2) ?? '--'}',
      '加权 ${_gradeNumber(value.weightedAverage)}',
      '算数 ${_gradeNumber(value.arithmeticAverage)}',
    ].join(' · ');
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (counts.isNotEmpty)
                  Text(
                    counts.join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (loading && stats == null)
              const SizedBox(height: 48, child: Center(child: LoadingGlyph()))
            else
              Row(
                children: [
                  metric('GPA', stats?.gpa?.toStringAsFixed(2) ?? '--'),
                  metric('加权平均分', _gradeNumber(stats?.weightedAverage)),
                  metric('算数平均分', _gradeNumber(stats?.arithmeticAverage)),
                ],
              ),
            if (overallTitle != null) ...[
              const SizedBox(height: 12),
              Divider(height: 1, color: muted.withValues(alpha: .2)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    overallTitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: muted,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: overallLoading && overall == null
                        ? const Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox.square(
                              dimension: 16,
                              child: LoadingGlyph(),
                            ),
                          )
                        : Text(
                            overall == null ? '暂不可用' : brief(overall!),
                            style: theme.textTheme.bodySmall,
                          ),
                  ),
                ],
              ),
            ],
            if (notice != null) ...[
              const SizedBox(height: 6),
              Text(
                notice!,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('重试统计')),
          ],
        ),
      ),
    );
  }
}

/// 不及格的分数标红；等级制按常见文字判断。
bool _gradeFailed(String score) {
  final number = double.tryParse(score);
  if (number != null) return number < 60;
  return const {'不及格', '不合格', '不通过', 'F'}.contains(score);
}

/// 一门课两行：课程名与分数同行，学分、属性、成绩类型合为一行小字。
class GradeCard extends StatelessWidget {
  const GradeCard({required this.detail});
  final FeatureDetail detail;
  @override
  Widget build(BuildContext context) {
    final grade = detail.presentation! as GradePresentation;
    final theme = Theme.of(context);
    final score = uiNonBlank(grade.score);
    final meta = [
      if (grade.credit != null) '${_gradeNumber(grade.credit)} 学分',
      ?uiNonBlank(grade.courseType),
      ?uiNonBlank(grade.scoreType),
    ].join(' · ');
    return Card.outlined(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => uiShowAcademicDetails(context, detail),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      detail.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: Text(
                  score ?? '待出',
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      (score == null
                              ? theme.textTheme.titleSmall
                              : theme.textTheme.titleLarge)
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: score == null
                                ? theme.colorScheme.onSurfaceVariant
                                : _gradeFailed(score)
                                ? theme.colorScheme.error
                                : theme.colorScheme.primary,
                          ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

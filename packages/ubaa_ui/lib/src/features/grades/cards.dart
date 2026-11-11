import 'package:flutter/material.dart';
import '../../theme.dart' show UbaaTheme;
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../shared/loading.dart' show UiReportBusy;
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
    // 浅蓝底上的说明文字用次要文字色，对比度高于同色系浅蓝。
    final muted = theme.colorScheme.onSurfaceVariant;
    Widget metric(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        ],
      ),
    );
    final stats = statistics;
    bool blank(double? value) => value == null || !value.isFinite;
    final noScores =
        stats != null &&
        !loading &&
        blank(stats.gpa) &&
        blank(stats.weightedAverage) &&
        blank(stats.arithmeticAverage);
    final counts = [
      if (showCourseAndCredits && stats != null) '${stats.courseCount} 门',
      if (showCourseAndCredits && (stats?.totalCredits ?? 0) > 0)
        '${_gradeNumber(stats?.totalCredits)} 学分',
    ];
    String brief(GradeStatistics value) => [
      'GPA ${value.gpa?.toStringAsFixed(2) ?? '--'}',
      '加权 ${_gradeNumber(value.weightedAverage)}',
      '算术 ${_gradeNumber(value.arithmeticAverage)}',
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
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (counts.isNotEmpty || noScores)
                  Text(
                    [...counts, if (noScores) '成绩待出'].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
              ],
            ),
            // 本学期还没有出分时不占三个“--”的位置，只保留标题行和全部学期统计。
            if (!noScores) ...[
              const SizedBox(height: 8),
              // 统计未到时先显示占位值，读取进度交给标题栏。
              UiReportBusy(
                busy: loading && stats == null,
                child: Row(
                  children: [
                    metric('GPA', stats?.gpa?.toStringAsFixed(2) ?? '--'),
                    metric('加权平均分', _gradeNumber(stats?.weightedAverage)),
                    metric('算术平均分', _gradeNumber(stats?.arithmeticAverage)),
                  ],
                ),
              ),
            ] else if (overallTitle == null) ...[
              const SizedBox(height: 4),
              Text(
                '成绩尚未公布',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
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
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: overallLoading && overall == null
                        ? UiReportBusy(
                            busy: true,
                            child: Text('—', style: theme.textTheme.bodySmall),
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
              TextButton(onPressed: onRetry, child: const Text('重试')),
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
        borderRadius: BorderRadius.circular(UbaaTheme.cardRadius),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      // 课程名、分数、绩点和学分已全部在卡片上，不再弹详情。
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
                      fontWeight: FontWeight.w500,
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
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: score ?? '待出'),
                    if (score != null && uiNonBlank(grade.gradePoint) != null)
                      TextSpan(
                        text: '  ${grade.gradePoint!.trim()}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                  ],
                ),
                textAlign: TextAlign.right,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    (score == null
                            ? theme.textTheme.titleSmall
                            : theme.textTheme.titleLarge)
                        ?.copyWith(
                          fontWeight: FontWeight.w500,
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
    );
  }
}

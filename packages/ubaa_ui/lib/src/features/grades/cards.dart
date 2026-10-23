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

class GradeSummaryCard extends StatelessWidget {
  const GradeSummaryCard({
    required this.title,
    this.statistics,
    this.showCourseAndCredits = false,
    this.loading = false,
    this.notice,
    this.onRetry,
  });
  final String title;
  final GradeStatistics? statistics;
  final bool showCourseAndCredits, loading;
  final String? notice;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(List<(String, String)> values) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < values.length; i++) ...[
          if (i > 0) const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  values[i].$2,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(values[i].$1, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ],
    );
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (showCourseAndCredits) ...[
              row([
                ('课程数', statistics?.courseCount.toString() ?? '--'),
                (
                  '总学分',
                  (statistics?.totalCredits ?? 0) > 0
                      ? _gradeNumber(statistics?.totalCredits)
                      : '--',
                ),
              ]),
              const SizedBox(height: 8),
            ],
            if (loading && statistics == null)
              const SizedBox(height: 64, child: Center(child: LoadingGlyph()))
            else
              row([
                ('GPA', statistics?.gpa?.toStringAsFixed(2) ?? '--'),
                ('加权平均分', _gradeNumber(statistics?.weightedAverage)),
                ('算数平均分', _gradeNumber(statistics?.arithmeticAverage)),
              ]),
            if (notice != null) ...[const SizedBox(height: 8), Text(notice!)],
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('重试统计')),
          ],
        ),
      ),
    );
  }
}

class GradeCard extends StatelessWidget {
  const GradeCard({required this.detail});
  final FeatureDetail detail;
  @override
  Widget build(BuildContext context) {
    final grade = detail.presentation! as GradePresentation;
    final theme = Theme.of(context);
    final rows = <(String, String)>[
      if (uiNonBlank(grade.courseCode) case final code?) ('课程号', code),
      if (grade.credit != null) ('学分', _gradeNumber(grade.credit)),
      if (uiNonBlank(grade.courseType) case final value?) ('课程属性', value),
      if (uiNonBlank(grade.scoreType) case final value?) ('成绩类型', value),
    ];
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
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.book, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      detail.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 130),
                    child: Card(
                      margin: EdgeInsets.zero,
                      color: theme.colorScheme.secondaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.grade,
                              size: 16,
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                uiNonBlank(grade.score) ?? '--',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (rows.isNotEmpty) const SizedBox(height: 10),
              for (final (label, value) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (label == '成绩类型') ...[
                        Icon(
                          Icons.person,
                          size: 16,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        '$label：',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Expanded(child: Text(value)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

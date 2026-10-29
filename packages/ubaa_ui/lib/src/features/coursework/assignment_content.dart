import 'package:ubaa_ui/src/theme.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../shared/text.dart' show uiNonBlank;
import '../../shared/when.dart'
    show uiCampusNow, uiDeadlineHint, uiParseCampusTime, uiShortDateTime;

bool uiSupportsAssignmentContent(
  FeatureId feature,
  List<FeatureDetail> details,
) => details.every(
  (detail) => switch (feature) {
    FeatureId.spoc => detail.presentation is SpocAssignmentPresentation,
    FeatureId.judge => detail.presentation is JudgeAssignmentPresentation,
    _ => false,
  },
);

List<String> uiAssignmentSearchValues(FeaturePresentation? presentation) =>
    switch (presentation) {
      SpocAssignmentPresentation p => [
        p.courseName,
        p.courseId,
        p.assignmentId,
        p.statusText,
        p.contentPlainText ?? '',
      ],
      JudgeAssignmentPresentation p => [
        p.courseName,
        p.courseId,
        p.assignmentId,
        p.statusText,
        p.contentPlainText ?? '',
        for (final problem in p.problems) ...[
          problem.name,
          problem.statusText,
          problem.score ?? '',
          problem.maxScore ?? '',
        ],
      ],
      _ => [],
    };

class AssignmentContent extends StatelessWidget {
  const AssignmentContent({required this.details, this.onNavigate});
  final List<FeatureDetail> details;
  final Future<void> Function(FeatureReadNavigation)? onNavigate;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final summary = details.every(
        (detail) => switch (detail.presentation) {
          SpocAssignmentPresentation p => !p.isDetail,
          JudgeAssignmentPresentation p => !p.isDetail,
          _ => false,
        },
      );
      final groups = <String, List<FeatureDetail>>{};
      if (summary) {
        for (final detail in details) {
          final key = switch (detail.presentation) {
            SpocAssignmentPresentation p => p.courseName,
            JudgeAssignmentPresentation p => p.courseName,
            _ => '',
          };
          groups.putIfAbsent(key, () => []).add(detail);
        }
      } else {
        // 批量详情保持调用者顺序，不按课程重新排列。
        groups[''] = details;
      }
      return ListView(
        padding: EdgeInsets.all(
          UbaaTheme.pagePadding(MediaQuery.sizeOf(context).width),
        ),
        children: [
          for (final entry in groups.entries) ...[
            if (summary)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  uiNonBlank(entry.key) ?? '课程名称未提供',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final detail in entry.value)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AssignmentCard(
                  detail: detail,
                  wide: constraints.maxWidth >= 740,
                  onNavigate: onNavigate,
                ),
              ),
          ],
        ],
      );
    },
  );
}

class AssignmentCard extends StatelessWidget {
  const AssignmentCard({
    required this.detail,
    required this.wide,
    this.onNavigate,
  });
  final FeatureDetail detail;
  final bool wide;
  final Future<void> Function(FeatureReadNavigation)? onNavigate;

  @override
  Widget build(BuildContext context) {
    final p = detail.presentation;
    final (status, due) = switch (p) {
      SpocAssignmentPresentation p => (p.statusText, p.dueTime),
      JudgeAssignmentPresentation p => (p.statusText, p.dueTime),
      _ => ('', null),
    };
    final summary = switch (p) {
      SpocAssignmentPresentation p => !p.isDetail,
      JudgeAssignmentPresentation p => !p.isDetail,
      _ => false,
    };
    if (!summary) return _AssignmentDetail(detail: detail, wide: wide);
    final target = detail.readNavigation;
    final canOpen = target != null && onNavigate != null;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = switch (p) {
      SpocAssignmentPresentation p => p.status,
      JudgeAssignmentPresentation p => p.status,
      _ => AssignmentSubmissionStatus.unknown,
    };
    final label = switch (state) {
      AssignmentSubmissionStatus.submitted => '已提交',
      AssignmentSubmissionStatus.partial => '部分提交',
      AssignmentSubmissionStatus.unsubmitted => '未提交',
      AssignmentSubmissionStatus.unknown => uiNonBlank(status),
    };
    final (tagFg, tagBg) = switch (state) {
      AssignmentSubmissionStatus.submitted => (
        scheme.onPrimaryContainer,
        scheme.primaryContainer,
      ),
      AssignmentSubmissionStatus.partial => (
        scheme.onTertiaryContainer,
        scheme.tertiaryContainer,
      ),
      AssignmentSubmissionStatus.unsubmitted => (
        scheme.onErrorContainer,
        scheme.errorContainer,
      ),
      AssignmentSubmissionStatus.unknown => (
        scheme.onSurfaceVariant,
        scheme.surfaceContainerHighest,
      ),
    };
    final deadline = uiParseCampusTime(due);
    final hint = deadline == null ? null : uiDeadlineHint(deadline);
    final urgent =
        deadline != null &&
        state != AssignmentSubmissionStatus.submitted &&
        deadline.isAfter(uiCampusNow()) &&
        deadline.difference(uiCampusNow()) <= const Duration(days: 3);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final meta = switch (p) {
      SpocAssignmentPresentation p => [
        if (uiNonBlank(p.teacherName) case final t?)
          t.replaceAll(RegExp(r'\s*[,，]\s*'), '、'),
        if (uiNonBlank(p.score) case final s?) '分值 $s',
      ],
      JudgeAssignmentPresentation p => [
        if (p.totalProblems > 0) '已交 ${p.submittedCount}/${p.totalProblems} 题',
        if (uiNonBlank(p.myScore) case final s?)
          '得分 $s${uiNonBlank(p.maxScore) == null ? '' : '/${p.maxScore}'}'
        else if (uiNonBlank(p.maxScore) case final m?
            when (double.tryParse(m) ?? 1) > 0)
          '满分 $m',
      ],
      _ => const <String>[],
    };
    return Card.outlined(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: canOpen ? () => onNavigate!(target) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      detail.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (label != null) ...[
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: tagBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: tagFg,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: uiNonBlank(due) == null
                          ? '截止时间未提供'
                          : '截止 ${uiShortDateTime(due!)}',
                    ),
                    if (hint != null)
                      TextSpan(
                        text: ' · $hint',
                        style: urgent
                            ? TextStyle(
                                color: scheme.error,
                                fontWeight: FontWeight.w600,
                              )
                            : null,
                      ),
                  ],
                ),
                style: muted,
              ),
              if (meta.isNotEmpty)
                Text(
                  meta.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: muted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssignmentDetail extends StatelessWidget {
  const _AssignmentDetail({required this.detail, required this.wide});
  final FeatureDetail detail;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final p = detail.presentation;
    final (course, status, start, due) = switch (p) {
      SpocAssignmentPresentation p => (
        p.courseName,
        p.statusText,
        p.startTime,
        p.dueTime,
      ),
      JudgeAssignmentPresentation p => (
        p.courseName,
        p.statusText,
        p.startTime,
        p.dueTime,
      ),
      _ => ('', '', null, null),
    };
    Widget section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              DefaultTextStyle.merge(
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(height: 1.6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: EdgeInsets.zero,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  uiNonBlank(course) ?? '课程名称未提供',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (p is SpocAssignmentPresentation &&
                    uiNonBlank(p.teacherName) != null)
                  _assignmentLine(context, '教师：${p.teacherName}'),
              ],
            ),
          ),
        ),
        section('提交信息', [
          Text('状态：${uiNonBlank(status) ?? '未知'}'),
          if (uiNonBlank(start) case final s?)
            Text('开始时间：${uiShortDateTime(s)}'),
          Text(
            '截止时间：${uiNonBlank(due) == null ? '未知' : uiShortDateTime(due!)}',
          ),
          if (p is SpocAssignmentPresentation) ...[
            if (uiNonBlank(p.score) case final score?) Text('分值：$score'),
            if (uiNonBlank(p.submittedAt) case final time?)
              Text('提交时间：${uiShortDateTime(time)}'),
          ],
          if (p is JudgeAssignmentPresentation) ...[
            if (p.totalProblems > 0)
              Text('进度：${p.submittedCount}/${p.totalProblems}'),
            if (uiNonBlank(p.maxScore) case final score?)
              Text('分数：${uiNonBlank(p.myScore) ?? '无'} / $score'),
          ],
        ]),
        if (p is SpocAssignmentPresentation)
          section('作业内容', [
            SelectableText(
              uiNonBlank(p.contentPlainText) ?? '暂无作业说明',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.65),
            ),
          ]),
        if (p is JudgeAssignmentPresentation)
          section('题目明细', [
            if (p.problems.isEmpty)
              const Text('暂无题目明细')
            else
              _JudgeProblems(problems: p.problems, wide: wide),
          ]),
      ],
    );
  }
}

Widget _assignmentLine(BuildContext context, String text) => Text(
  text,
  style: Theme.of(context).textTheme.bodySmall?.copyWith(
    fontSize: 13,
    height: 1.6,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  ),
);

class _JudgeProblems extends StatelessWidget {
  const _JudgeProblems({required this.problems, required this.wide});
  final List<JudgeProblemPresentation> problems;
  final bool wide;
  @override
  Widget build(BuildContext context) => wide
      ? LayoutBuilder(
          builder: (context, constraints) => DataTable(
            dataTextStyle: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.5),
            headingTextStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            columnSpacing: 16,
            horizontalMargin: 0,
            dataRowMinHeight: 56,
            dataRowMaxHeight: double.infinity,
            columns: const [
              DataColumn(label: Text('题目')),
              DataColumn(label: Text('状态')),
              DataColumn(label: Text('得分 / 满分')),
            ],
            rows: [
              for (final problem in problems)
                DataRow(
                  cells: [
                    DataCell(
                      SizedBox(
                        width: constraints.maxWidth * .42,
                        child: Text(problem.name),
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: constraints.maxWidth * .22,
                        child: Text(problem.statusText),
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: constraints.maxWidth * .22,
                        child: Text(
                          '${uiNonBlank(problem.score) ?? '未提供'} / ${uiNonBlank(problem.maxScore) ?? '未提供'}',
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        )
      : Column(
          children: [
            for (final problem in problems)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      problem.name,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _assignmentLine(context, problem.statusText),
                    _assignmentLine(
                      context,
                      '得分 ${uiNonBlank(problem.score) ?? '未提供'} / 满分 ${uiNonBlank(problem.maxScore) ?? '未提供'}',
                    ),
                  ],
                ),
              ),
          ],
        );
}

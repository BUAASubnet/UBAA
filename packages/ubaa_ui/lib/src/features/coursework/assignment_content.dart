import '../../shared/academic_fields.dart' show AcademicMore;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../shared/text.dart' show uiNonBlank;

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
  const AssignmentContent({
    required this.details,
    required this.selection,
    this.onNavigate,
  });
  final List<FeatureDetail> details;
  final Widget? Function(FeatureDetail) selection;
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
      final groups = <(String, String), List<FeatureDetail>>{};
      if (summary) {
        for (final detail in details) {
          final key = switch (detail.presentation) {
            SpocAssignmentPresentation p => (p.courseId, p.courseName),
            JudgeAssignmentPresentation p => (p.courseId, p.courseName),
            _ => ('', ''),
          };
          groups.putIfAbsent(key, () => []).add(detail);
        }
      } else {
        // 批量详情保持调用者顺序，不按课程重新排列。
        groups[('', '')] = details;
      }
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final entry in groups.entries) ...[
            if (summary)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  uiNonBlank(entry.key.$2) ?? '课程名称未提供',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            for (final detail in entry.value)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AssignmentCard(
                  detail: detail,
                  wide: constraints.maxWidth >= 740,
                  selection: selection(detail),
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
    this.selection,
    this.onNavigate,
  });
  final FeatureDetail detail;
  final bool wide;
  final Widget? selection;
  final Future<void> Function(FeatureReadNavigation)? onNavigate;

  @override
  Widget build(BuildContext context) {
    final p = detail.presentation;
    final (course, status, due, body) = switch (p) {
      SpocAssignmentPresentation p => (
        p.courseName,
        p.statusText,
        p.dueTime,
        p.contentPlainText,
      ),
      JudgeAssignmentPresentation p => (
        p.courseName,
        p.statusText,
        p.dueTime,
        p.contentPlainText,
      ),
      _ => ('', '', null, null),
    };
    final summary = switch (p) {
      SpocAssignmentPresentation p => !p.isDetail,
      JudgeAssignmentPresentation p => !p.isDetail,
      _ => false,
    };
    final target = detail.readNavigation;
    final canOpen = target != null && onNavigate != null;
    final card = Card(
      margin: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: InkWell(
        onTap: canOpen ? () => onNavigate!(target) : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      detail.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 132),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        uiNonBlank(status) ?? '提交状态未知',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                  ),
                ],
              ),
              if (!summary) ...[
                const SizedBox(height: 4),
                Text(uiNonBlank(course) ?? '课程名称未提供'),
              ],
              const SizedBox(height: 8),
              if (p is SpocAssignmentPresentation) ...[
                if (uiNonBlank(p.teacherName) case final teacher?)
                  _assignmentLine(context, '教师：$teacher'),
                if (uiNonBlank(p.startTime) case final start?)
                  _assignmentLine(context, '开始：$start'),
                _assignmentLine(context, '截止：${uiNonBlank(due) ?? '未提供'}'),
                if (uiNonBlank(p.score) case final score?)
                  _assignmentLine(context, '分值：$score'),
                if (!summary && uiNonBlank(p.submittedAt) != null)
                  _assignmentLine(context, '提交时间：${p.submittedAt}'),
              ],
              if (p is JudgeAssignmentPresentation) ...[
                if (uiNonBlank(p.startTime) case final start?)
                  _assignmentLine(context, '开始：$start'),
                _assignmentLine(context, '截止：${uiNonBlank(due) ?? '未提供'}'),
                _assignmentLine(
                  context,
                  '已提交 ${p.submittedCount} / ${p.totalProblems} 题',
                ),
                if (uiNonBlank(p.myScore) case final score?)
                  _assignmentLine(context, '我的得分：$score'),
                if (uiNonBlank(p.maxScore) case final score?)
                  _assignmentLine(context, '满分：$score'),
              ],
              if (uiNonBlank(body) case final text?) ...[
                const SizedBox(height: 16),
                Text('作业内容', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SelectableText(text),
              ],
              if (p is JudgeAssignmentPresentation && p.isDetail) ...[
                const SizedBox(height: 16),
                Text('题目明细', style: Theme.of(context).textTheme.titleSmall),
                if (p.problems.isEmpty)
                  const Text('暂无题目明细')
                else
                  _JudgeProblems(problems: p.problems, wide: wide),
              ],
              if (!summary || !canOpen)
                AcademicMore(
                  fields: [
                    for (final field in detail.fields)
                      (field.label, field.value),
                  ],
                ),
              if (selection case final child?) child,
            ],
          ),
        ),
      ),
    );
    return canOpen ? Tooltip(message: '查看作业详情', child: card) : card;
  }
}

Widget _assignmentLine(BuildContext context, String text) => Text(
  text,
  style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(problem.statusText),
                    Text(
                      '得分 ${uiNonBlank(problem.score) ?? '未提供'} / 满分 ${uiNonBlank(problem.maxScore) ?? '未提供'}',
                    ),
                  ],
                ),
              ),
          ],
        );
}

part of '../../widgets.dart';

bool _supportsAssignmentContent(
  FeatureId feature,
  List<FeatureDetail> details,
) => details.every(
  (detail) => switch (feature) {
    FeatureId.spoc => detail.presentation is SpocAssignmentPresentation,
    FeatureId.judge => detail.presentation is JudgeAssignmentPresentation,
    _ => false,
  },
);

List<String> _assignmentSearchValues(FeaturePresentation? presentation) =>
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

class _AssignmentContent extends StatelessWidget {
  const _AssignmentContent({
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
                  _nonBlank(entry.key.$2) ?? '课程名称未提供',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            for (final detail in entry.value)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _AssignmentCard(
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

class _AssignmentCard extends StatelessWidget {
  const _AssignmentCard({
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
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(detail.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(_nonBlank(course) ?? '课程名称未提供'),
            const SizedBox(height: 8),
            Chip(label: Text(_nonBlank(status) ?? '提交状态未知')),
            _AcademicInfo(
              icon: Icons.event_outlined,
              text: '截止时间：${_nonBlank(due) ?? '未提供'}',
            ),
            if (p is SpocAssignmentPresentation) ...[
              if (_nonBlank(p.teacherName) case final teacher?)
                _AcademicInfo(icon: Icons.person_outline, text: teacher),
              if (_nonBlank(p.score) case final score?)
                _DetailField(label: '成绩', value: score),
              if (_nonBlank(p.submittedAt) case final time?)
                _DetailField(label: '提交时间', value: time),
            ],
            if (p is JudgeAssignmentPresentation) ...[
              Text('已提交 ${p.submittedCount} / ${p.totalProblems} 题'),
              if (_nonBlank(p.myScore) case final score?)
                _DetailField(label: '我的得分', value: score),
              if (_nonBlank(p.maxScore) case final score?)
                _DetailField(label: '满分', value: score),
            ],
            if (_nonBlank(body) case final text?) ...[
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
            _AcademicMore(
              fields: [
                for (final field in detail.fields) (field.label, field.value),
              ],
            ),
            if (selection case final child?) child,
            if (detail.readNavigation case final navigation?
                when onNavigate != null)
              FilledButton.tonalIcon(
                onPressed: () => onNavigate!(navigation),
                icon: const Icon(Icons.arrow_forward),
                label: const Text('查看作业详情'),
              ),
          ],
        ),
      ),
    );
  }
}

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
                          '${_nonBlank(problem.score) ?? '未提供'} / ${_nonBlank(problem.maxScore) ?? '未提供'}',
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
                      '得分 ${_nonBlank(problem.score) ?? '未提供'} / 满分 ${_nonBlank(problem.maxScore) ?? '未提供'}',
                    ),
                  ],
                ),
              ),
          ],
        );
}

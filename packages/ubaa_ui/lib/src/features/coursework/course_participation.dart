part of '../../widgets.dart';

bool _supportsParticipationContent(
  FeatureId feature,
  List<FeatureDetail> details,
) => details.every(
  (detail) => switch (feature) {
    FeatureId.signin => detail.presentation is SigninPresentation,
    FeatureId.evaluation => detail.presentation is EvaluationCoursePresentation,
    _ => false,
  },
);

class _CourseParticipationContent extends StatelessWidget {
  const _CourseParticipationContent({
    required this.feature,
    required this.details,
    required this.actions,
  });
  final FeatureId feature;
  final List<FeatureDetail> details;
  final List<Widget> Function(BuildContext, FeatureDetail) actions;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (feature == FeatureId.evaluation && constraints.maxWidth >= 740)
          _EvaluationTable(details: details, actions: actions)
        else
          for (final detail in details)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      detail.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (detail.presentation case SigninPresentation p) ...[
                      _AcademicInfo(
                        icon: Icons.schedule,
                        text:
                            _timeRange(p.classBeginTime, p.classEndTime) ??
                            '时间未提供',
                      ),
                      Chip(
                        label: Text(switch (p.signStatus) {
                          0 => '未签到',
                          1 => '已签到',
                          _ => '签到状态未知',
                        }),
                      ),
                      if (p.signStatus != null &&
                          p.signStatus != 0 &&
                          p.signStatus != 1)
                        Text('原始状态：${p.signStatus}'),
                      if (detail.action<SigninPerformAction>()
                          case final action?
                          when (action.eligibility ==
                                      ActionEligibility.denied &&
                                  p.signStatus != 1) ||
                              (action.eligibility ==
                                      ActionEligibility.allowed &&
                                  p.signStatus != 0))
                        const Text('签到状态与操作资格信息不一致；操作资格由服务端判定。'),
                    ],
                    if (detail.presentation
                        case EvaluationCoursePresentation p) ...[
                      const SizedBox(height: 4),
                      Text(_nonBlank(detail.subtitle) ?? '教师未提供'),
                      Chip(label: Text(p.isEvaluated ? '已评' : '待评')),
                    ],
                    ...actions(context, detail),
                    _AcademicMore(
                      fields: [
                        for (final field in detail.fields)
                          (field.label, field.value),
                      ],
                    ),
                  ],
                ),
              ),
            ),
      ],
    ),
  );
}

class _EvaluationTable extends StatelessWidget {
  const _EvaluationTable({required this.details, required this.actions});
  final List<FeatureDetail> details;
  final List<Widget> Function(BuildContext, FeatureDetail) actions;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final available = constraints.maxWidth - 72;
      final widths = [
        available * .28,
        available * .17,
        available * .12,
        available * .43,
      ];
      Widget cell(int index, Widget child) => SizedBox(
        width: widths[index],
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: child,
        ),
      );
      return Card(
        margin: EdgeInsets.zero,
        child: DataTable(
          horizontalMargin: 12,
          columnSpacing: 16,
          dataRowMinHeight: 64,
          dataRowMaxHeight: double.infinity,
          columns: const [
            DataColumn(label: Text('课程')),
            DataColumn(label: Text('教师')),
            DataColumn(label: Text('状态')),
            DataColumn(label: Text('操作')),
          ],
          rows: [
            for (final detail in details)
              DataRow(
                cells: [
                  DataCell(
                    cell(
                      0,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            detail.title,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          _AcademicMore(
                            fields: [
                              for (final field in detail.fields)
                                (field.label, field.value),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  DataCell(
                    cell(1, Text(_nonBlank(detail.subtitle) ?? '教师未提供')),
                  ),
                  DataCell(
                    cell(
                      2,
                      Text(
                        (detail.presentation as EvaluationCoursePresentation)
                                .isEvaluated
                            ? '已评'
                            : '待评',
                      ),
                    ),
                  ),
                  DataCell(
                    cell(
                      3,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: actions(context, detail),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      );
    },
  );
}

extension _ParticipationActions on _FeatureDetailListState {
  List<Widget> _participationActions(
    BuildContext context,
    FeatureDetail detail,
    StateSetter setState,
  ) {
    if (widget.feature == FeatureId.signin) {
      final action = detail.action<SigninPerformAction>();
      if (action == null || action.scheduleId.trim().isEmpty)
        return [const Text('未提供签到目标，请刷新课程后重试。')];
      final p = detail.presentation as SigninPresentation;
      return _signinWriteFields(
        context,
        action,
        action.eligibility == ActionEligibility.allowed &&
            action.scheduleId.trim().isNotEmpty,
        deniedMessage: p.signStatus == 1
            ? '该课程已签到，不能重复提交。'
            : '当前课程不允许签到，请刷新确认。',
      );
    }
    final target = _evaluationSubmitTarget(detail);
    return [
      ..._evaluationSelectionFields(setState, target),
      ..._evaluationSubmitFields(target),
      if (target == null)
        Text(
          (detail.presentation as EvaluationCoursePresentation).isEvaluated
              ? '已完成评教，无需重复提交。'
              : detail.action<EvaluationSubmitAction>()?.eligibility ==
                    ActionEligibility.denied
              ? '当前课程不允许提交评教。'
              : '当前评教资格无法确认，请刷新后重试。',
        ),
    ];
  }
}

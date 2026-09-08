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
    required this.evaluationRow,
    this.onSignin,
  });
  final FeatureId feature;
  final List<FeatureDetail> details;
  final Widget Function(FeatureDetail) evaluationRow;
  final SigninStarter? onSignin;
  @override
  Widget build(BuildContext context) => feature == FeatureId.evaluation
      ? ListView(
          padding: const EdgeInsets.all(16),
          children: [for (final detail in details) evaluationRow(detail)],
        )
      : ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: details.length,
          separatorBuilder: (_, _) => const SizedBox(height: 16),
          itemBuilder: (context, index) =>
              _SigninCourseCard(detail: details[index], onSignin: onSignin),
        );
}

class _SigninCourseCard extends StatelessWidget {
  const _SigninCourseCard({required this.detail, required this.onSignin});
  final FeatureDetail detail;
  final SigninStarter? onSignin;

  String? get _notice {
    final p = detail.presentation! as SigninPresentation;
    final action = detail.action<SigninPerformAction>();
    if (action == null || action.scheduleId.trim().isEmpty) {
      return '未提供签到目标，请刷新课程后重试。';
    }
    if ((action.eligibility == ActionEligibility.denied && p.signStatus != 1) ||
        (action.eligibility == ActionEligibility.allowed &&
            p.signStatus != 0)) {
      return '签到状态与操作资格信息不一致；操作资格由服务端判定。';
    }
    return switch (action.eligibility) {
      ActionEligibility.unknown => '当前签到资格无法确认，请刷新后重试。',
      ActionEligibility.denied when p.signStatus != 1 => '当前课程不允许签到，请刷新确认。',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = detail.presentation! as SigninPresentation;
    final action = detail.action<SigninPerformAction>();
    final done = p.signStatus == 1;
    final allowed =
        action?.eligibility == ActionEligibility.allowed &&
        action!.scheduleId.trim().isNotEmpty;
    final theme = Theme.of(context);
    return Card(
      color: done
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: '课程详情',
                    child: InkWell(
                      onTap: () => _showDetails(context),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            detail.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _AcademicInfo(
                            icon: Icons.schedule,
                            text:
                                _timeRange(p.classBeginTime, p.classEndTime) ??
                                '时间未提供',
                          ),
                          if (p.signStatus != 0 && p.signStatus != 1)
                            const Text('签到状态未知'),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                if (done && !allowed)
                  const Tooltip(
                    message: '已签到',
                    child: Icon(Icons.check_circle, size: 32),
                  )
                else if (onSignin != null && action != null)
                  FilledButton(
                    onPressed: allowed ? () => onSignin!(action) : null,
                    child: const Text('签到'),
                  ),
              ],
            ),
            if (_notice case final notice?) ...[
              const SizedBox(height: 8),
              Text(notice, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showDetails(BuildContext context) {
    final p = detail.presentation! as SigninPresentation;
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(detail.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_timeRange(p.classBeginTime, p.classEndTime) ?? '时间未提供'),
              Text(switch (p.signStatus) {
                0 => '未签到',
                1 => '已签到',
                _ => '签到状态未知',
              }),
              if (p.signStatus case final status?) Text('原始状态：$status'),
              if (p.signStatus == 1 &&
                  detail.action<SigninPerformAction>()?.eligibility ==
                      ActionEligibility.denied)
                const Text('该课程已签到，不能重复提交。'),
              if (_notice case final notice?) Text(notice),
              const SizedBox(height: 12),
              _DetailField(label: '课程编号', value: p.courseId),
              for (final field in detail.fields)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _DetailField(label: field.label, value: field.value),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

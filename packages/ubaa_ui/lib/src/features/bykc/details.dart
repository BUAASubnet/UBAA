part of '../../widgets.dart';

class _BykcSection extends StatelessWidget {
  const _BykcSection(this.title, this.children);
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );
}

extension _BykcDetails on _FeatureDetailListState {
  Widget _bykcCourseDetails(
    BuildContext context,
    FeatureDetail detail,
    BykcCoursePresentation course,
  ) {
    final theme = Theme.of(context);
    final select = detail.action<BykcSelectAction>();
    final deselect = detail.action<BykcDeselectAction>();
    final canSelect =
        select?.eligibility == ActionEligibility.allowed &&
        select!.courseId > 0;
    final canDeselect =
        deselect?.eligibility == ActionEligibility.allowed &&
        deselect!.courseId > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course.courseName,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                _BykcStatusChip(_bykcDisplayStatus(course)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _BykcSection('基本信息', [
          _BykcInfoLine('教师', course.courseTeacher),
          _BykcInfoLine('地点', course.coursePosition),
          _BykcInfoLine('课程编号', '${course.id}'),
          _BykcInfoLine('已报名', course.courseCurrentCount?.toString()),
          _BykcInfoLine('人数上限', course.courseMaxCount?.toString()),
        ]),
        const SizedBox(height: 12),
        _BykcSection('时间安排', [
          _BykcInfoLine(
            '上课',
            _bykcRange(course.courseStartDate, course.courseEndDate),
          ),
          _BykcInfoLine(
            '选课',
            _bykcRange(
              course.courseSelectStartDate,
              course.courseSelectEndDate,
            ),
          ),
          _BykcInfoLine(
            '退选截止',
            course.courseCancelEndDate == null
                ? null
                : _bykcDate(course.courseCancelEndDate!),
          ),
        ]),
        if (widget.onBykcWrite != null) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (select != null && (course.selected != true || canSelect))
                OutlinedButton.icon(
                  onPressed: canSelect
                      ? () => widget.onBykcWrite!(
                          select.operation,
                          select.courseId,
                        )
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('准备选课'),
                ),
              if (deselect != null && (course.selected != false || canDeselect))
                OutlinedButton.icon(
                  onPressed: canDeselect
                      ? () => widget.onBykcWrite!(
                          deselect.operation,
                          deselect.courseId,
                        )
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                  label: const Text('准备退选'),
                ),
            ],
          ),
          if (!canSelect && !canDeselect)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('当前没有可执行的选课或退选操作，请刷新后核对。'),
            ),
        ],
      ],
    );
  }

  Widget _bykcChosenDetails(
    BuildContext context,
    FeatureDetail detail,
    BykcChosenPresentation course,
  ) {
    final signIn = _bykcSignAction(detail, BykcSignKind.signIn);
    final signOut = _bykcSignAction(detail, BykcSignKind.signOut);
    final deselect = detail.action<BykcDeselectAction>();
    bool canSign(BykcSignAction? action) =>
        action != null &&
        action.eligibility == ActionEligibility.allowed &&
        action.courseId > 0;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              course.courseName,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _BykcSection('基本信息', [
          _BykcInfoLine('教师', course.courseTeacher),
          _BykcInfoLine('地点', course.coursePosition),
          _BykcInfoLine(
            '分类',
            [
              course.category,
              course.subCategory,
            ].whereType<String>().join(' / '),
          ),
          _BykcInfoLine('课程编号', '${course.courseId}'),
          _BykcInfoLine('选课记录', '${course.recordId}'),
        ]),
        const SizedBox(height: 12),
        _BykcSection('时间安排', [
          _BykcInfoLine(
            '上课',
            _bykcRange(course.courseStartDate, course.courseEndDate),
          ),
          _BykcInfoLine(
            '选课时间',
            course.selectDate == null ? null : _bykcDate(course.selectDate!),
          ),
          _BykcInfoLine(
            '退选截止',
            course.courseCancelEndDate == null
                ? null
                : _bykcDate(course.courseCancelEndDate!),
          ),
        ]),
        const SizedBox(height: 12),
        _BykcSection('签到信息', [
          _BykcInfoLine('考勤', _bykcCheckinLabel(course.checkin)),
          _BykcInfoLine('考核', _bykcPassLabel(course.pass)),
          _BykcInfoLine(
            '成绩',
            course.score == null ? null : '${course.score} 分',
          ),
          _BykcInfoLine(
            '签到',
            _bykcRange(course.signStartDate, course.signEndDate),
          ),
          _BykcInfoLine(
            '签退',
            _bykcRange(course.signOutStartDate, course.signOutEndDate),
          ),
          _BykcInfoLine(
            '签到地点',
            course.signPointCount == null
                ? '未提供'
                : '${course.signPointCount} 处',
          ),
          _BykcInfoLine('签到类型', course.courseSignType?.toString()),
        ]),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (signIn != null && widget.onBykcSignWrite != null)
              OutlinedButton.icon(
                onPressed: canSign(signIn)
                    ? () => widget.onBykcSignWrite!(signIn)
                    : null,
                icon: const Icon(Icons.login),
                label: const Text('准备博雅签到'),
              ),
            if (signOut != null && widget.onBykcSignWrite != null)
              OutlinedButton.icon(
                onPressed: canSign(signOut)
                    ? () => widget.onBykcSignWrite!(signOut)
                    : null,
                icon: const Icon(Icons.logout),
                label: const Text('准备博雅签退'),
              ),
            if (deselect != null && widget.onBykcWrite != null)
              OutlinedButton.icon(
                onPressed:
                    deselect.eligibility == ActionEligibility.allowed &&
                        deselect.courseId > 0
                    ? () => widget.onBykcWrite!(
                        deselect.operation,
                        deselect.courseId,
                      )
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
                label: const Text('准备退选'),
              ),
          ],
        ),
      ],
    );
  }
}

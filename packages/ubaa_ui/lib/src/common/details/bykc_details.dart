part of 'detail_list.dart';

extension BykcDetails on _FeatureDetailListState {
  Widget _bykcCourseDetails(
    BuildContext context,
    FeatureDetail detail,
    BykcCoursePresentation course,
  ) {
    final theme = Theme.of(context);
    final select = detail.action<BykcSelectAction>();
    final deselect = detail.action<BykcDeselectAction>();
    final listCourse = widget.bykcListCourse?.id == course.id
        ? widget.bykcListCourse
        : null;
    final full =
        uiBykcDisplayStatus(course) == BykcCourseStatus.full ||
        listCourse != null &&
            uiBykcDisplayStatus(listCourse) == BykcCourseStatus.full;
    final canSelect =
        select?.eligibility == ActionEligibility.allowed &&
        select!.courseId > 0 &&
        !full;
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
                BykcStatusChip(
                  full && course.selected != true
                      ? BykcCourseStatus.full
                      : uiBykcDisplayStatus(course),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        BykcSection('基本信息', [
          BykcInfoLine('教师', course.courseTeacher),
          BykcInfoLine('地点', course.coursePosition),
          BykcInfoLine('课程编号', '${course.id}'),
          BykcInfoLine(
            course.courseCurrentCount == null &&
                    listCourse?.courseCurrentCount != null
                ? '已报名（列表）'
                : '已报名',
            (course.courseCurrentCount ?? listCourse?.courseCurrentCount)
                ?.toString(),
          ),
          BykcInfoLine('人数上限', course.courseMaxCount?.toString()),
          BykcInfoLine('类别', course.categoryDisplayName),
          ...uiBykcContactFields(course.supplement),
        ]),
        const SizedBox(height: 12),
        BykcSection('时间安排', [
          BykcInfoLine(
            '上课',
            uiBykcRange(course.courseStartDate, course.courseEndDate),
          ),
          BykcInfoLine(
            '选课',
            uiBykcRange(
              course.courseSelectStartDate,
              course.courseSelectEndDate,
            ),
          ),
          BykcInfoLine(
            '退选截止',
            course.courseCancelEndDate == null
                ? null
                : uiBykcDate(course.courseCancelEndDate!),
          ),
        ]),
        ...uiBykcSupplementSections(course),
        if (course.supplement case final supplement?
            when supplement.signConfig != null ||
                supplement.attendance != null) ...[
          const SizedBox(height: 12),
          BykcSection('签到信息', [
            if (supplement.attendance != null)
              BykcInfoLine(
                '考勤',
                uiBykcCheckinLabel(supplement.attendance?.checkin),
              ),
            if (supplement.attendance != null)
              BykcInfoLine(
                '考核',
                supplement.attendance?.pass == null
                    ? '考核未知'
                    : uiBykcPassLabel(supplement.attendance!.pass),
              ),
            if (supplement.signConfig != null)
              ...uiBykcDisplaySignFields(supplement.signConfig),
          ]),
        ],
        if (course.selected == true &&
            detail.readNavigation != null &&
            widget.onNavigate != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: !widget.writesEnabled
                ? null
                : () => widget.onNavigate!(detail.readNavigation!),
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('查看签到与签退'),
          ),
        ],
        if (widget.onBykcWrite != null) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (select != null && (course.selected != true || canSelect))
                OutlinedButton.icon(
                  onPressed: !widget.writesEnabled
                      ? null
                      : canSelect
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
                  onPressed: !widget.writesEnabled
                      ? null
                      : canDeselect
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
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                full
                    ? '该课程人数已满，当前不可选择。'
                    : select?.eligibility == ActionEligibility.unknown
                    ? '选课状态不完整，请刷新课程详情后重试。'
                    : '当前没有可执行的选课或退选操作，请刷新后核对。',
              ),
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
        BykcSection('基本信息', [
          BykcInfoLine('教师', course.courseTeacher),
          BykcInfoLine('地点', course.coursePosition),
          BykcInfoLine(
            '分类',
            [
              course.category,
              course.subCategory,
            ].whereType<String>().join(' / '),
          ),
          BykcInfoLine('课程编号', '${course.courseId}'),
          BykcInfoLine('选课记录', '${course.recordId}'),
          ...uiBykcContactFields(course.fullDetail?.supplement),
        ]),
        const SizedBox(height: 12),
        BykcSection('时间安排', [
          BykcInfoLine(
            '上课',
            uiBykcRange(course.courseStartDate, course.courseEndDate),
          ),
          BykcInfoLine(
            '选课时间',
            course.selectDate == null ? null : uiBykcDate(course.selectDate!),
          ),
          BykcInfoLine(
            '退选截止',
            course.courseCancelEndDate == null
                ? null
                : uiBykcDate(course.courseCancelEndDate!),
          ),
        ]),
        const SizedBox(height: 12),
        if (course.fullDetail case final fullDetail?)
          ...uiBykcSupplementSections(fullDetail),
        BykcSection('签到信息', [
          BykcInfoLine('考勤', uiBykcCheckinLabel(course.checkin)),
          BykcInfoLine('考核', uiBykcPassLabel(course.pass)),
          BykcInfoLine('成绩', course.score == null ? null : '${course.score} 分'),
          ...uiBykcDisplaySignFields(course.fullDetail?.supplement?.signConfig),
          BykcInfoLine('签到类型', course.courseSignType?.toString()),
        ]),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (signIn != null && widget.onBykcSignWrite != null)
              OutlinedButton.icon(
                onPressed: !widget.writesEnabled
                    ? null
                    : canSign(signIn)
                    ? () => widget.onBykcSignWrite!(signIn)
                    : null,
                icon: const Icon(Icons.login),
                label: const Text('准备博雅签到'),
              ),
            if (signOut != null && widget.onBykcSignWrite != null)
              OutlinedButton.icon(
                onPressed: !widget.writesEnabled
                    ? null
                    : canSign(signOut)
                    ? () => widget.onBykcSignWrite!(signOut)
                    : null,
                icon: const Icon(Icons.logout),
                label: const Text('准备博雅签退'),
              ),
            if (deselect != null && widget.onBykcWrite != null)
              OutlinedButton.icon(
                onPressed: !widget.writesEnabled
                    ? null
                    : deselect.eligibility == ActionEligibility.allowed &&
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

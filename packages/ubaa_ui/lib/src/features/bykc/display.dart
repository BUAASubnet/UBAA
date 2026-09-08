part of '../../widgets.dart';

String _bykcStatusLabel(BykcCourseStatus status) => switch (status) {
  BykcCourseStatus.preview => '预告',
  BykcCourseStatus.available => '可选',
  BykcCourseStatus.full => '人数已满',
  BykcCourseStatus.selected => '已选',
  BykcCourseStatus.ended => '选课结束',
  BykcCourseStatus.expired => '已过期',
};

// 冻结列表的“人数已满”展示规则；不参与任何写资格判断。
bool _bykcDisplayedFull(BykcCoursePresentation course) =>
    course.status == BykcCourseStatus.full ||
    (course.status == BykcCourseStatus.available &&
        course.courseCurrentCount != null &&
        (course.courseMaxCount ?? 0) > 0 &&
        course.courseCurrentCount! >= course.courseMaxCount!);

BykcCourseStatus _bykcDisplayStatus(BykcCoursePresentation course) =>
    course.selected == true
    ? BykcCourseStatus.selected
    : _bykcDisplayedFull(course)
    ? BykcCourseStatus.full
    : course.status;

String _bykcCheckinLabel(int? value) => switch (value) {
  null => '考勤未知',
  0 => '待考勤',
  1 => '考勤通过',
  2 => '迟到',
  3 => '早退',
  4 => '缺勤',
  5 => '已签到、未签退',
  6 => '已签到(异常)、未签退',
  7 => '未签到、已签退',
  8 => '未签到、已签退(异常)',
  9 => '已签到(异常)、已签退',
  10 => '已签到、已签退(异常)',
  11 => '已签到(异常)、已签退(异常)',
  final code => '考勤状态 $code',
};

String _bykcPassLabel(int? value) => switch (value) {
  null => '待考核',
  0 => '考核未通过',
  1 => '考核通过',
  final code => '考核状态 $code',
};

String _bykcDate(String value) {
  final date = DateTime.tryParse(value.trim());
  if (date == null || date.isUtc) return value.trim();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} '
      '${two(date.hour)}:${two(date.minute)}';
}

String? _bykcRange(String? start, String? end) {
  final begin = start?.trim(), finish = end?.trim();
  if (begin == null || begin.isEmpty) {
    return finish == null || finish.isEmpty ? null : '截至 ${_bykcDate(finish)}';
  }
  if (finish == null || finish.isEmpty) return _bykcDate(begin);
  final a = _bykcDate(begin), b = _bykcDate(finish);
  if (a.length == 16 &&
      b.length == 16 &&
      a.substring(0, 10) == b.substring(0, 10)) {
    return '$a–${b.substring(11)}';
  }
  return '$a–$b';
}

// 沿冻结 resolveSelectTimeDisplay；只决定列表文案，不参与写入资格。
({String label, String value})? _bykcSelectTime(BykcCoursePresentation course) {
  final start = course.courseSelectStartDate?.trim();
  final end = course.courseSelectEndDate?.trim();
  final startDate = start == null ? null : DateTime.tryParse(start);
  if (startDate != null && DateTime.now().isBefore(startDate)) {
    return (label: '开始选课', value: _bykcDate(start!));
  }
  if (end != null && end.isNotEmpty) {
    return (label: '截止选课', value: _bykcDate(end));
  }
  if (start != null && start.isNotEmpty) {
    return (label: '开始选课', value: _bykcDate(start));
  }
  return null;
}

class _BykcInfoLine extends StatelessWidget {
  const _BykcInfoLine(this.label, this.value, {this.maxLines});
  final String label;
  final String? value;
  final int? maxLines;
  @override
  Widget build(BuildContext context) {
    if (value == null || value!.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            softWrap: false,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value!,
              maxLines: maxLines,
              overflow: maxLines == null ? null : TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _BykcStatusChip extends StatelessWidget {
  const _BykcStatusChip(this.status);
  final BykcCourseStatus status;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 112),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        _bykcStatusLabel(status),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

List<String> _bykcSearchValues(FeaturePresentation? value) => switch (value) {
  BykcCoursePresentation p => [
    p.courseName,
    _bykcStatusLabel(_bykcDisplayStatus(p)),
    ...[
      p.courseTeacher,
      p.coursePosition,
      p.courseStartDate,
      p.courseEndDate,
      p.courseSelectStartDate,
      p.courseSelectEndDate,
      p.courseCancelEndDate,
    ].whereType<String>(),
  ],
  BykcChosenPresentation p => [
    p.courseName,
    _bykcCheckinLabel(p.checkin),
    _bykcPassLabel(p.pass),
    ...[
      p.courseTeacher,
      p.coursePosition,
      p.courseStartDate,
      p.courseEndDate,
      p.category,
      p.subCategory,
    ].whereType<String>(),
  ],
  BykcCategoryPresentation p => [
    ...[p.categoryName, p.subCategoryName].whereType<String>(),
    p.qualified == null
        ? '未知'
        : p.qualified!
        ? '达标'
        : '未达标',
  ],
  _ => const [],
};

const _defaultBykcStatuses = <BykcCourseStatus>{
  BykcCourseStatus.preview,
  BykcCourseStatus.available,
  BykcCourseStatus.full,
  BykcCourseStatus.selected,
};

bool _matchesBykcStatuses(
  BykcCoursePresentation course,
  Set<BykcCourseStatus> statuses,
) =>
    statuses.isEmpty ||
    statuses.any(
      (status) => switch (status) {
        BykcCourseStatus.full =>
          course.selected != true && _bykcDisplayedFull(course),
        BykcCourseStatus.available =>
          course.status == BykcCourseStatus.available &&
              !_bykcDisplayedFull(course),
        _ => course.status == status,
      },
    );

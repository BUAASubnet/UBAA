part of '../widgets.dart';

class _ScheduleContent extends StatelessWidget {
  const _ScheduleContent({required this.details, required this.wide});
  final List<FeatureDetail> details;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final days = <int, List<FeatureDetail>>{};
    final unknown = <FeatureDetail>[];
    for (final detail in details) {
      final course = detail.presentation! as ScheduleCoursePresentation;
      if (_scheduled(course)) {
        (days[course.dayOfWeek!] ??= []).add(detail);
      } else {
        unknown.add(detail);
      }
    }
    Widget day(int index, List<FeatureDetail> courses) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            _weekdays[index - 1],
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        if (courses.isEmpty)
          const Padding(padding: EdgeInsets.all(12), child: Text('暂无课程')),
        for (final course in courses)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _AcademicCard(detail: course),
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wide) ...[
          const Text('周课表 · 横向滚动查看各天；课程按查询中的原顺序展示'),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 1; i <= 7; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: SizedBox(width: 240, child: day(i, days[i] ?? [])),
                  ),
              ],
            ),
          ),
        ] else
          for (var i = 1; i <= 7; i++)
            if (days[i] case final courses?) day(i, courses),
        if (unknown.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('时间待确认', style: Theme.of(context).textTheme.titleSmall),
          ),
          for (final detail in unknown)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _AcademicCard(detail: detail),
            ),
        ],
      ],
    );
  }
}

const _weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
bool _scheduled(ScheduleCoursePresentation course) =>
    course.dayOfWeek != null &&
    course.dayOfWeek! >= 1 &&
    course.dayOfWeek! <= 7 &&
    course.beginSection != null &&
    course.beginSection! > 0 &&
    course.endSection != null &&
    course.endSection! >= course.beginSection!;

List<Widget> _courseFields(ScheduleCoursePresentation course) => [
  if (_scheduled(course))
    _AcademicInfo(
      icon: Icons.calendar_view_week_outlined,
      text: _weekdays[course.dayOfWeek! - 1],
    ),
  if (_scheduled(course))
    Chip(
      label: Text(
        course.beginSection == course.endSection
            ? '第${course.beginSection}节'
            : '第${course.beginSection}–${course.endSection}节',
      ),
    ),
  if (_timeRange(course.beginTime, course.endTime) case final time?)
    _AcademicInfo(icon: Icons.schedule, text: time),
  _AcademicInfo(
    icon: Icons.place_outlined,
    text: _nonBlank(course.place) ?? '地点待公布',
  ),
  if (_nonBlank(course.weeksAndTeachers) case final value?) Text(value),
  _AcademicMore(
    fields: [
      ('课程编号', course.courseCode),
      if (_nonBlank(course.courseSerialNo) case final value?) ('课程序号', value),
      if (_nonBlank(course.credit) case final value?) ('学分', value),
      if (_nonBlank(course.teachingTarget) case final value?) ('教学对象', value),
      if (!_scheduled(course)) ...[
        if (course.dayOfWeek case final value?) ('原周几', '$value'),
        if (course.beginSection case final value?) ('原开始节次', '$value'),
        if (course.endSection case final value?) ('原结束节次', '$value'),
      ],
    ],
  ),
];

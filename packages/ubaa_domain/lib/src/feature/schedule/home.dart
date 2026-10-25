import '../presentation.dart';
import '../../common/error.dart';
import '../result.dart';
import '../overview.dart';

/// 将绝对时刻转换为校园墙上时间，所有日历比较使用相同分量。
DateTime homeCampusTime(DateTime instant) {
  final value = instant.toUtc().add(const Duration(hours: 8));
  return DateTime(
    value.year,
    value.month,
    value.day,
    value.hour,
    value.minute,
    value.second,
  );
}

String homeDateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

DateTime? homeParseDate(String raw) {
  final match = RegExp(
    r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T].*)?$',
  ).firstMatch(raw.trim());
  if (match == null) return null;
  final y = int.parse(match[1]!),
      m = int.parse(match[2]!),
      d = int.parse(match[3]!);
  final date = DateTime(y, m, d);
  return date.year == y && date.month == m && date.day == d ? date : null;
}

WeekPresentation? homeWeekOn(
  Iterable<WeekPresentation> weeks,
  DateTime day, {
  String? term,
}) {
  final date = DateTime(day.year, day.month, day.day);
  final matches = weeks.where((week) {
    final start = homeParseDate(week.startDate),
        end = homeParseDate(week.endDate);
    return week.number > 0 &&
        week.requestTerm.isNotEmpty &&
        week.requestTerm == week.responseTerm &&
        (term == null || week.requestTerm == term) &&
        start != null &&
        end != null &&
        !end.isBefore(start) &&
        !date.isBefore(start) &&
        !date.isAfter(end);
  }).toList();
  return matches.length == 1 ? matches.single : null;
}

({DateTime start, DateTime end})? homeCoursePeriod(String? time, DateTime day) {
  final match = RegExp(
    r'^(\d{1,2}):(\d{2})(?::(\d{2}))?\s*[-–—]\s*(\d{1,2}):(\d{2})(?::(\d{2}))?$',
  ).firstMatch(time?.trim() ?? '');
  if (match == null) return null;
  final values = [for (var i = 1; i <= 6; i++) int.parse(match[i] ?? '0')];
  if (values[0] > 23 ||
      values[3] > 23 ||
      values[1] > 59 ||
      values[2] > 59 ||
      values[4] > 59 ||
      values[5] > 59)
    return null;
  final start = DateTime(
    day.year,
    day.month,
    day.day,
    values[0],
    values[1],
    values[2],
  );
  final end = DateTime(
    day.year,
    day.month,
    day.day,
    values[3],
    values[4],
    values[5],
  );
  return end.isAfter(start) ? (start: start, end: end) : null;
}

String homeCourseStatus(
  TodayCoursePresentation course,
  DateTime day,
  DateTime now,
) {
  final period = homeCoursePeriod(course.time, day);
  if (period == null) return '时间待定';
  if (now.isBefore(period.start)) return '未开始';
  return now.isBefore(period.end) ? '进行中' : '已结束';
}

bool homeCoursesFinished(
  List<FeatureDetail> courses,
  DateTime day,
  DateTime now,
) =>
    courses.isNotEmpty &&
    courses.every((detail) {
      final p = detail.presentation;
      if (p is! TodayCoursePresentation) return false;
      final period = homeCoursePeriod(p.time, day);
      return period != null && !now.isBefore(period.end);
    });

FeatureResult homeProjectScheduleDay(
  FeatureResult weekly,
  WeekPresentation week,
  DateTime date,
) {
  if (weekly.details.any((detail) {
    final p = detail.presentation;
    return p is! ScheduleCoursePresentation ||
        p.dayOfWeek == null ||
        p.dayOfWeek! < 1 ||
        p.dayOfWeek! > 7;
  })) {
    return const FeatureResult.failure(
      UiError(
        code: UbaaErrorCode.invalidInput,
        title: '课表暂不可用',
        message: '课程日期信息不完整',
        retryable: true,
      ),
    );
  }
  final details = <FeatureDetail>[
    for (final detail in weekly.details)
      if (detail.presentation case ScheduleCoursePresentation p
          when p.dayOfWeek == date.weekday)
        FeatureDetail(
          title: detail.title,
          presentation: TodayCoursePresentation(
            place: p.place,
            time: p.beginTime == null && p.endTime == null
                ? null
                : '${p.beginTime ?? '待定'}–${p.endTime ?? '待定'}',
          ),
        ),
  ];
  final overview = HomeScheduleOverview(date: homeDateKey(date), week: week);
  return details.isEmpty
      ? FeatureResult.empty(
          overview: overview,
          evidence: weekly.evidence,
          resolvedRoute: weekly.resolvedRoute,
        )
      : FeatureResult.success(
          details: details,
          overview: overview,
          evidence: weekly.evidence,
          resolvedRoute: weekly.resolvedRoute,
        );
}

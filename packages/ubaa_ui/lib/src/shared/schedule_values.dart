import 'package:ubaa_domain/ubaa_domain.dart';

int uiCourseStart(FeatureDetail detail) {
  final value = (detail.presentation as TodayCoursePresentation).time ?? '';
  final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value);
  if (match == null) return 9999;
  final hour = int.parse(match[1]!), minute = int.parse(match[2]!);
  return hour < 24 && minute < 60 ? hour * 60 + minute : 9999;
}

String uiSavedScheduleTime(DateTime value) {
  final campus = value.toUtc().add(const Duration(hours: 8));
  return '${campus.month}月${campus.day}日 ${campus.hour.toString().padLeft(2, '0')}:${campus.minute.toString().padLeft(2, '0')}';
}

bool uiScheduled(ScheduleCoursePresentation course) =>
    course.dayOfWeek != null &&
    course.dayOfWeek! >= 1 &&
    course.dayOfWeek! <= 7 &&
    course.beginSection != null &&
    course.beginSection! > 0 &&
    course.endSection != null &&
    course.endSection! >= course.beginSection!;

bool uiIsWeeklyScheduleQuery(FeatureQuery? query) =>
    query?.view == FeatureQueryView.scheduleWeek ||
    (query?.view == FeatureQueryView.summary &&
        query?.term != null &&
        query?.week != null);

const uiWeekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];

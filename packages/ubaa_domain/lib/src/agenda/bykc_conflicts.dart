import 'models.dart';
import 'school.dart';

/// 博雅无偏移量的时间按北京时间解释，不依赖设备所在时区。
final class BykcCourseInterval {
  const BykcCourseInterval(this.start, this.end);
  final DateTime start, end;

  static BykcCourseInterval? parse(String? start, String? end) {
    final a = _time(start), b = _time(end);
    return a != null && b != null && a.isBefore(b)
        ? BykcCourseInterval(a, b)
        : null;
  }

  bool overlaps(BykcCourseInterval other) =>
      start.isBefore(other.end) && other.start.isBefore(end);

  static DateTime? _time(String? value) {
    if (value == null) return null;
    final text = value.trim();
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(?:Z|[+-]\d{2}:?\d{2})?$',
    ).firstMatch(text);
    if (match == null ||
        int.parse(match[4]!) > 23 ||
        int.parse(match[5]!) > 59 ||
        int.parse(match[6] ?? '0') > 59)
      return null;
    final day = DateTime.utc(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
    );
    if (day.year != int.parse(match[1]!) ||
        day.month != int.parse(match[2]!) ||
        day.day != int.parse(match[3]!))
      return null;
    final zoned = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(text);
    return DateTime.tryParse(zoned ? text : '$text+08:00')?.toUtc();
  }
}

/// 比较 Core 已展开的日程发生项；不在展示层重新展开重复规则。
List<AgendaEntry> bykcAgendaConflicts(
  BykcCourseInterval course,
  Iterable<AgendaEntry> entries, {
  required int courseId,
}) => [
  for (final entry in entries)
    if (!entry.hidden &&
        !entry.completed &&
        !(entry.school?.navigation.feature == AgendaFeature.bykc &&
            entry.school?.navigation.bykcCourseId == courseId))
      if (_interval(entry) case final interval?)
        if (course.overlaps(interval)) entry,
];

BykcCourseInterval? _interval(AgendaEntry entry) {
  if (entry.local?.content.kind == AgendaKind.task) return null;
  final timing = entry.timing;
  if (timing.kind == AgendaTimingKind.period) {
    return BykcCourseInterval.parse(timing.start?.rfc3339, timing.end?.rfc3339);
  }
  // 学校全天项也用于表示具体时刻未知的占位，不能据此隐藏一天的课程。
  if (timing.kind == AgendaTimingKind.allDay &&
      entry.local?.content.allDay == true) {
    return BykcCourseInterval.parse(
      entry.local!.content.start?.rfc3339,
      entry.local!.content.end?.rfc3339,
    );
  }
  return null;
}

import 'dart:math' as math;
import 'package:ubaa_domain/ubaa_domain.dart';
import 'format.dart';

/// 日历几何使用北京时间的年月日字段，领域时间仍由 Core 提供。
DateTime agendaDay(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);
DateTime agendaWeekStart(DateTime value) =>
    agendaDay(value).subtract(Duration(days: value.weekday - 1));
DateTime agendaShiftMonth(DateTime value, int offset) {
  final first = DateTime.utc(value.year, value.month + offset);
  final last = DateTime.utc(first.year, first.month + 1, 0).day;
  return DateTime.utc(first.year, first.month, math.min(value.day, last));
}

String agendaEntryKey(AgendaEntry entry) => switch (entry.local) {
  final local? => 'local:${local.itemId}:${local.recurrenceId}',
  null => 'school:${entry.school!.key.source}:${entry.school!.key.upstreamId}',
};

DateTime? agendaStart(AgendaEntry entry) => entry.timing.from != null
    ? DateTime.tryParse('${entry.timing.from}T00:00:00Z')
    : agendaValue(entry.timing.start);
DateTime? agendaEnd(AgendaEntry entry) => entry.timing.to != null
    ? DateTime.tryParse('${entry.timing.to}T00:00:00Z')
    : agendaValue(entry.timing.end);
DateTime? agendaEntryDate(AgendaEntry entry) =>
    agendaStart(entry) ?? agendaValue(entry.timing.due) ?? agendaEnd(entry);

bool agendaOverlaps(
  DateTime start,
  DateTime end,
  DateTime otherStart,
  DateTime otherEnd,
) => start.isBefore(otherEnd) && end.isAfter(otherStart);

bool agendaOnDay(AgendaEntry entry, DateTime day) {
  final start = agendaStart(entry), end = agendaEnd(entry);
  final date = agendaDay(day);
  if (start != null && end != null && end.isAfter(start)) {
    return agendaOverlaps(start, end, date, date.add(const Duration(days: 1)));
  }
  final point = agendaEntryDate(entry);
  return point != null && agendaDay(point) == date;
}

List<AgendaEntry> agendaContentConflicts(
  AgendaContent content,
  Iterable<AgendaEntry> entries,
) {
  final start = agendaValue(content.start), end = agendaValue(content.end);
  if (content.kind != AgendaKind.event || start == null || end == null)
    return [];
  return [
    for (final entry in entries)
      if (entry.school?.navigation.feature == AgendaFeature.schedule &&
          entry.timing.kind == AgendaTimingKind.period)
        if (agendaStart(entry) case final courseStart?)
          if (agendaEnd(entry) case final courseEnd?)
            if (courseEnd.isAfter(courseStart) &&
                agendaOverlaps(start, end, courseStart, courseEnd))
              entry,
  ];
}

List<AgendaEntry> agendaEntryConflicts(
  AgendaEntry entry,
  Iterable<AgendaEntry> entries,
) {
  if (entry.local case final local?)
    return agendaContentConflicts(local.content, entries);
  if (entry.school?.navigation.feature != AgendaFeature.cgyy ||
      entry.timing.kind != AgendaTimingKind.period)
    return [];
  final start = agendaStart(entry), end = agendaEnd(entry);
  if (start == null || end == null || !end.isAfter(start)) return [];
  return [
    for (final course in entries)
      if (course.school?.navigation.feature == AgendaFeature.schedule &&
          course.timing.kind == AgendaTimingKind.period)
        if (agendaStart(course) case final courseStart?)
          if (agendaEnd(course) case final courseEnd?)
            if (courseEnd.isAfter(courseStart) &&
                agendaOverlaps(start, end, courseStart, courseEnd))
              course,
  ];
}

/// 同一天同名同地点的课程，若前一节结束到后一节开始不超过 20 分钟，界面合并为一段显示。
bool agendaCourseContinues(
  AgendaEntry a,
  DateTime aEnd,
  AgendaEntry b,
  DateTime bStart,
) {
  if (a.school?.navigation.feature != AgendaFeature.schedule ||
      b.school?.navigation.feature != AgendaFeature.schedule) {
    return false;
  }
  if (a.school!.title != b.school!.title ||
      (a.school!.location ?? '') != (b.school!.location ?? '')) {
    return false;
  }
  final gap = bStart.difference(aEnd);
  return !gap.isNegative &&
      gap <= const Duration(minutes: 20) &&
      agendaDay(aEnd) == agendaDay(bStart);
}

/// 将已按开始时间排序的条目中连续课程合并，返回（条目，显示结束时间）。
/// 中间夹有签到等其他条目时同样合并。
List<(AgendaEntry, DateTime?)> agendaMergeCourses(List<AgendaEntry> sorted) {
  final out = <(AgendaEntry, DateTime?)>[];
  outer:
  for (final e in sorted) {
    final start = agendaStart(e);
    if (start != null &&
        e.school?.navigation.feature == AgendaFeature.schedule) {
      for (var k = out.length - 1; k >= 0; k--) {
        final (prev, prevEnd) = out[k];
        if (prevEnd != null && agendaCourseContinues(prev, prevEnd, e, start)) {
          out[k] = (prev, agendaEnd(e) ?? prevEnd);
          continue outer;
        }
      }
    }
    out.add((e, agendaEnd(e)));
  }
  return out;
}

/// 与课程同名且时段重叠的签到条目归入该课程，返回（条目，显示结束时间，签到）。
List<(AgendaEntry, DateTime?, AgendaEntry?)> agendaAttachSignins(
  List<(AgendaEntry, DateTime?)> merged,
) {
  final attached = <AgendaEntry>{};
  final out = <(AgendaEntry, DateTime?, AgendaEntry?)>[];
  for (final (entry, end) in merged) {
    AgendaEntry? signin;
    final start = agendaStart(entry);
    if (entry.school?.navigation.feature == AgendaFeature.schedule &&
        start != null &&
        end != null) {
      for (final (other, _) in merged) {
        if (attached.contains(other) ||
            !agendaSigninMatches(other, entry, start, end))
          continue;
        signin = other;
        attached.add(other);
        break;
      }
    }
    out.add((entry, end, signin));
  }
  return [
    for (final item in out)
      if (!attached.contains(item.$1)) item,
  ];
}

bool agendaSigninMatches(
  AgendaEntry signin,
  AgendaEntry course,
  DateTime start,
  DateTime end,
) {
  if (signin.school?.navigation.feature != AgendaFeature.signin ||
      signin.school!.title != course.school?.title) {
    return false;
  }
  final s = agendaStart(signin), e = agendaEnd(signin) ?? s;
  return s != null &&
      e != null &&
      s.isBefore(end) &&
      !e.isBefore(start) &&
      agendaDay(s) == agendaDay(start);
}

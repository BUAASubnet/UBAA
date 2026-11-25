import 'dart:math' as math;
import 'package:ubaa_domain/ubaa_domain.dart';
import 'format.dart';

export 'package:ubaa_domain/ubaa_domain.dart'
    show
        agendaDay,
        agendaStart,
        agendaEnd,
        agendaCourseContinues,
        agendaMergeCourses;

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

/// 在可见日期范围内一次分组，跨日事项同时进入覆盖到的日期，结束时刻不包含在内。
Map<DateTime, List<AgendaEntry>> agendaEntriesByDay(
  Iterable<AgendaEntry> entries,
  DateTime first,
  int days,
) {
  final from = agendaDay(first);
  final until = from.add(Duration(days: days));
  final groups = <DateTime, List<AgendaEntry>>{};
  for (final entry in entries) {
    final start = agendaStart(entry), end = agendaEnd(entry);
    if (start != null && end != null && end.isAfter(start)) {
      var day = agendaDay(start);
      if (day.isBefore(from)) day = from;
      while (day.isBefore(until) && day.isBefore(end)) {
        (groups[day] ??= []).add(entry);
        day = day.add(const Duration(days: 1));
      }
    } else {
      final point = start ?? agendaValue(entry.timing.due) ?? end;
      if (point == null) continue;
      final day = agendaDay(point);
      if (!day.isBefore(from) && day.isBefore(until))
        (groups[day] ??= []).add(entry);
    }
  }
  return groups;
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

/// 详情与列表一致：课程按同日连续小节合并后的显示结束时间。
DateTime? agendaDisplayEnd(AgendaEntry entry, Iterable<AgendaEntry> entries) {
  final start = agendaStart(entry);
  if (start == null ||
      entry.school?.navigation.feature != AgendaFeature.schedule) {
    return agendaEnd(entry);
  }
  final sameDay = [
    for (final e in entries)
      if (e.school?.navigation.feature == AgendaFeature.schedule)
        if (agendaStart(e) case final s? when agendaDay(s) == agendaDay(start))
          e,
  ]..sort((a, b) => agendaStart(a)!.compareTo(agendaStart(b)!));
  final key = agendaEntryKey(entry);
  for (final (e, end) in agendaMergeCourses(sameDay)) {
    if (agendaEntryKey(e) == key) return end;
  }
  return agendaEnd(entry);
}

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

import 'package:ubaa_domain/ubaa_domain.dart';
import '../contracts/backend.dart';
import '../contracts/offline.dart';

/// 只读取当前账号已加密保存的完整课表，不触发在线恢复。
Future<ScheduleWidgetSnapshot> readScheduleWidgetSnapshot({
  required OfflineQueryBackend backend,
  required String owner,
  required RoutePolicy policy,
  required bool Function() isCurrent,
}) async {
  void check() {
    if (!isCurrent())
      throw const BackendException(UbaaErrorCode.operationConflict);
  }

  Future<CachedFeatureProjection?> read(FeatureQuery query) async {
    check();
    final result = await backend.readCachedQuery(
      FeatureId.schedule,
      query,
      policy,
    );
    check();
    final value = result.projection;
    if (value == null ||
        !value.complete ||
        value.accountId != owner ||
        value.feature != FeatureId.schedule ||
        !value.readContext.hasSameQuery(query))
      return null;
    return value;
  }

  final terms = await read(
    const FeatureQuery(view: FeatureQueryView.scheduleTerms),
  );
  final semesters = <Map<String, Object?>>[];
  final seen = <String>{};
  for (final item in terms?.details ?? <FeatureDetail>[]) {
    if (item.presentation case final TermPresentation term) {
      if (term.code.isEmpty || !seen.add(term.code)) continue;
      final weeks = await read(
        FeatureQuery(view: FeatureQueryView.scheduleWeeks, term: term.code),
      );
      if (weeks == null || weeks.details.isEmpty || weeks.details.length > 80)
        continue;
      final exported = <Map<String, Object?>>[];
      final numbers = <int>{};
      var valid = true;
      for (final detail in weeks.details) {
        if (detail.presentation is! WeekPresentation) {
          valid = false;
          break;
        }
        final week = detail.presentation! as WeekPresentation;
        final start = _date(week.startDate), end = _date(week.endDate);
        if (week.number < 1 ||
            !numbers.add(week.number) ||
            week.requestTerm != term.code ||
            week.responseTerm != term.code ||
            start == null ||
            end == null ||
            start.weekday != DateTime.monday ||
            end.difference(start).inDays != 6) {
          valid = false;
          break;
        }
        final schedule = await read(
          FeatureQuery(
            view: FeatureQueryView.scheduleWeek,
            term: term.code,
            week: week.number,
          ),
        );
        if (schedule == null || schedule.details.length > 512) {
          valid = false;
          break;
        }
        final courses = <Map<String, Object?>>[];
        final presentations = <ScheduleCoursePresentation>[];
        for (final course in schedule.details) {
          if (course.presentation case final ScheduleCoursePresentation data) {
            if (data.dayOfWeek == null ||
                data.dayOfWeek! < 1 ||
                data.dayOfWeek! > 7)
              continue;
            presentations.add(data);
            courses.add({
              'name': course.title,
              'day': data.dayOfWeek,
              'begin': data.beginSection,
              'end': data.endSection,
              'startTime': data.beginTime,
              'endTime': data.endTime,
              'place': data.place,
              'weeksAndTeachers': data.weeksAndTeachers,
            });
          }
        }
        final overview = schedule.overview;
        final times = scheduleSectionTimes(
          courses: presentations,
          explicit: overview is ScheduleWeekOverview
              ? overview.sectionTimes
              : [],
          code: overview is ScheduleWeekOverview ? overview.code : null,
        );
        exported.add({
          'number': week.number,
          'name': detail.title,
          'start': _day(start),
          'end': _day(end),
          'courses': courses,
          'times': [
            for (final t in times)
              {'section': t.section, 'start': t.start, 'end': t.end},
          ],
        });
      }
      if (valid && exported.isNotEmpty) {
        semesters.add({
          'term': term.code,
          'name': item.title,
          'updatedAt': weeks.fetchedAt.toUtc().toIso8601String(),
          'weeks': exported,
        });
      }
    }
  }
  check();
  return ScheduleWidgetSnapshot(owner: owner, semesters: semesters);
}

DateTime? _date(String raw) {
  final value = raw.trim().split(RegExp('[ T]')).first;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return null;
  final date = DateTime.utc(
    int.parse(match[1]!),
    int.parse(match[2]!),
    int.parse(match[3]!),
  );
  return _day(date) == value ? date : null;
}

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

import 'package:ubaa_domain/ubaa_domain.dart';

import 'promo_data.dart';
import 'promo_schoolwork.dart';

AgendaTime _time(DateTime date, String hhmm) =>
    AgendaTime(rfc3339: storeRfc3339(date, hhmm), timezone: 'Asia/Shanghai');

/// 只读的本机日程替身：汇集示例课表、作业、考试和个人日程。
/// 截图流程不新建、不编辑日程，写方法一律拒绝。
final class PromoAgenda implements AgendaBackend {
  @override
  Future<void> openAccount(String accountId) async {}

  @override
  Future<void> deactivate() async {}

  @override
  Future<AgendaQueryResult> query(AgendaQuery query) async {
    bool inRange(String day) =>
        day.compareTo(query.from) >= 0 && day.compareTo(query.to) <= 0;
    final entries = <AgendaEntry>[];
    for (var week = 1; week <= storeWeekCount; week++) {
      for (final course in storeCourses) {
        final day = storeDate(week, course.day);
        if (!course.occursIn(week) || !inRange(storeDateKey(day))) continue;
        final start = _time(day, course.beginTime);
        final end = _time(day, course.endTime);
        final timing = AgendaTiming(
          kind: AgendaTimingKind.period,
          start: start,
          end: end,
        );
        entries.add(
          AgendaEntry(
            school: SchoolAgendaItem(
              key: SchoolAgendaKey(
                source: 'schedule',
                upstreamId:
                    '${course.code}-$week-${course.day}-${course.begin}',
              ),
              timing: timing,
              sortTime: start,
              title: course.name,
              subtitle: course.teacher,
              location: course.place,
              statusLabel: '',
              upstreamStatus: AgendaUpstreamStatus(
                feature: AgendaFeature.schedule,
                completed: false,
              ),
              navigation: AgendaNavigation(
                feature: AgendaFeature.schedule,
                term: storeTerm,
                week: week,
                courseCode: course.code,
                day: course.day,
                section: course.begin,
              ),
              homeTodo: false,
            ),
            timing: timing,
            sortTime: start,
            soon: false,
            completed: false,
            hidden: false,
          ),
        );
      }
    }
    entries.addAll([
      for (final assignment in storeAssignments)
        if (inRange(storeDateKey(assignment.date)))
          storeAssignmentAgenda(assignment),
      for (final exam in storeExams)
        if (inRange(storeDateKey(exam.date))) _examAgenda(exam),
    ]);
    for (final item in _personal()) {
      final start = item.start, due = item.due;
      final day = (start ?? due)!.rfc3339.substring(0, 10);
      if (!inRange(day)) continue;
      final timing = item.kind == AgendaKind.task
          ? AgendaTiming(kind: AgendaTimingKind.deadline, due: due)
          : AgendaTiming(
              kind: AgendaTimingKind.period,
              start: start,
              end: item.end,
            );
      entries.add(
        AgendaEntry(
          local: AgendaOccurrence(
            itemId: item.title,
            recurrenceId: (start ?? due)!.rfc3339,
            content: item,
            overridden: false,
          ),
          timing: timing,
          sortTime: start ?? due,
          soon: false,
          completed: false,
          hidden: false,
        ),
      );
    }
    entries.sort((a, b) => a.sortTime!.rfc3339.compareTo(b.sortTime!.rfc3339));
    return AgendaQueryResult(
      entries: entries,
      sources: [
        for (final (feature, kind) in const [
          (AgendaFeature.schedule, AgendaCacheKind.scheduleWeek),
          (AgendaFeature.spoc, AgendaCacheKind.spocTerm),
          (AgendaFeature.exam, AgendaCacheKind.exams),
        ])
          AgendaSource(
            feature: feature,
            observations: [_observed(query.route, kind)],
            missingScopes: const [],
            unprojectableCount: 0,
          ),
      ],
    );
  }

  List<AgendaContent> _personal() {
    final tuesday = storeDate(storeWeek, 2);
    final wednesday = storeDate(storeWeek, 3);
    final thursday = storeDate(storeWeek, 4);
    final friday = storeDate(storeWeek, 5);
    final saturday = storeDate(storeWeek, 6);
    AgendaContent event(
      String title,
      DateTime day,
      String start,
      String end, {
      String? location,
      required String color,
    }) => AgendaContent(
      kind: AgendaKind.event,
      title: title,
      location: location,
      color: color,
      start: _time(day, start),
      end: _time(day, end),
      allDay: false,
    );
    return [
      event(
        '项目组会',
        tuesday,
        '16:00',
        '17:30',
        location: '新主楼F座 研讨室',
        color: '#7B5EA7',
      ),
      event(
        '羽毛球约练',
        thursday,
        '19:00',
        '20:30',
        location: '体育馆',
        color: '#2E7D4F',
      ),
      event(
        '社团例会',
        wednesday,
        '12:15',
        '13:15',
        location: '学生活动中心',
        color: '#D9822B',
      ),
      event(
        '图书馆自习',
        saturday,
        '09:00',
        '11:30',
        location: '图书馆',
        color: '#476FBD',
      ),
      AgendaContent(
        kind: AgendaKind.task,
        title: '提交奖学金申请材料',
        color: '#C2185B',
        due: _time(friday, '17:00'),
        allDay: false,
      ),
    ];
  }

  @override
  Future<AgendaItem> create(AgendaDraft draft, AgendaTime now) => _readOnly();

  @override
  Future<AgendaItem?> get(String itemId) async => null;

  @override
  Future<String?> edit(
    String itemId,
    AgendaEditScope scope,
    AgendaTime? at,
    AgendaContent content,
    String? rrule,
    AgendaTime now,
  ) => _readOnly();

  @override
  Future<void> delete(
    String itemId,
    AgendaEditScope scope,
    AgendaTime? at,
    AgendaTime now,
  ) => _readOnly();

  @override
  Future<void> complete(
    String itemId,
    AgendaTime? at,
    bool completed,
    AgendaTime now,
  ) => _readOnly();

  @override
  Future<void> setOverlay(AgendaOverlayDraft value, AgendaTime now) =>
      _readOnly();

  @override
  Future<AgendaOverlay?> overlay(SchoolAgendaKey key) async => null;

  @override
  Future<void> clearOverlay(SchoolAgendaKey key, AgendaTime now) => _readOnly();

  @override
  Future<int> unsyncedCount() async => 0;

  @override
  Future<int> clearLocalData() => _readOnly();

  @override
  Future<TeachingWeekRule> teachingWeekRule(TeachingWeekInput input) =>
      _readOnly();

  Future<T> _readOnly<T>() =>
      Future.error(const AgendaException(AgendaFailure.unavailable));
}

AgendaObservation _observed(ConnectionMode route, AgendaCacheKind kind) {
  final capturedAt = storeNow.millisecondsSinceEpoch ~/ 1000;
  return AgendaObservation(
    scope: AgendaCacheScope(
      route: route,
      kind: kind,
      term: storeTerm,
      week: kind == AgendaCacheKind.scheduleWeek ? storeWeek : null,
    ),
    fetchedAt: capturedAt,
    lastVerifiedAt: capturedAt,
    lastAttemptAt: capturedAt,
    lastAttemptSucceeded: true,
    completeness: AgendaCompleteness.complete,
  );
}

AgendaEntry storeAssignmentAgenda(StoreAssignment assignment) {
  final due = _time(assignment.date, assignment.dueTime);
  final timing = AgendaTiming(kind: AgendaTimingKind.deadline, due: due);
  return AgendaEntry(
    school: SchoolAgendaItem(
      key: SchoolAgendaKey(source: 'spoc', upstreamId: assignment.id),
      timing: timing,
      sortTime: due,
      title: assignment.title,
      subtitle: assignment.course.name,
      statusLabel: assignment.statusLabel,
      upstreamStatus: AgendaUpstreamStatus(
        feature: AgendaFeature.spoc,
        completed: assignment.submitted,
        submission: assignment.submitted
            ? AgendaSubmission.submitted
            : AgendaSubmission.unsubmitted,
      ),
      navigation: AgendaNavigation(
        feature: AgendaFeature.spoc,
        assignmentId: assignment.id,
      ),
      homeTodo: !assignment.submitted,
    ),
    timing: timing,
    sortTime: due,
    soon:
        !assignment.submitted &&
        DateTime.parse(due.rfc3339).difference(storeNow) <=
            const Duration(days: 2),
    completed: assignment.submitted,
    hidden: false,
  );
}

AgendaEntry _examAgenda(StoreExam exam) {
  final start = _time(exam.date, exam.startTime);
  final timing = AgendaTiming(
    kind: AgendaTimingKind.period,
    start: start,
    end: _time(exam.date, exam.endTime),
  );
  return AgendaEntry(
    school: SchoolAgendaItem(
      key: SchoolAgendaKey(
        source: 'exam',
        upstreamId: 'exam-${exam.courseCode}',
      ),
      timing: timing,
      sortTime: start,
      title: exam.title,
      subtitle: '闭卷 · 座位 ${exam.seat}',
      location: exam.place,
      statusLabel: '待考试',
      upstreamStatus: AgendaUpstreamStatus(
        feature: AgendaFeature.exam,
        completed: false,
      ),
      navigation: AgendaNavigation(
        feature: AgendaFeature.exam,
        term: storeTerm,
        courseNo: exam.courseCode,
        taskId: 'exam-${exam.courseCode}',
        date: storeDateKey(exam.date),
        startTime: exam.startTime,
      ),
      homeTodo: false,
    ),
    timing: timing,
    sortTime: start,
    soon: false,
    completed: false,
    hidden: false,
  );
}

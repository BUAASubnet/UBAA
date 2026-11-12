import 'package:test/test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('博雅按校园时区检查交集，相邻边界不冲突，跨日保留实际时段', () {
    final course = BykcCourseInterval.parse(
      '2026-11-18 23:30:00',
      '2026-11-19 01:00:00',
    )!;
    expect(course.start.toIso8601String(), '2026-11-18T15:30:00.000Z');
    final entries = [
      event('前项', '2026-11-18T22:00:00+08:00', '2026-11-18T23:30:00+08:00'),
      event('相交', '2026-11-18T16:00:00Z', '2026-11-18T18:00:00Z'),
      event('后项', '2026-11-19T01:00:00+08:00', '2026-11-19T02:00:00+08:00'),
    ];
    expect(
      bykcAgendaConflicts(
        course,
        entries,
        courseId: 42,
      ).map((e) => e.local!.content.title),
      ['相交'],
    );
  });
  test('全天自建事件占用日期，截止待办、已完成、隐藏和课程自身不冲突', () {
    final course = BykcCourseInterval.parse(
      '2026-11-18 14:00:00',
      '2026-11-18 16:00:00',
    )!;
    final allDay = event(
      '全天',
      '2026-11-18T00:00:00+08:00',
      '2026-11-19T00:00:00+08:00',
      allDay: true,
    );
    final entries = [
      allDay,
      event(
        '已完成',
        '2026-11-18T14:00:00+08:00',
        '2026-11-18T15:00:00+08:00',
        completed: true,
      ),
      event(
        '已隐藏',
        '2026-11-18T14:00:00+08:00',
        '2026-11-18T15:00:00+08:00',
        hidden: true,
      ),
      event(
        '待办',
        '2026-11-18T14:00:00+08:00',
        '2026-11-18T15:00:00+08:00',
        task: true,
      ),
      school(42, course),
      school(43, course),
      school(44, course, unknownTime: true),
    ];
    expect(bykcAgendaConflicts(course, entries, courseId: 42), [
      allDay,
      entries[5],
    ]);
    final tomorrow = BykcCourseInterval.parse(
      '2026-11-19 00:00:00',
      '2026-11-19 01:00:00',
    )!;
    expect(bykcAgendaConflicts(tomorrow, [allDay], courseId: 42), isEmpty);
  });
  test('课程缺时间、日期无效和倒置时段保持未知', () {
    for (final (start, end) in [
      (null, null),
      ('2026-11-18', '2026-11-19'),
      ('错误', '2026-11-19 16:00:00'),
      ('2026-11-18 25:00:00', '2026-11-19 16:00:00'),
      ('2026-02-30 14:00:00', '2026-03-03 16:00:00'),
      ('2026-11-18 16:00:00', '2026-11-18 14:00:00'),
    ]) {
      expect(BykcCourseInterval.parse(start, end), isNull);
    }
  });
}

AgendaEntry event(
  String title,
  String start,
  String end, {
  bool allDay = false,
  bool completed = false,
  bool hidden = false,
  bool task = false,
}) {
  final a = AgendaTime(rfc3339: start, timezone: 'Asia/Shanghai');
  final b = AgendaTime(rfc3339: end, timezone: 'Asia/Shanghai');
  return AgendaEntry(
    local: AgendaOccurrence(
      itemId: title,
      recurrenceId: start,
      content: AgendaContent(
        kind: task ? AgendaKind.task : AgendaKind.event,
        title: title,
        start: a,
        end: b,
        allDay: allDay,
      ),
      overridden: false,
    ),
    timing: AgendaTiming(
      kind: task
          ? AgendaTimingKind.deadline
          : allDay
          ? AgendaTimingKind.allDay
          : AgendaTimingKind.period,
      start: a,
      end: b,
      from: start.substring(0, 10),
      to: end.substring(0, 10),
      due: a,
    ),
    soon: false,
    completed: completed,
    hidden: hidden,
  );
}

AgendaEntry school(
  int id,
  BykcCourseInterval interval, {
  bool unknownTime = false,
}) {
  final timing = AgendaTiming(
    kind: unknownTime ? AgendaTimingKind.allDay : AgendaTimingKind.period,
    start: AgendaTime(
      rfc3339: interval.start.toIso8601String(),
      timezone: 'Asia/Shanghai',
    ),
    end: AgendaTime(
      rfc3339: interval.end.toIso8601String(),
      timezone: 'Asia/Shanghai',
    ),
    from: '2026-11-18',
    to: '2026-11-19',
  );
  return AgendaEntry(
    school: SchoolAgendaItem(
      key: SchoolAgendaKey(source: 'bykc', upstreamId: '$id'),
      timing: timing,
      title: '博雅$id',
      subtitle: '',
      statusLabel: '',
      upstreamStatus: AgendaUpstreamStatus(
        feature: AgendaFeature.bykc,
        completed: false,
      ),
      navigation: AgendaNavigation(
        feature: AgendaFeature.bykc,
        bykcCourseId: id,
      ),
      homeTodo: true,
    ),
    timing: timing,
    soon: false,
    completed: false,
    hidden: false,
  );
}

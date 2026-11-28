import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/agenda/home_card.dart';

AgendaTime _time(String raw) =>
    AgendaTime(rfc3339: raw, timezone: 'Asia/Shanghai');

AgendaEntry _local({
  required String title,
  required AgendaTimingKind kind,
  String? start,
  String? end,
  String? due,
  String? location,
  bool completed = false,
  bool hidden = false,
}) => AgendaEntry(
  local: AgendaOccurrence(
    itemId: title,
    recurrenceId: start ?? due ?? 'undated',
    content: AgendaContent(
      kind: AgendaKind.event,
      title: title,
      location: location,
      allDay: kind == AgendaTimingKind.allDay,
    ),
    overridden: false,
  ),
  timing: AgendaTiming(
    kind: kind,
    start: start == null ? null : _time(start),
    end: end == null ? null : _time(end),
    due: due == null ? null : _time(due),
  ),
  soon: false,
  completed: completed,
  hidden: hidden,
);

AgendaEntry _school({
  required String title,
  required AgendaFeature feature,
  required AgendaTimingKind kind,
  String? start,
  String? end,
  String? due,
}) => AgendaEntry(
  school: SchoolAgendaItem(
    key: SchoolAgendaKey(source: feature.name, upstreamId: title),
    timing: AgendaTiming(
      kind: kind,
      start: start == null ? null : _time(start),
      end: end == null ? null : _time(end),
      due: due == null ? null : _time(due),
    ),
    title: title,
    subtitle: '',
    statusLabel: '',
    upstreamStatus: AgendaUpstreamStatus(feature: feature, completed: false),
    navigation: AgendaNavigation(feature: feature),
    homeTodo: false,
  ),
  timing: AgendaTiming(
    kind: kind,
    start: start == null ? null : _time(start),
    end: end == null ? null : _time(end),
    due: due == null ? null : _time(due),
  ),
  soon: false,
  completed: false,
  hidden: false,
);

void main() {
  final now = DateTime(2026, 11, 27, 8, 30);

  test('按日程、作业、待办分类并只保留今天日程', () {
    final snapshot = buildHomeCardSnapshot(
      [
        _local(
          title: '下午课',
          kind: AgendaTimingKind.period,
          start: '2026-11-27T14:00:00+08:00',
          end: '2026-11-27T15:40:00+08:00',
          location: '主楼 101',
        ),
        _local(
          title: '早课',
          kind: AgendaTimingKind.period,
          start: '2026-11-27T08:00:00+08:00',
          end: '2026-11-27T09:40:00+08:00',
        ),
        _local(
          title: '明天的课',
          kind: AgendaTimingKind.period,
          start: '2026-11-28T08:00:00+08:00',
          end: '2026-11-28T09:40:00+08:00',
        ),
        _local(
          title: '已完成的课',
          kind: AgendaTimingKind.period,
          start: '2026-11-27T10:00:00+08:00',
          end: '2026-11-27T11:40:00+08:00',
          completed: true,
        ),
        _local(
          title: '隐藏的课',
          kind: AgendaTimingKind.period,
          start: '2026-11-27T12:00:00+08:00',
          end: '2026-11-27T13:00:00+08:00',
          hidden: true,
        ),
        _school(
          title: '希冀作业',
          feature: AgendaFeature.judge,
          kind: AgendaTimingKind.deadline,
          due: '2026-11-27T23:59:00+08:00',
        ),
        _school(
          title: 'SPOC 作业',
          feature: AgendaFeature.spoc,
          kind: AgendaTimingKind.deadline,
          due: '2026-11-28T23:59:00+08:00',
        ),
        _local(
          title: '今天的待办',
          kind: AgendaTimingKind.deadline,
          due: '2026-11-27T20:00:00+08:00',
        ),
        _local(title: '无日期待办', kind: AgendaTimingKind.undated),
        _school(
          title: '博雅报名',
          feature: AgendaFeature.bykc,
          kind: AgendaTimingKind.deadline,
          due: '2026-11-27T18:00:00+08:00',
        ),
        _local(
          title: '已完成待办',
          kind: AgendaTimingKind.deadline,
          due: '2026-11-27T20:00:00+08:00',
          completed: true,
        ),
      ],
      now: now,
      signedIn: true,
    );

    expect(snapshot.campusDay, '2026-11-27');
    expect(snapshot.dateLabel, '11月27日 周五');
    expect(snapshot.signedIn, isTrue);
    expect(snapshot.agenda.map((item) => item.title), ['早课', '下午课']);
    expect(snapshot.agenda.first.time, '08:00–09:40');
    expect(snapshot.agenda.last.location, '主楼 101');
    expect(snapshot.homework.map((item) => item.title), ['希冀作业', 'SPOC 作业']);
    expect(snapshot.homework.first.time, '今天 23:59');
    expect(snapshot.homework.last.time, '明天 23:59');
    expect(snapshot.todo.map((item) => item.title), ['博雅报名', '今天的待办', '无日期待办']);
    expect(snapshot.todo.last.time, '无截止');
  });

  test('按本周开始时间生成课程表行并合并同格课程', () {
    final snapshot = buildHomeCardSnapshot(
      [
        _local(
          title: '周一课 A',
          kind: AgendaTimingKind.period,
          start: '2026-11-23T08:00:00+08:00',
          end: '2026-11-23T09:40:00+08:00',
          location: '主楼 101',
        ),
        _local(
          title: '周一课 B',
          kind: AgendaTimingKind.period,
          start: '2026-11-23T08:00:00+08:00',
          end: '2026-11-23T09:40:00+08:00',
        ),
        _local(
          title: '周三课',
          kind: AgendaTimingKind.period,
          start: '2026-11-25T14:00:00+08:00',
          end: '2026-11-25T15:40:00+08:00',
        ),
        _local(
          title: '周六课',
          kind: AgendaTimingKind.period,
          start: '2026-11-28T10:00:00+08:00',
          end: '2026-11-28T11:40:00+08:00',
        ),
        _local(
          title: '下周课',
          kind: AgendaTimingKind.period,
          start: '2026-11-30T08:00:00+08:00',
          end: '2026-11-30T09:40:00+08:00',
        ),
        _local(
          title: '已完成的课',
          kind: AgendaTimingKind.period,
          start: '2026-11-24T08:00:00+08:00',
          end: '2026-11-24T09:40:00+08:00',
          completed: true,
        ),
      ],
      now: now,
      signedIn: true,
    );

    expect(snapshot.weekLabel, '11.23–11.29');
    expect(snapshot.todayWeekday, 5);
    expect(snapshot.weekRows.map((row) => row.time), [
      '08:00',
      '10:00',
      '14:00',
    ]);
    expect(snapshot.weekRows.first.cells[0].title, '周一课 A / 周一课 B');
    expect(snapshot.weekRows.first.cells[0].time, '09:40');
    expect(snapshot.weekRows.first.cells[0].location, '主楼 101');
    expect(snapshot.weekRows.first.cells[1].isEmpty, isTrue);
    expect(snapshot.weekRows[1].cells[5].title, '周六课');
    expect(snapshot.weekRows[1].cells[6].isEmpty, isTrue);
    expect(snapshot.weekRows[2].cells[2].title, '周三课');
    expect(
      snapshot.weekRows
          .expand((row) => row.cells)
          .every((cell) => cell.title != '下周课' && cell.title != '已完成的课'),
      isTrue,
    );
  });

  test('结束时间缺失只显示开始时间，未登录快照为空', () {
    expect(
      homeCardTime(
        AgendaTiming(
          kind: AgendaTimingKind.period,
          start: _time('2026-11-27T16:00:00+08:00'),
        ),
      ),
      '16:00',
    );
    final snapshot = buildHomeCardSnapshot(
      [
        _local(
          title: '时间待定',
          kind: AgendaTimingKind.period,
          start: '2026-11-27T16:00:00+08:00',
        ),
      ],
      now: now,
      signedIn: false,
    );

    expect(snapshot.signedIn, isFalse);
    expect(snapshot.agenda, isEmpty);
    expect(snapshot.homework, isEmpty);
    expect(snapshot.todo, isEmpty);
  });
}

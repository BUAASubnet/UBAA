import 'dart:convert';
import 'package:ubaa_domain/ubaa_domain.dart';

const owner = '虚构 账号';
const term = '合成学期';
final monday = DateTime.utc(2026, 11, 16);
DateTime wall(int day, [int hour = 0, int minute = 0]) =>
    monday.add(Duration(days: day, hours: hour, minutes: minute));
DateTime instant(DateTime wallTime) =>
    wallTime.subtract(const Duration(hours: 8));
int seconds(DateTime wallTime) =>
    instant(wallTime).millisecondsSinceEpoch ~/ 1000;
AgendaTime? time(DateTime? value) => value == null
    ? null
    : AgendaTime(
        rfc3339: instant(value).toIso8601String(),
        timezone: 'Asia/Shanghai',
      );
const route = ConnectionMode.direct;
AgendaEntry event(
  String title,
  AgendaFeature? feature, {
  DateTime? start,
  DateTime? end,
  DateTime? due,
  DateTime? allDay,
  String? place,
  bool homeTodo = true,
  bool hidden = false,
  bool completed = false,
  AgendaSubmission? submission,
  int? bykcId = 7,
}) {
  final timing = AgendaTiming(
    kind: allDay != null
        ? AgendaTimingKind.allDay
        : due != null
        ? AgendaTimingKind.deadline
        : AgendaTimingKind.period,
    start: time(start),
    end: time(end),
    due: time(due),
    from: allDay == null ? null : homeDateKey(allDay),
    to: allDay == null
        ? null
        : homeDateKey(allDay.add(const Duration(days: 1))),
  );
  return AgendaEntry(
    timing: timing,
    soon: false,
    completed: completed,
    hidden: hidden,
    local: feature != null
        ? null
        : AgendaOccurrence(
            itemId: title,
            recurrenceId: title,
            overridden: false,
            content: AgendaContent(
              kind: due == null ? AgendaKind.event : AgendaKind.task,
              title: title,
              location: place,
              allDay: allDay != null,
            ),
          ),
    school: feature == null
        ? null
        : SchoolAgendaItem(
            key: SchoolAgendaKey(source: feature.name, upstreamId: title),
            timing: timing,
            title: title,
            subtitle: place ?? '考场待定',
            location: place,
            statusLabel: '',
            upstreamStatus: AgendaUpstreamStatus(
              feature: feature,
              completed: false,
              submission: submission,
            ),
            navigation: AgendaNavigation(
              feature: feature,
              term: term,
              bykcCourseId: bykcId,
              courseId: '课程甲',
              assignmentId: '作业甲',
              date: homeDateKey(start ?? allDay ?? end ?? due!),
            ),
            homeTodo: homeTodo,
          ),
  );
}

List<WeekPresentation> weeks([int first = 0, int count = 4]) => [
  for (var index = 0; index < count; index++)
    WeekPresentation(
      requestTerm: term,
      responseTerm: term,
      number: index + 1,
      current: index == 0,
      startDate: homeDateKey(wall(first + 7 * index)),
      endDate: homeDateKey(wall(first + 7 * index + 6)),
    ),
];
AgendaObservation observed(
  AgendaCacheScope scope, {
  int? verified,
  int? attempt,
  bool success = true,
}) => AgendaObservation(
  scope: scope,
  fetchedAt: seconds(wall(-3)),
  lastVerifiedAt: verified ?? seconds(wall(-2, 20, 30)),
  lastAttemptAt: attempt ?? seconds(wall(-2, 20, 30)),
  lastAttemptSucceeded: success,
  completeness: AgendaCompleteness.complete,
);
AgendaSource coverage(int count) => AgendaSource(
  feature: AgendaFeature.schedule,
  observations: [
    for (var number = 1; number <= count; number++)
      observed(
        AgendaCacheScope(
          route: route,
          kind: AgendaCacheKind.scheduleWeek,
          term: term,
          week: number,
        ),
      ),
  ],
  missingScopes: [],
  unprojectableCount: 0,
);
AgendaSource freshness(DateTime at) => AgendaSource(
  feature: AgendaFeature.judge,
  observations: [
    observed(
      AgendaCacheScope(route: route, kind: AgendaCacheKind.judgeSummaries),
      attempt: seconds(at),
    ),
  ],
  missingScopes: [],
  unprojectableCount: 0,
);
List<AgendaEntry> example() => [
  event(
    '高等数学',
    AgendaFeature.schedule,
    start: wall(0, 8),
    end: wall(0, 8, 45),
    place: '主楼 A201',
  ),
  event(
    '高等数学',
    AgendaFeature.schedule,
    start: wall(0, 8, 55),
    end: wall(0, 9, 35),
    place: '主楼 A201',
  ),
  event(
    '大学英语',
    AgendaFeature.schedule,
    start: wall(0, 10, 10),
    end: wall(0, 11, 45),
    place: '教一 B305',
  ),
  event(
    '研讨室预约',
    AgendaFeature.cgyy,
    start: wall(0, 14),
    end: wall(0, 16),
    place: '研讨室 305',
  ),
  event(
    '博雅讲座',
    AgendaFeature.bykc,
    start: wall(0, 19),
    end: wall(0, 21),
    place: '学术交流厅',
  ),
  event(
    '线性代数',
    AgendaFeature.schedule,
    start: wall(1, 8),
    end: wall(1, 9, 35),
    place: '主楼 A201',
  ),
];
Map<String, dynamic> snapshot(
  List<AgendaEntry> entries, {
  DateTime? build,
  List<WeekPresentation>? index,
  List<AgendaSource>? sources,
  List<Map<String, Object?>> semesters = const [],
  CacheMaintenanceFailure? failure,
}) => buildWidgetSnapshot(
  owner: owner,
  semesters: semesters,
  now: instant(build ?? monday),
  term: term,
  weeks: index ?? weeks(),
  agenda: AgendaQueryResult(
    entries: entries,
    sources: sources ?? [coverage(4)],
    schoolCacheFailure: failure,
  ),
).toJson().cast<String, dynamic>();
Map segment(Map data, String table, DateTime at) => (data[table] as List)
    .cast<Map>()
    .lastWhere((row) => row['from'] <= seconds(at));
Map widgetFixture() => snapshot(
  [
    ...example(),
    event('合成考试', AgendaFeature.exam, allDay: wall(1)),
    event('合成作业', AgendaFeature.judge, due: wall(0, 17)),
    event('合成待办', null, due: wall(3, 19)),
  ],
  semesters: [
    {
      'term': term,
      'name': '合成秋季学期',
      'updatedAt': '2026-11-15T12:30:00.000Z',
      'weeks': [
        {
          'number': 1,
          'name': '第一周',
          'start': '2026-11-16',
          'end': '2026-11-22',
          'courses': [
            {
              'name': '高等数学',
              'day': 1,
              'begin': 1,
              'end': 2,
              'startTime': '08:00',
              'endTime': '09:35',
              'place': '主楼 A201',
              'weeksAndTeachers': null,
            },
          ],
          'times': [
            {'section': 1, 'start': '08:00', 'end': '08:45'},
            {'section': 2, 'start': '08:55', 'end': '09:35'},
          ],
        },
      ],
    },
  ],
  index: weeks(0, 1),
  sources: [coverage(1), freshness(wall(-1, 20, 30))],
);

void main() =>
    print(const JsonEncoder.withIndent('  ').convert(widgetFixture()));

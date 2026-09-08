import 'package:test/test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

final now = DateTime(2026, 3, 24, 12);
FeatureSnapshot source(
  FeatureId feature,
  List<FeatureDetail> details, {
  FeatureLoadStatus status = FeatureLoadStatus.success,
  FeatureQueryView? view,
  FeatureOverview? overview,
}) => FeatureSnapshot(
  feature: feature,
  status: status,
  details: details,
  overview: overview,
  resolvedRoute: ConnectionMode.direct,
  readContext: FeatureReadContext(
    requestRevision: 1,
    query: view == null ? null : FeatureQuery(view: view),
  ),
);
FeatureDetail bykc(int id, String? start, String? end) => FeatureDetail(
  title: '合成博雅 $id',
  presentation: BykcChosenPresentation(
    recordId: id,
    courseId: id + 100,
    courseName: '合成博雅 $id',
    courseStartDate: start,
    courseEndDate: end,
  ),
);
FeatureDetail room(
  int id, {
  String? end = '2026-03-24 15:00',
  int? status = 1,
  int? check = 2,
}) => FeatureDetail(
  title: '合成研讨室',
  presentation: CgyyOrderPresentation(
    id: id,
    statusText: '合成状态',
    venueName: '合成楼',
    venueSpaceName: '合成房间',
    reservationStartDate: '2026-03-24 13:30',
    reservationEndDate: end,
    orderStatus: status,
    checkStatus: check,
  ),
);
FeatureDetail signin(
  String id,
  String start,
  String end, {
  int? state = 0,
  bool action = true,
}) => FeatureDetail(
  title: '合成签到 $id',
  presentation: SigninPresentation(
    courseId: id,
    classBeginTime: start,
    classEndTime: end,
    signStatus: state,
  ),
  actions: [
    if (action)
      SigninPerformAction(
        scheduleId: id,
        eligibility: ActionEligibility.allowed,
      ),
  ],
);
FeatureSnapshot sunlight({int? week = 3, int term = 15}) => source(
  FeatureId.ygdk,
  [],
  overview: YgdkOverview(
    termCount: term,
    weekCount: week,
    classifyId: 3,
    classifyName: '合成体育',
    defaultItemId: 1,
    defaultItemName: '合成项目',
  ),
);
WeekPresentation week(int n) => WeekPresentation(
  requestTerm: 'synthetic-term',
  responseTerm: 'synthetic-term',
  number: n,
  current: true,
  startDate: '2026-03-23',
  endDate: '2026-03-29',
);
void main() {
  test('后台刷新保留已显示待办但暂停原签到动作', () {
    final loading = source(
      FeatureId.signin,
      [signin('refresh', '12:05', '13:00')],
      status: FeatureLoadStatus.loading,
    ).copyWith(updatedAt: DateTime(2026, 3, 24, 11, 59));
    final items = buildHomeTodos(
      now: now,
      snapshots: {FeatureId.signin: loading},
    );
    expect(items, hasLength(1));
    expect(items.single.signinAction, isNull);
  });

  test('六来源按旧时间混合排序并保留原始详情参数', () {
    final items = buildHomeTodos(
      now: now,
      currentWeek: week(11),
      snapshots: {
        FeatureId.bykc: source(FeatureId.bykc, [
          bykc(1, '2026-03-24 11:00', '2026-03-24 13:00'),
        ], view: FeatureQueryView.bykcChosenCourses),
        FeatureId.signin: source(FeatureId.signin, [
          signin('s1', '11:55', '12:45'),
        ]),
        FeatureId.judge: source(FeatureId.judge, [
          FeatureDetail(
            title: '合成希冀',
            presentation: JudgeAssignmentPresentation(
              courseId: 'j-c',
              courseName: '合成课',
              assignmentId: 'j-a',
              dueTime: '2026-03-24 12:20',
              totalProblems: 2,
              submittedCount: 1,
              status: AssignmentSubmissionStatus.partial,
              statusText: '部分完成',
            ),
          ),
        ]),
        FeatureId.spoc: source(FeatureId.spoc, [
          const FeatureDetail(
            title: '合成SPOC',
            presentation: SpocAssignmentPresentation(
              courseId: 's-c',
              courseName: '合成课',
              assignmentId: 's-a',
              dueTime: '2026-03-24 12:30',
              status: AssignmentSubmissionStatus.unsubmitted,
              statusText: '未提交',
            ),
          ),
        ]),
        FeatureId.cgyy: source(FeatureId.cgyy, [
          room(1),
        ], view: FeatureQueryView.cgyyOrders),
        FeatureId.ygdk: sunlight(),
      },
    );
    expect(items.map((e) => e.feature), [
      FeatureId.bykc,
      FeatureId.signin,
      FeatureId.judge,
      FeatureId.spoc,
      FeatureId.cgyy,
      FeatureId.ygdk,
    ]);
    expect(items[0].navigation!.query.courseId, '101');
    expect(items[1].signinAction!.scheduleId, 's1');
    expect(items[2].navigation!.query.courseId, 'j-c');
    expect(items[2].navigation!.query.assignmentId, 'j-a');
    expect(items[2].statusLabel, '待完成');
    expect(items[3].statusLabel, '待提交');
    expect(items.last.sortTime, DateTime(2026, 3, 29, 23, 59, 59));
  });
  test('博雅结束时刻保留、研讨室结束时刻与拒绝取消排除', () {
    final items = buildHomeTodos(
      now: now,
      snapshots: {
        FeatureId.bykc: source(FeatureId.bykc, [
          bykc(1, '2026-03-24 11:00', '2026-03-24 12:00'),
          bykc(2, null, null),
          bykc(3, null, '2026-03-24 11:59'),
        ], view: FeatureQueryView.bykcChosenCourses),
        FeatureId.cgyy: source(FeatureId.cgyy, [
          room(1, end: '2026-03-24 12:00'),
          room(2, status: 2),
          room(3, check: -1),
          room(4),
        ], view: FeatureQueryView.cgyyOrders),
      },
    );
    expect(items.map((e) => e.id), ['bykc:101', 'cgyy:4']);
  });
  test('签到开始前十分钟和结束边界，状态未知或缺资格不伪造动作', () {
    final items = buildHomeTodos(
      now: now,
      snapshots: {
        FeatureId.signin: source(FeatureId.signin, [
          signin('visible', '12:10', '13:00'),
          signin('early', '12:11', '13:00'),
          signin('ended', '11:00', '12:00'),
          signin('unknown', '12:05', '13:00', state: null),
          signin('no-action', '12:05', '13:00', action: false),
          signin('bad-time', '25:00', '26:00'),
        ]),
      },
    );
    expect(items.map((e) => e.id), ['signin:no-action', 'signin:visible']);
    expect(items.first.signinAction, isNull);
    expect(items.last.statusLabel, '即将签到');
    final stale = buildHomeTodos(
      now: now,
      snapshots: {
        FeatureId.signin: source(FeatureId.signin, [
          signin('stale', '12:05', '13:00'),
        ], status: FeatureLoadStatus.stale),
      },
    );
    expect(stale.single.signinAction, isNull);
  });
  test('阳光旧提醒只在11到14周且未达4和16，不把缺数据当零', () {
    List<HomeTodo> items({
      int n = 11,
      int? count = 3,
      int term = 15,
      bool enabled = true,
      bool done = false,
      bool termDone = false,
    }) => buildHomeTodos(
      now: now,
      currentWeek: week(n),
      ygdkReminderEnabled: enabled,
      ygdkWeekDone: done,
      ygdkTermDone: termDone,
      snapshots: {FeatureId.ygdk: sunlight(week: count, term: term)},
    );
    expect(items(n: 14), hasLength(1));
    for (final value in [
      items(n: 10),
      items(n: 15),
      items(count: null),
      items(count: 4),
      items(term: 16),
      items(enabled: false),
      items(done: true),
      items(termDone: true),
    ]) {
      expect(value, isEmpty);
    }
  });
  test('错误和其他查询不能变成首页来源，日期溢出不归一化', () {
    final items = buildHomeTodos(
      now: now,
      snapshots: {
        FeatureId.bykc: source(FeatureId.bykc, [
          bykc(1, '2026-03-24 13:00', null),
        ], view: FeatureQueryView.bykcDetail),
        FeatureId.cgyy: source(
          FeatureId.cgyy,
          [room(1)],
          view: FeatureQueryView.cgyyOrders,
          status: FeatureLoadStatus.failure,
        ),
        FeatureId.spoc: source(FeatureId.spoc, [
          const FeatureDetail(
            title: '无效日期',
            presentation: SpocAssignmentPresentation(
              courseId: 'c',
              courseName: '合成',
              assignmentId: 'a',
              dueTime: '2026-03-99 12:00',
              status: AssignmentSubmissionStatus.unsubmitted,
              statusText: '未交',
            ),
          ),
        ]),
      },
    );
    expect(items, isEmpty);
  });
}

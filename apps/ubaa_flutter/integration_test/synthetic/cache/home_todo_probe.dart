import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_app/src/bridge/home/agenda.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

final now = DateTime.parse('2026-03-24T12:00:00+08:00');
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
    actionTarget: id,
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
Future<void> probeHomeTodos(String directory) async {
  await scenario('首页考试按开始时间排序且仅保留未结束已安排考试', () async {
    FeatureDetail exam(
      String title,
      String date,
      String? start,
      String? end, {
      bool arranged = true,
    }) => FeatureDetail(
      title: title,
      presentation: ExamPresentation(
        arranged: arranged,
        date: date,
        startTime: start,
        endTime: end,
        place: '合成考场',
        seat: '12',
        taskId: title,
      ),
    );
    final tasks = (await projectTodos(
      now: now,
      snapshots: {
        FeatureId.exam: source(FeatureId.exam, [
          exam('明天考试', '2026-03-25', '09:00', '11:00'),
          exam('已结束', '2026-03-24', '08:00', '10:00'),
          exam('进行中', '2026-03-24', '11:00', '13:00'),
          exam('未安排', '2026-03-24', '13:00', '15:00', arranged: false),
          exam('日期错误', '2026-02-30', '13:00', '15:00'),
          exam('时间待定', '2026-03-26', null, null),
        ]),
      },
    ));
    expect(tasks.map((t) => t.title), ['进行中', '明天考试', '时间待定']);
    expect(tasks.first.statusLabel, '考试中');
    expect(tasks[1].statusLabel, '待考试');
    expect(tasks.first.subtitle, contains('合成考场'));
    expect(tasks.first.subtitle, contains('12'));
    expect(tasks.first.timeLabel, contains('11:00–13:00'));
    expect(tasks.last.timeLabel, contains('时间待定'));
    expect(tasks.first.navigation?.query.view, FeatureQueryView.examArranged);
    expect(tasks.first.signinAction, isNull);
  });

  await scenario('已保存签到跨日失效，同日仅导航且不能恢复写资格', () async {
    FeatureSnapshot cached(String date) =>
        source(FeatureId.signin, [signin('cache', '12:05', '13:00')]).copyWith(
          evidence: DataEvidence(
            accountId: 'synthetic',
            origin: DataOrigin.persisted,
            fetchedAt: now,
            complete: true,
            savedForOffline: true,
            scopeDate: date,
          ),
        );
    expect(
      (await projectTodos(
        now: now,
        snapshots: {FeatureId.signin: cached('2026-03-23')},
      )),
      isEmpty,
    );
    final today = (await projectTodos(
      now: now,
      snapshots: {FeatureId.signin: cached('2026-03-24')},
    )).single;
    expect(today.signinAction, isNull);
    expect(today.navigation?.query.view, FeatureQueryView.signinPending);
  });
  await scenario('首次阳光部分统计不能把默认零当作未达标依据', () async {
    final partial = sunlight().copyWith(
      evidence: DataEvidence(
        accountId: 'synthetic',
        origin: DataOrigin.online,
        fetchedAt: now,
        complete: false,
        savedForOffline: true,
      ),
    );
    expect(
      (await projectTodos(
        now: now,
        currentWeek: week(11),
        snapshots: {FeatureId.ygdk: partial},
      )),
      isEmpty,
    );
  });

  await scenario('后台刷新保留已显示待办但暂停原签到动作', () async {
    final loading = source(
      FeatureId.signin,
      [signin('refresh', '12:05', '13:00')],
      status: FeatureLoadStatus.loading,
    ).copyWith(updatedAt: DateTime(2026, 3, 24, 11, 59));
    final items = (await projectTodos(
      now: now,
      snapshots: {FeatureId.signin: loading},
    ));
    expect(items, hasLength(1));
    expect(items.single.signinAction, isNull);
  });

  await scenario('六来源按旧时间混合排序并保留原始详情参数', () async {
    final items = (await projectTodos(
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
    ));
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
  await scenario('博雅结束时刻保留、研讨室结束时刻与拒绝取消排除', () async {
    final items = (await projectTodos(
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
    ));
    expect(items.map((e) => e.id), ['bykc:101', 'cgyy:4']);
  });
  await scenario('签到开始前十分钟和结束边界，状态未知或缺资格不伪造动作', () async {
    final items = (await projectTodos(
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
    ));
    expect(items.map((e) => e.id), ['signin:no-action', 'signin:visible']);
    expect(items.first.signinAction, isNull);
    expect(items.last.statusLabel, '即将签到');
    final stale = (await projectTodos(
      now: now,
      snapshots: {
        FeatureId.signin: source(FeatureId.signin, [
          signin('stale', '12:05', '13:00'),
        ], status: FeatureLoadStatus.stale),
      },
    ));
    expect(stale.single.signinAction, isNull);
  });
  await scenario('阳光旧提醒只在11到14周且未达4和16，不把缺数据当零', () async {
    Future<List<HomeTodo>> reminders({
      int n = 11,
      int? count = 3,
      int term = 15,
      bool enabled = true,
      bool done = false,
      bool termDone = false,
    }) async => (await projectTodos(
      now: now,
      currentWeek: week(n),
      ygdkReminderEnabled: enabled,
      ygdkWeekDone: done,
      ygdkTermDone: termDone,
      snapshots: {FeatureId.ygdk: sunlight(week: count, term: term)},
    ));
    expect((await reminders(n: 14)), hasLength(1));
    for (final value in [
      (await reminders(n: 10)),
      (await reminders(n: 15)),
      (await reminders(count: null)),
      (await reminders(count: 4)),
      (await reminders(term: 16)),
      (await reminders(enabled: false)),
      (await reminders(done: true)),
      (await reminders(termDone: true)),
    ]) {
      expect(value, isEmpty);
    }
  });
  await scenario('错误和其他查询不能变成首页来源，日期溢出不归一化', () async {
    final items = (await projectTodos(
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
    ));
    expect(items, isEmpty);
  });
  await scenario('唯一在线目标不符、重复与跨日均撤销签到资格', () async {
    for (final (target, count, observed) in [
      ('wrong', 1, '2026-03-24'),
      ('s', 2, '2026-03-24'),
      ('s', 1, '2026-03-23'),
    ]) {
      final items = await projectTodos(
        now: now,
        snapshots: {
          FeatureId.signin: FeatureSnapshot(
            feature: FeatureId.signin,
            status: FeatureLoadStatus.success,
            resolvedRoute: ConnectionMode.direct,
            evidence: DataEvidence(
              accountId: 'synthetic',
              origin: DataOrigin.online,
              fetchedAt: now,
              complete: true,
              savedForOffline: false,
              scopeDate: observed,
            ),
            details: [
              for (var i = 0; i < count; i++)
                FeatureDetail(
                  title: '合成签到',
                  presentation: const SigninPresentation(
                    courseId: 's',
                    actionTarget: 's',
                    classBeginTime: '12:05',
                    classEndTime: '13:00',
                    signStatus: 0,
                  ),
                  actions: [
                    SigninPerformAction(
                      scheduleId: target,
                      eligibility: ActionEligibility.allowed,
                    ),
                  ],
                ),
            ],
          ),
        },
      );
      expect(items.every((v) => v.signinAction == null), isTrue);
    }
  });
  await scenario('投影使用校园日期且保留截止文案和48小时边界', () async {
    final snapshot = source(FeatureId.spoc, const [
      FeatureDetail(
        title: '临近作业',
        presentation: SpocAssignmentPresentation(
          courseId: 'c',
          courseName: '课',
          assignmentId: 'a',
          dueTime: '2026-03-26 12:00',
          status: AssignmentSubmissionStatus.unsubmitted,
          statusText: '未提交',
        ),
      ),
    ]);
    final at = DateTime.parse('2026-03-24T04:00:00Z');
    expect(
      (await projectTodos(
        now: at,
        snapshots: {FeatureId.spoc: snapshot},
      )).single.soon,
      isTrue,
    );
    expect(
      (await projectTodos(
        now: at.subtract(const Duration(seconds: 1)),
        snapshots: {FeatureId.spoc: snapshot},
      )).single.soon,
      isFalse,
    );
    final tomorrow = await projectTodos(
      now: DateTime.parse('2026-03-25T15:59:00Z'),
      snapshots: {FeatureId.spoc: snapshot},
    );
    expect(tomorrow.single.timeLabel, '明天 12:00 截止');
    final midnight = await projectTodos(
      now: DateTime.parse('2026-03-25T16:00:00Z'),
      snapshots: {FeatureId.spoc: snapshot},
    );
    expect(midnight.single.timeLabel, '今天 12:00 截止');
  });
  await scenario('真实FFI叠加本地重新挂起并保留学校已提交状态', () async {
    final store = await BridgeAgendaStore.open(
      configDir: directory,
      accountId: '00000000000000000000000000000009',
    );
    final context = bridgeHomeAgendaContext(
      HomeTodoRequest(snapshots: const {}, now: now),
    );
    BridgeHomeAgendaInput input(AssignmentSubmissionStatus status) =>
        bridgeHomeAgendaInputs(
          HomeTodoRequest(
            snapshots: {
              FeatureId.spoc: source(FeatureId.spoc, [
                FeatureDetail(
                  title: '可重新挂起',
                  presentation: SpocAssignmentPresentation(
                    courseId: 'c',
                    courseName: '课',
                    assignmentId: 'reopen',
                    dueTime: '2026-03-25 12:00',
                    status: status,
                    statusText: '原始学校状态',
                  ),
                ),
              ]),
            },
            now: now,
          ),
        );
    final initial = await agendaProjectHome(
      values: input(AssignmentSubmissionStatus.unsubmitted),
      context: context,
    );
    final key = initial.single.school!.key;
    expect(
      await store.projectHome(
        values: input(AssignmentSubmissionStatus.submitted),
        context: context,
      ),
      isEmpty,
    );
    await store.setOverlay(
      overlay: BridgeAgendaOverlayDraft(
        key: key,
        completionOverride: true,
        hidden: false,
      ),
      now: context.now,
    );
    final reopened = await store.projectHome(
      values: input(AssignmentSubmissionStatus.submitted),
      context: context,
    );
    expect(
      reopened.single.school!.upstreamStatus.submission,
      BridgeAgendaSubmission.submitted,
    );
    expect(reopened.single.school!.statusLabel, '本地待办');
    await store.setOverlay(
      overlay: BridgeAgendaOverlayDraft(
        key: key,
        completionOverride: true,
        completedAt: context.now,
        hidden: false,
      ),
      now: context.now,
    );
    expect(
      await store.projectHome(
        values: input(AssignmentSubmissionStatus.unsubmitted),
        context: context,
      ),
      isEmpty,
    );
    await store.deactivate();
  });
}

Future<void> scenario(String label, Future<void> Function() body) async {
  await body();
}

Future<List<HomeTodo>> projectTodos({
  required Map<FeatureId, FeatureSnapshot> snapshots,
  required DateTime now,
  WeekPresentation? currentWeek,
  bool ygdkReminderEnabled = true,
  bool ygdkWeekDone = false,
  bool ygdkTermDone = false,
}) async {
  final request = HomeTodoRequest(
    snapshots: snapshots,
    now: now,
    currentWeek: currentWeek,
    reminder: YgdkReminderSettings(
      enabled: ygdkReminderEnabled,
      weekDoneKey: ygdkWeekDone && currentWeek != null
          ? '${currentWeek.responseTerm}:${currentWeek.number}'
          : null,
      termDoneKey: ygdkTermDone ? currentWeek?.responseTerm : null,
    ),
  );
  return bridgeHomeTodoProjection(
    await agendaProjectHome(
      values: bridgeHomeAgendaInputs(request),
      context: bridgeHomeAgendaContext(request),
    ),
    request,
  ).todos;
}

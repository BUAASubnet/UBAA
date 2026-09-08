part of '../bridge_backend_test.dart';

void _registerAssignmentsBridgeBackendTests() {
  test('BridgeBackend Judge 批量详情保持请求顺序并投影题目白名单', () async {
    final response = BridgeRoutedJudgeAssignmentDetails(
      data: <BridgeJudgeAssignmentDetail>[
        _judgeDetail('c-2', 'a-2', '第二项'),
        _judgeDetail('c-1', 'a-1', '第一项'),
      ],
      route: const BridgeRouteDecision(
        policy: BridgeRoutePolicy.webVpn,
        resolvedRoute: BridgeConnectionMode.webVpn,
        network: BridgeNetworkState.offCampus,
        initialRoute: BridgeConnectionMode.webVpn,
        usedFallback: false,
      ),
    );
    final backend = BridgeBackend(_FakeJudgeBatchClient(response));

    final result = await backend.loadFeatureQuery(
      FeatureId.judge,
      FeatureQuery(
        view: FeatureQueryView.judgeBatchDetails,
        judgeKeys: const <JudgeAssignmentQueryKey>[
          JudgeAssignmentQueryKey(courseId: 'c-2', assignmentId: 'a-2'),
          JudgeAssignmentQueryKey(courseId: 'c-1', assignmentId: 'a-1'),
        ],
      ),
    );

    expect(result.summary, '2项希冀作业详情');
    expect(result.details.map((item) => item.title), ['第二项', '第一项']);
    expect(
      result.details.expand(
        (item) => [
          item.title,
          ...(item.presentation! as JudgeAssignmentPresentation).problems.map(
            (p) => p.name,
          ),
        ],
      ),
      ['第二项', '题目一', '第一项', '题目一'],
    );
    final parents = result.details
        .map((item) => item.presentation! as JudgeAssignmentPresentation)
        .toList();
    expect(parents.map((p) => p.courseId), ['c-2', 'c-1']);
    expect(parents.map((p) => p.assignmentId), ['a-2', 'a-1']);
    expect(
      result.details[0].fields.map((field) => field.label),
      contains('题目数'),
    );
    expect(result.resolvedRoute, ConnectionMode.webvpn);
  });

  test('BridgeBackend 课堂签到只按 typed 资格筛选并构造 typed action', () async {
    final response = BridgeRoutedSigninClasses(
      data: const <BridgeSigninClass>[
        BridgeSigninClass(
          courseId: 'course-1',
          courseName: '已签到课程',
          classBeginTime: '08:00',
          classEndTime: '09:00',
          signStatus: 0,
          signinEligibility: BridgeActionEligibility.denied,
          signinTarget: 'denied-target-safe',
        ),
        BridgeSigninClass(
          courseId: 'course-2',
          courseName: '未签到课程',
          classBeginTime: '10:00',
          classEndTime: '11:00',
          signStatus: 1,
          signinEligibility: BridgeActionEligibility.allowed,
          signinTarget: 'allowed-target-safe',
        ),
      ],
      route: const BridgeRouteDecision(
        policy: BridgeRoutePolicy.direct,
        resolvedRoute: BridgeConnectionMode.direct,
        network: BridgeNetworkState.campus,
        initialRoute: BridgeConnectionMode.direct,
        usedFallback: false,
      ),
    );
    final backend = BridgeBackend(_FakeSigninClient(response));

    final result = await backend.loadFeatureQuery(
      FeatureId.signin,
      const FeatureQuery(view: FeatureQueryView.signinPending),
    );

    expect(result.summary, '1门可签到课程');
    expect(result.details.single.title, '未签到课程');
    expect(
      result.details.single.action<SigninPerformAction>()?.scheduleId,
      'allowed-target-safe',
    );
    expect(
      result.details.single.action<SigninPerformAction>()?.eligibility,
      ActionEligibility.allowed,
    );
    expect(result.resolvedRoute, ConnectionMode.direct);
  });

  test('BridgeBackend SPOC 列表保留课程编号供详情选择', () async {
    final response = BridgeRoutedSpocAssignments(
      data: const BridgeSpocAssignments(
        termCode: '2026-spring',
        assignments: <BridgeSpocAssignmentSummary>[
          BridgeSpocAssignmentSummary(
            assignmentId: 'assignment-1',
            courseId: 'course-1',
            courseName: '程序设计',
            title: '第一次作业',
            submissionStatus: BridgeSpocSubmissionStatus.unsubmitted,
            submissionStatusText: '未提交',
          ),
        ],
      ),
      route: const BridgeRouteDecision(
        policy: BridgeRoutePolicy.direct,
        resolvedRoute: BridgeConnectionMode.direct,
        network: BridgeNetworkState.campus,
        initialRoute: BridgeConnectionMode.direct,
        usedFallback: false,
      ),
    );
    final backend = BridgeBackend(_FakeSpocClient(response));

    final result = await backend.loadFeatureQuery(
      FeatureId.spoc,
      const FeatureQuery(),
    );

    expect(
      result.details.single.fields
          .singleWhere((field) => field.label == '课程编号')
          .value,
      'course-1',
    );
  });
}

BridgeJudgeAssignmentDetail _judgeDetail(
  String courseId,
  String assignmentId,
  String title,
) => BridgeJudgeAssignmentDetail(
  courseId: courseId,
  courseName: '课程 $courseId',
  assignmentId: assignmentId,
  title: title,
  totalProblems: 2,
  submittedCount: 1,
  submissionStatus: BridgeJudgeSubmissionStatus.partial,
  submissionStatusText: '部分提交',
  problems: const <BridgeJudgeProblem>[
    BridgeJudgeProblem(
      name: '题目一',
      score: '5',
      maxScore: '10',
      status: BridgeJudgeSubmissionStatus.partial,
      statusText: '部分提交',
    ),
  ],
);

class _FakeJudgeBatchClient extends _CompatibleBridgeClient {
  _FakeJudgeBatchClient(this.response);

  final BridgeRoutedJudgeAssignmentDetails response;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #judgeAssignmentDetails) {
      final keys =
          invocation.namedArguments[#keys] as List<BridgeJudgeAssignmentKey>;
      expect(keys.map((key) => '${key.courseId}/${key.assignmentId}'), <String>[
        'c-2/a-2',
        'c-1/a-1',
      ]);
      return Future<BridgeRoutedJudgeAssignmentDetails>.value(response);
    }
    throw UnsupportedError('unexpected bridge call: ${invocation.memberName}');
  }
}

class _FakeSigninClient extends _CompatibleBridgeClient {
  _FakeSigninClient(this.response);

  final BridgeRoutedSigninClasses response;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #signinToday) {
      return Future<BridgeRoutedSigninClasses>.value(response);
    }
    throw UnsupportedError('unexpected bridge call: ${invocation.memberName}');
  }
}

class _FakeSpocClient extends _CompatibleBridgeClient {
  _FakeSpocClient(this.response);

  final BridgeRoutedSpocAssignments response;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #spocAssignments) {
      return Future<BridgeRoutedSpocAssignments>.value(response);
    }
    throw UnsupportedError('unexpected bridge call: ${invocation.memberName}');
  }
}

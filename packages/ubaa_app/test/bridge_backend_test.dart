import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('BridgeBackend 空教室楼层和节次筛选只投影白名单结果', () async {
    final response = BridgeRoutedClassroomQuery(
      data: const BridgeClassroomQuery(
        code: 0,
        message: 'ok',
        floors: <BridgeClassroomFloor>[
          BridgeClassroomFloor(
            name: '主楼',
            rooms: <BridgeClassroomInfo>[
              BridgeClassroomInfo(
                id: 'room-1',
                floorId: 'F2',
                name: '主楼 201',
                availableSections: '1,3',
              ),
              BridgeClassroomInfo(
                id: 'room-2',
                floorId: 'F2',
                name: '主楼 202',
                availableSections: '13',
              ),
            ],
          ),
          BridgeClassroomFloor(
            name: '新主楼',
            rooms: <BridgeClassroomInfo>[
              BridgeClassroomInfo(
                id: 'room-3',
                floorId: 'F3',
                name: '新主楼 301',
                availableSections: '3',
              ),
            ],
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
    final backend = BridgeBackend(_FakeClassroomClient(response));

    final result = await backend.loadFeatureQuery(
      FeatureId.classroom,
      FeatureQuery(
        date: DateTime(2026, 9, 2),
        campus: 2,
        floorId: 'F2',
        section: '3',
      ),
    );

    expect(result.summary, '1间可用教室');
    expect(result.details.single.title, '主楼 201');
    expect(result.resolvedRoute, ConnectionMode.direct);
  });

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
    expect(result.details.map((item) => item.title), <String>[
      '第二项',
      '题目一',
      '第一项',
      '题目一',
    ]);
    expect(
      result.details[0].fields.map((field) => field.label),
      contains('题目数'),
    );
    expect(result.resolvedRoute, ConnectionMode.webvpn);
  });

  test('BridgeBackend 课堂签到按冻结状态本地派生筛选', () async {
    final response = BridgeRoutedSigninClasses(
      data: const <BridgeSigninClass>[
        BridgeSigninClass(
          courseId: 'course-1',
          courseName: '已签到课程',
          classBeginTime: '08:00',
          classEndTime: '09:00',
          signStatus: 1,
        ),
        BridgeSigninClass(
          courseId: 'course-2',
          courseName: '未签到课程',
          classBeginTime: '10:00',
          classEndTime: '11:00',
          signStatus: 0,
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

    expect(result.summary, '1门未签到课程');
    expect(result.details.single.title, '未签到课程');
    expect(
      result.details.single.fields
          .singleWhere((field) => field.label == '课程 ID')
          .value,
      'course-2',
    );
    expect(
      result.details.single.fields
          .singleWhere((field) => field.label == '签到状态')
          .value,
      '未签到',
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

  test('BridgeBackend 图书馆座位详情保留预约所需公开摘要字段', () async {
    final response = BridgeRoutedLibBookSeats(
      data: const <BridgeLibBookSeat>[
        BridgeLibBookSeat(
          id: 'seat-2',
          name: '座位 A-01',
          no: 'A-01',
          status: '1',
          statusName: '可用',
          isAvailable: true,
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
    final backend = BridgeBackend(_FakeLibbookSeatsClient(response));
    final result = await backend.loadFeatureQuery(
      FeatureId.libbook,
      FeatureQuery(
        view: FeatureQueryView.libbookSeats,
        areaId: 'area-1',
        date: DateTime(2026, 9, 2),
        segment: '3',
        startTime: '10:00',
        endTime: '12:00',
      ),
    );
    final fields = {
      for (final field in result.details.single.fields)
        field.label: field.value,
    };
    expect(fields['分区 ID'], 'area-1');
    expect(fields['座位 ID'], 'seat-2');
    expect(fields['日期'], '2026-09-02');
    expect(fields['时段'], '3');
    expect(fields['可预约'], '是');
  });
}

class _FakeClassroomClient implements BridgeClient {
  _FakeClassroomClient(this.response);

  final BridgeRoutedClassroomQuery response;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #classroomSearch) {
      return Future<BridgeRoutedClassroomQuery>.value(response);
    }
    throw UnsupportedError('unexpected bridge call: ${invocation.memberName}');
  }
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

class _FakeJudgeBatchClient implements BridgeClient {
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

class _FakeSigninClient implements BridgeClient {
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

class _FakeSpocClient implements BridgeClient {
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

class _FakeLibbookSeatsClient implements BridgeClient {
  _FakeLibbookSeatsClient(this.response);

  final BridgeRoutedLibBookSeats response;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #libbookSeats) {
      final named = invocation.namedArguments;
      expect(named[#areaId], 'area-1');
      expect(named[#day], '2026-09-02');
      expect(named[#startTime], '10:00');
      expect(named[#endTime], '12:00');
      return Future<BridgeRoutedLibBookSeats>.value(response);
    }
    throw UnsupportedError('unexpected bridge call: ${invocation.memberName}');
  }
}

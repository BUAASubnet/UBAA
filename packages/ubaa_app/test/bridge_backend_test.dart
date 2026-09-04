import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

part 'bridge_backend/libbook.dart';

void main() {
  _registerLibbookBridgeBackendTests();

  test('BridgeBackend 接受当前合同版本', () {
    final client = _ContractVersionClient(4);

    final backend = BridgeBackend(client);

    expect(backend.client, same(client));
  });

  test('BridgeBackend 在 release 可执行路径拒绝不匹配合同版本', () {
    final client = _ContractVersionClient(2);

    expect(() => BridgeBackend(client), throwsA(isA<StateError>()));
    expect(client.disposeCalls, 1);
  });

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

    expect(result.summary, '1门未签到课程');
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

  test('BridgeBackend 博雅已选课程投影签到时间和位置要求但不暴露坐标', () async {
    final response = BridgeRoutedBykcChosenCourses(
      data: const <BridgeBykcChosenCourse>[
        BridgeBykcChosenCourse(
          id: 1,
          courseId: 42,
          courseName: '课程 A',
          coursePosition: '校本部',
          checkin: null,
          signEligibility: BridgeActionEligibility.allowed,
          signOutEligibility: BridgeActionEligibility.unknown,
          deselectEligibility: BridgeActionEligibility.unknown,
          signConfig: BridgeBykcSignConfig(
            signStartDate: '2026-09-02 08:00',
            signEndDate: '2026-09-02 10:00',
            signOutStartDate: '2026-09-02 11:00',
            signOutEndDate: '2026-09-02 12:00',
            signPoints: <BridgeBykcSignPoint>[
              BridgeBykcSignPoint(lat: 39.99, lng: 116.31, radius: 100),
              BridgeBykcSignPoint(lat: 40.00, lng: 116.32, radius: 80),
            ],
          ),
          courseSignType: 1,
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
    final result = await BridgeBackend(_FakeBykcChosenCoursesClient(response))
        .loadFeatureQuery(
          FeatureId.bykc,
          const FeatureQuery(view: FeatureQueryView.bykcChosenCourses),
        );
    final fields = {
      for (final field in result.details.single.fields)
        field.label: field.value,
    };
    expect(fields['签到时间'], '2026-09-02 08:00–2026-09-02 10:00');
    expect(fields['签退时间'], '2026-09-02 11:00–2026-09-02 12:00');
    expect(fields['可签到'], '是');
    expect(fields['可签退'], '未知');
    expect(fields.containsKey('签到状态'), isFalse);
    expect(fields['位置要求'], '指定位置（2 处）');
    expect(fields['签到类型'], '1');
    final actions = result.details.single.actions
        .whereType<BykcSignAction>()
        .toList(growable: false);
    expect(
      actions.map(
        (action) => (
          action.courseId,
          action.kind,
          action.eligibility,
          action.requiresCoordinates,
        ),
      ),
      <(int, BykcSignKind, ActionEligibility, bool)>[
        (42, BykcSignKind.signIn, ActionEligibility.allowed, false),
        (42, BykcSignKind.signOut, ActionEligibility.unknown, false),
      ],
    );
    expect(
      result.details.single.fields.any(
        (field) =>
            field.value.contains('39.99') || field.value.contains('116.31'),
      ),
      isFalse,
    );
  });

  test('BridgeBackend 仅在全部签到点坐标有效且半径有限为正时不要求调用方坐标', () async {
    const eligibility = BridgeActionEligibility.allowed;
    const unknown = BridgeActionEligibility.unknown;
    final response = BridgeRoutedBykcChosenCourses(
      data: const <BridgeBykcChosenCourse>[
        BridgeBykcChosenCourse(
          id: 1,
          courseId: 101,
          courseName: '完整范围',
          signEligibility: eligibility,
          signOutEligibility: eligibility,
          deselectEligibility: unknown,
          signConfig: BridgeBykcSignConfig(
            signPoints: <BridgeBykcSignPoint>[
              BridgeBykcSignPoint(lat: 39.9, lng: 116.3, radius: 1),
            ],
          ),
        ),
        BridgeBykcChosenCourse(
          id: 2,
          courseId: 102,
          courseName: '空范围',
          signEligibility: eligibility,
          signOutEligibility: eligibility,
          deselectEligibility: unknown,
          signConfig: BridgeBykcSignConfig(signPoints: <BridgeBykcSignPoint>[]),
        ),
        BridgeBykcChosenCourse(
          id: 3,
          courseId: 103,
          courseName: '零半径',
          signEligibility: eligibility,
          signOutEligibility: eligibility,
          deselectEligibility: unknown,
          signConfig: BridgeBykcSignConfig(
            signPoints: <BridgeBykcSignPoint>[
              BridgeBykcSignPoint(lat: 39.9, lng: 116.3, radius: 0),
            ],
          ),
        ),
        BridgeBykcChosenCourse(
          id: 4,
          courseId: 104,
          courseName: '无限半径',
          signEligibility: eligibility,
          signOutEligibility: eligibility,
          deselectEligibility: unknown,
          signConfig: BridgeBykcSignConfig(
            signPoints: <BridgeBykcSignPoint>[
              BridgeBykcSignPoint(
                lat: 39.9,
                lng: 116.3,
                radius: double.infinity,
              ),
            ],
          ),
        ),
        BridgeBykcChosenCourse(
          id: 5,
          courseId: 105,
          courseName: '缺失配置',
          signEligibility: eligibility,
          signOutEligibility: eligibility,
          deselectEligibility: unknown,
        ),
        BridgeBykcChosenCourse(
          id: 6,
          courseId: 106,
          courseName: '混合完整与不完整范围',
          signEligibility: eligibility,
          signOutEligibility: eligibility,
          deselectEligibility: unknown,
          signConfig: BridgeBykcSignConfig(
            signPoints: <BridgeBykcSignPoint>[
              BridgeBykcSignPoint(lat: 39.9, lng: 116.3, radius: 1),
              BridgeBykcSignPoint(lat: 39.91, lng: 116.31, radius: 0),
            ],
          ),
        ),
        BridgeBykcChosenCourse(
          id: 7,
          courseId: 107,
          courseName: '非法纬度',
          signEligibility: eligibility,
          signOutEligibility: eligibility,
          deselectEligibility: unknown,
          signConfig: BridgeBykcSignConfig(
            signPoints: <BridgeBykcSignPoint>[
              BridgeBykcSignPoint(lat: double.nan, lng: 116.3, radius: 1),
            ],
          ),
        ),
        BridgeBykcChosenCourse(
          id: 8,
          courseId: 108,
          courseName: '越界经度',
          signEligibility: eligibility,
          signOutEligibility: eligibility,
          deselectEligibility: unknown,
          signConfig: BridgeBykcSignConfig(
            signPoints: <BridgeBykcSignPoint>[
              BridgeBykcSignPoint(lat: 39.9, lng: 181, radius: 1),
            ],
          ),
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

    final result = await BridgeBackend(_FakeBykcChosenCoursesClient(response))
        .loadFeatureQuery(
          FeatureId.bykc,
          const FeatureQuery(view: FeatureQueryView.bykcChosenCourses),
        );
    final requirements = <int, bool>{
      for (final detail in result.details)
        for (final action in detail.actions.whereType<BykcSignAction>())
          action.courseId: action.requiresCoordinates,
    };
    expect(requirements, <int, bool>{
      101: false,
      102: true,
      103: true,
      104: true,
      105: true,
      106: true,
      107: true,
      108: true,
    });
    expect(
      result.details
          .singleWhere((detail) => detail.title == '空范围')
          .fields
          .singleWhere((field) => field.label == '位置要求')
          .value,
      '需获取当前位置（未返回可用签到范围）',
    );
    expect(
      result.details
          .singleWhere((detail) => detail.title == '缺失配置')
          .fields
          .singleWhere((field) => field.label == '位置要求')
          .value,
      '位置配置未知（需获取当前位置）',
    );
  });

  test('BridgeBackend 三类复杂写入保持 typed 字段并不透传 raw payload', () async {
    final backend = BridgeBackend(_FakeComplexWriteClient());
    final ygdkIntent = await backend.prepareYgdkSubmit(
      const YgdkSubmitInput(
        itemId: 7,
        place: '校园',
        photo: YgdkPhotoInput(
          bytes: <int>[1, 2],
          fileName: 'safe.jpg',
          mimeType: 'image/jpeg',
        ),
      ),
    );
    expect(ygdkIntent.operation, WriteOperation.ygdkSubmit);

    final cgyyIntent = await backend.prepareCgyySubmitReservation(
      const CgyySubmitInput(
        venueSiteId: 3,
        reservationDate: '2026-09-03',
        selections: <CgyyReservationSelectionInput>[
          CgyyReservationSelectionInput(spaceId: 4, timeId: 5),
        ],
        phone: 'phone-placeholder',
        theme: '讨论',
        purposeType: 1,
        joinerNum: 2,
        activityContent: '课程讨论',
        joiners: '张三',
        isPhilosophySocialSciences: false,
        isOffSchoolJoiner: false,
      ),
    );
    expect(cgyyIntent.operation, WriteOperation.cgyySubmitReservation);

    final evaluationIntent = await backend
        .prepareEvaluationSubmitCourses(const <EvaluationCourseInput>[
          EvaluationCourseInput(
            id: 'course-1',
            kcmc: '课程',
            bpmc: '教师',
            rwid: 'task-1',
            wjid: 'questionnaire-1',
            kcdm: 'K1',
            msid: 'M1',
          ),
        ]);
    expect(evaluationIntent.operation, WriteOperation.evaluationSubmitCourses);
  });

  test('BridgeBackend 保留场馆提交的非敏感订单收据用于结果核对', () async {
    final backend = BridgeBackend(_FakeCgyyCommitClient());

    final result = await backend.commitWrite('cgyy-intent');

    expect(result.operation, WriteOperation.cgyySubmitReservation);
    expect(result.cgyyReceipt?.orderId, 42);
    expect(result.cgyyReceipt?.venueSiteId, 3);
    expect(result.cgyyReceipt?.reservationDate, '2026-09-03');
    expect(result.cgyyReceipt?.orderStatus, 1);
  });

  test('BridgeBackend 场馆日期空间只投影可预约时段的公开 ID', () async {
    final backend = BridgeBackend(
      _FakeCgyyDayClient(
        BridgeRoutedCgyyDayInfo(
          data: const BridgeCgyyDayInfo(
            venueSiteId: 3,
            reservationDate: '2026-09-03',
            availableDates: <String>['2026-09-03'],
            timeSlots: <BridgeCgyyTimeSlot>[
              BridgeCgyyTimeSlot(
                id: 5,
                beginTime: '10:00',
                endTime: '11:00',
                label: '上午',
              ),
            ],
            spaces: <BridgeCgyySpaceAvailability>[
              BridgeCgyySpaceAvailability(
                spaceId: 4,
                spaceName: '讨论室',
                venueSiteId: 3,
                venueSpaceGroupId: 9,
                slots: <BridgeCgyySlotStatus>[
                  BridgeCgyySlotStatus(
                    timeId: 5,
                    reservationStatus: 0,
                    isReservable: true,
                  ),
                  BridgeCgyySlotStatus(
                    timeId: 6,
                    reservationStatus: 1,
                    isReservable: false,
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
        ),
      ),
    );
    final result = await backend.loadFeatureQuery(
      FeatureId.cgyy,
      const FeatureQuery(view: FeatureQueryView.cgyyDayInfo, siteId: 3),
    );
    expect(result.details, hasLength(1));
    final fields = {
      for (final field in result.details.single.fields)
        field.label: field.value,
    };
    expect(fields['站点 ID'], '3');
    expect(fields['空间 ID'], '4');
    expect(fields['时段 ID'], '5');
    expect(fields['空间组 ID'], '9');
    expect(fields['可预约'], '是');
  });

  test('BridgeBackend 取消入口状态字段保持公开且可供 UI 门禁使用', () async {
    final route = const BridgeRouteDecision(
      policy: BridgeRoutePolicy.direct,
      resolvedRoute: BridgeConnectionMode.direct,
      network: BridgeNetworkState.campus,
      initialRoute: BridgeConnectionMode.direct,
      usedFallback: false,
    );
    final backend = BridgeBackend(
      _FakeCancellationProjectionClient(
        libbook: BridgeRoutedLibBookBookings(
          data: const BridgeLibBookBookingsPage(
            bookings: <BridgeLibBookBooking>[
              BridgeLibBookBooking(
                id: 'booking-6',
                nameMerge: '预约',
                areaName: '馆区',
                seatNo: 'A-01',
                day: '2026-09-02',
                beginTime: '10:00',
                endTime: '12:00',
                status: '6',
                statusName: '有效',
              ),
            ],
            page: 1,
            limit: 20,
            total: 1,
          ),
          route: route,
        ),
        cgyy: BridgeRoutedCgyyOrders(
          data: const BridgeCgyyOrdersPage(
            content: <BridgeCgyyOrder>[
              BridgeCgyyOrder(id: 17, orderStatus: 1, checkStatus: 2),
            ],
            totalElements: 1,
            totalPages: 1,
            size: 20,
            number: 0,
          ),
          route: route,
        ),
      ),
    );
    final libbook = await backend.loadFeatureQuery(
      FeatureId.libbook,
      const FeatureQuery(view: FeatureQueryView.libbookBookings),
    );
    final libbookFields = {
      for (final field in libbook.details.single.fields)
        field.label: field.value,
    };
    expect(libbookFields['状态码'], '6');
    expect(libbookFields['状态'], '有效');

    final cgyy = await backend.loadFeatureQuery(
      FeatureId.cgyy,
      const FeatureQuery(view: FeatureQueryView.cgyyOrders),
    );
    final cgyyFields = {
      for (final field in cgyy.details.single.fields) field.label: field.value,
    };
    expect(cgyyFields['订单状态'], '1');
    expect(cgyyFields['审核状态'], '2');
    expect(cgyyFields['订单状态说明'], '待审批');
    expect(cgyyFields['审核状态说明'], '待辅导员审批');
  });

  test('BridgeBackend 阳光打卡记录只投影图片数量而不传递地址', () async {
    final response = BridgeRoutedYgdkRecords(
      data: const BridgeYgdkRecordsPage(
        content: <BridgeYgdkRecord>[
          BridgeYgdkRecord(
            recordId: 7,
            itemId: 3,
            itemName: '跑步',
            startTime: '2026-09-02 08:00',
            endTime: '2026-09-02 09:00',
            place: '校园',
            imageCount: 2,
            isOpen: false,
          ),
        ],
        total: 1,
        page: 1,
        size: 20,
        hasMore: false,
      ),
      route: const BridgeRouteDecision(
        policy: BridgeRoutePolicy.direct,
        resolvedRoute: BridgeConnectionMode.direct,
        network: BridgeNetworkState.campus,
        initialRoute: BridgeConnectionMode.direct,
        usedFallback: false,
      ),
    );
    final result = await BridgeBackend(_FakeYgdkRecordsClient(response))
        .loadFeatureQuery(
          FeatureId.ygdk,
          const FeatureQuery(view: FeatureQueryView.ygdkRecords),
        );
    expect(result.summary, '1条打卡记录');
    final fields = {
      for (final field in result.details.single.fields)
        field.label: field.value,
    };
    expect(fields['图片数量'], '2');
    expect(result.pagination?.page, 1);
    expect(result.pagination?.size, 20);
    expect(result.pagination?.total, 1);
    expect(result.pagination?.hasMore, isFalse);
    expect(
      result.details.single.fields.any((field) => field.value.contains('http')),
      isFalse,
    );
  });
}

class _ContractVersionClient implements BridgeClient {
  _ContractVersionClient(this.version);

  final int version;
  int disposeCalls = 0;

  @override
  int contractVersion() => version;

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('unexpected bridge call: ${invocation.memberName}');
  }
}

abstract class _CompatibleBridgeClient implements BridgeClient {
  @override
  int contractVersion() => 4;
}

class _FakeClassroomClient extends _CompatibleBridgeClient {
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

class _FakeBykcChosenCoursesClient extends _CompatibleBridgeClient {
  _FakeBykcChosenCoursesClient(this.response);

  final BridgeRoutedBykcChosenCourses response;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #bykcChosenCourses) {
      return Future<BridgeRoutedBykcChosenCourses>.value(response);
    }
    throw UnsupportedError('unexpected bridge call: ${invocation.memberName}');
  }
}

class _FakeComplexWriteClient extends _CompatibleBridgeClient {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final method = invocation.memberName;
    final named = invocation.namedArguments;
    if (method == #prepareYgdkSubmit) {
      final request = named[#request] as BridgeYgdkSubmitRequest;
      expect(request.itemId, 7);
      expect(request.photo?.bytes, <int>[1, 2]);
      expect(request.photo?.fileName, 'safe.jpg');
      return Future<BridgeWriteIntent>.value(
        _writeIntent(BridgeWriteOperation.ygdkSubmit),
      );
    }
    if (method == #prepareCgyySubmitReservation) {
      final request = named[#request] as BridgeCgyySubmitReservationRequest;
      expect(request.venueSiteId, 3);
      expect(request.selections.single.spaceId, 4);
      expect(request.selections.single.timeId, 5);
      expect(request.phone, 'phone-placeholder');
      return Future<BridgeWriteIntent>.value(
        _writeIntent(BridgeWriteOperation.cgyySubmitReservation),
      );
    }
    if (method == #prepareEvaluationSubmitCourses) {
      final request = named[#request] as BridgeEvaluationSubmitCoursesRequest;
      expect(request.courses.single.id, 'course-1');
      expect(request.courses.single.rwid, 'task-1');
      return Future<BridgeWriteIntent>.value(
        _writeIntent(BridgeWriteOperation.evaluationSubmitCourses),
      );
    }
    throw UnsupportedError('unexpected bridge call: $method');
  }
}

class _FakeCgyyCommitClient extends _CompatibleBridgeClient {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #commitWrite) {
      return Future<BridgeWriteCommitResult>.value(
        BridgeWriteCommitResult(
          operation: BridgeWriteOperation.cgyySubmitReservation,
          success: true,
          message: '场馆预约已提交',
          outcomeUnknown: false,
          resolvedRoute: BridgeConnectionMode.direct,
          order: const BridgeCgyyOrder(
            id: 42,
            venueSiteId: 3,
            reservationDate: '2026-09-03',
            orderStatus: 1,
            theme: 'private-theme',
          ),
        ),
      );
    }
    throw UnsupportedError('unexpected bridge call: ${invocation.memberName}');
  }
}

class _FakeCgyyDayClient extends _CompatibleBridgeClient {
  _FakeCgyyDayClient(this.response);

  final BridgeRoutedCgyyDayInfo response;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #cgyyDayInfo) {
      expect(invocation.namedArguments[#siteId], 3);
      expect(invocation.namedArguments[#date], isNotEmpty);
      return Future<BridgeRoutedCgyyDayInfo>.value(response);
    }
    throw UnsupportedError('unexpected bridge call: ${invocation.memberName}');
  }
}

class _FakeCancellationProjectionClient extends _CompatibleBridgeClient {
  _FakeCancellationProjectionClient({
    required this.libbook,
    required this.cgyy,
  });

  final BridgeRoutedLibBookBookings libbook;
  final BridgeRoutedCgyyOrders cgyy;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #libbookBookings) {
      return Future<BridgeRoutedLibBookBookings>.value(libbook);
    }
    if (invocation.memberName == #cgyyOrders) {
      return Future<BridgeRoutedCgyyOrders>.value(cgyy);
    }
    throw UnsupportedError('unexpected bridge call: ${invocation.memberName}');
  }
}

class _FakeYgdkRecordsClient extends _CompatibleBridgeClient {
  _FakeYgdkRecordsClient(this.response);

  final BridgeRoutedYgdkRecords response;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #ygdkRecords) {
      expect(invocation.namedArguments[#page], 1);
      expect(invocation.namedArguments[#size], 20);
      return Future<BridgeRoutedYgdkRecords>.value(response);
    }
    throw UnsupportedError('unexpected bridge call: ${invocation.memberName}');
  }
}

BridgeWriteIntent _writeIntent(BridgeWriteOperation operation) =>
    BridgeWriteIntent(
      intentId: 'intent',
      operation: operation,
      targetSummary: 'typed',
      resolvedRoute: BridgeConnectionMode.direct,
      warnings: const <String>[],
      expiresAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 120,
      requestDigest: 'digest',
    );

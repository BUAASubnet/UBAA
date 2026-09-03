part of '../bridge_backend_characterization_test.dart';

const _webVpnRoute = BridgeRouteDecision(
  policy: BridgeRoutePolicy.webVpn,
  resolvedRoute: BridgeConnectionMode.webVpn,
  network: BridgeNetworkState.offCampus,
  initialRoute: BridgeConnectionMode.webVpn,
  usedFallback: false,
);

class _SetterRecordingBackend extends BridgeBackend {
  _SetterRecordingBackend(super.client, this.events);

  final List<String> events;

  @override
  Future<BackendRouteSettings> setDefaultRoutePolicy(RoutePolicy policy) {
    events.add('backend.set:${policy.name}');
    return super.setDefaultRoutePolicy(policy);
  }
}

class _CharacterizationBridgeClient implements BridgeClient {
  _CharacterizationBridgeClient({this.emptyReads = false, List<String>? events})
    : calls = events ?? <String>[];

  final bool emptyReads;
  final List<String> calls;
  final Map<Symbol, Object> writeRequests = <Symbol, Object>{};
  BridgeError? authError;
  BridgeLoginOutcome loginOutcome = _readyLoginOutcome;
  BridgeWriteCommitResult commitResult = const BridgeWriteCommitResult(
    operation: BridgeWriteOperation.bykcSelectCourse,
    success: true,
    message: '已提交',
    outcomeUnknown: false,
    resolvedRoute: BridgeConnectionMode.webVpn,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final member = invocation.memberName;
    if (_readMembers.contains(member)) {
      calls.add(_describeReadCall(invocation));
      return _readResponse(invocation);
    }
    if (_writeMembers.containsKey(member)) {
      calls.add(_symbolName(member));
      writeRequests[member] = invocation.namedArguments[#request] as Object;
      return Future<BridgeWriteIntent>.value(
        _bridgeIntent(_writeMembers[member]!),
      );
    }
    switch (member) {
      case #setDefaultRoutePolicy:
        final policy = invocation.namedArguments[#policy] as BridgeRoutePolicy;
        calls.add('client.set:${policy.name}');
        return Future<BridgeRouteSettings>.value(
          BridgeRouteSettings(
            defaultPolicy: policy,
            activeRoutes: const <BridgeConnectionMode>[
              BridgeConnectionMode.direct,
              BridgeConnectionMode.webVpn,
            ],
          ),
        );
      case #prepareLogin:
        calls.add('client.prepareLogin');
        return Future<BridgeLoginPreparation>.value(
          const BridgeLoginPreparation(routes: <BridgeRouteLoginResult>[]),
        );
      case #login:
        calls.add(
          'client.login:${invocation.namedArguments[#username] as String}',
        );
        return Future<BridgeLoginOutcome>.value(loginOutcome);
      case #routeSettings:
        calls.add('client.routeSettings');
        return Future<BridgeRouteSettings>.value(
          const BridgeRouteSettings(
            defaultPolicy: BridgeRoutePolicy.auto,
            activeRoutes: <BridgeConnectionMode>[
              BridgeConnectionMode.direct,
              BridgeConnectionMode.webVpn,
            ],
          ),
        );
      case #authStatus:
        calls.add('client.authStatus');
        final error = authError;
        authError = null;
        if (error != null) return Future<BridgeLoginOutcome>.error(error);
        return Future<BridgeLoginOutcome>.value(_readyLoginOutcome);
      case #logout:
        calls.add('client.logout');
        return Future<void>.value();
      case #dispose:
        calls.add('client.dispose');
        return Future<void>.value();
      case #commitWrite:
        calls.add(
          'commitWrite:intentId=${invocation.namedArguments[#intentId]}',
        );
        return Future<BridgeWriteCommitResult>.value(commitResult);
      default:
        throw UnsupportedError('unexpected bridge call: $member');
    }
  }

  dynamic _readResponse(Invocation invocation) {
    final named = invocation.namedArguments;
    switch (invocation.memberName) {
      case #bykcChosenCourses:
        return Future<BridgeRoutedBykcChosenCourses>.value(
          BridgeRoutedBykcChosenCourses(
            data: emptyReads
                ? const <BridgeBykcChosenCourse>[]
                : const <BridgeBykcChosenCourse>[
                    BridgeBykcChosenCourse(
                      id: 1,
                      courseId: 42,
                      courseName: '已选课程',
                      checkin: 0,
                      canSign: true,
                      canSignOut: false,
                      signConfig: BridgeBykcSignConfig(
                        signPoints: <BridgeBykcSignPoint>[
                          BridgeBykcSignPoint(
                            lat: 39.9901,
                            lng: 116.3001,
                            radius: 100,
                          ),
                        ],
                      ),
                    ),
                  ],
            route: _webVpnRoute,
          ),
        );
      case #bykcCourseDetail:
        return Future<BridgeRoutedBykcCourse>.value(
          const BridgeRoutedBykcCourse(
            data: BridgeBykcCourse(
              id: 42,
              courseName: '课程详情',
              status: BridgeBykcCourseStatus.available,
            ),
            route: _webVpnRoute,
          ),
        );
      case #bykcCourses:
        final page = named[#page] as int;
        final size = named[#size] as int;
        return Future<BridgeRoutedBykcCourses>.value(
          BridgeRoutedBykcCourses(
            data: BridgeBykcCoursePage(
              content: emptyReads
                  ? const <BridgeBykcCourse>[]
                  : const <BridgeBykcCourse>[
                      BridgeBykcCourse(
                        id: 101,
                        courseName: '课程分页',
                        status: BridgeBykcCourseStatus.available,
                      ),
                    ],
              totalElements: emptyReads ? 0 : 201,
              totalPages: emptyReads ? 0 : 3,
              size: size,
              number: page,
            ),
            route: _webVpnRoute,
          ),
        );
      case #bykcProfile:
        return Future<BridgeRoutedBykcProfile>.value(
          const BridgeRoutedBykcProfile(
            data: BridgeBykcUserProfile(
              id: 1,
              employeeId: 'employee-secret',
              realName: '测试用户',
              studentNo: 'student-placeholder',
              collegeName: '测试学院',
            ),
            route: _webVpnRoute,
          ),
        );
      case #bykcStatistics:
        return Future<BridgeRoutedBykcStatistics>.value(
          BridgeRoutedBykcStatistics(
            data: BridgeBykcStatistics(
              categories: emptyReads
                  ? const <BridgeBykcStatistic>[]
                  : const <BridgeBykcStatistic>[
                      BridgeBykcStatistic(
                        categoryName: '美育分类',
                        requiredCount: 2,
                        passedCount: 1,
                        qualified: false,
                      ),
                    ],
            ),
            route: _webVpnRoute,
          ),
        );
      case #cgyyDayInfo:
        return Future<BridgeRoutedCgyyDayInfo>.value(
          BridgeRoutedCgyyDayInfo(
            data: BridgeCgyyDayInfo(
              venueSiteId: named[#siteId] as int,
              reservationDate: named[#date] as String,
              availableDates: const <String>[],
              timeSlots: emptyReads
                  ? const <BridgeCgyyTimeSlot>[]
                  : const <BridgeCgyyTimeSlot>[
                      BridgeCgyyTimeSlot(
                        id: 9,
                        beginTime: '08:00',
                        endTime: '10:00',
                        label: '上午时段',
                      ),
                    ],
              spaces: emptyReads
                  ? const <BridgeCgyySpaceAvailability>[]
                  : const <BridgeCgyySpaceAvailability>[
                      BridgeCgyySpaceAvailability(
                        spaceId: 8,
                        spaceName: '讨论室',
                        venueSiteId: 7,
                        venueSpaceGroupId: 10,
                        slots: <BridgeCgyySlotStatus>[
                          BridgeCgyySlotStatus(
                            timeId: 9,
                            reservationStatus: 0,
                            isReservable: true,
                          ),
                        ],
                      ),
                    ],
            ),
            route: _webVpnRoute,
          ),
        );
      case #cgyyLockCode:
        return Future<BridgeRoutedCgyyLockCode>.value(
          const BridgeRoutedCgyyLockCode(
            data: BridgeCgyyLockCode(available: false),
            route: _webVpnRoute,
          ),
        );
      case #cgyyOrderDetail:
        return Future<BridgeRoutedCgyyOrder>.value(
          BridgeRoutedCgyyOrder(
            data: BridgeCgyyOrder(id: named[#id] as int),
            route: _webVpnRoute,
          ),
        );
      case #cgyyOrders:
        final page = named[#page] as int;
        final size = named[#size] as int;
        return Future<BridgeRoutedCgyyOrders>.value(
          BridgeRoutedCgyyOrders(
            data: BridgeCgyyOrdersPage(
              content: emptyReads
                  ? const <BridgeCgyyOrder>[]
                  : const <BridgeCgyyOrder>[
                      BridgeCgyyOrder(id: 101, theme: '订单分页'),
                    ],
              totalElements: emptyReads ? 0 : 201,
              totalPages: emptyReads ? 0 : 3,
              size: size,
              number: page,
            ),
            route: _webVpnRoute,
          ),
        );
      case #cgyyPurposeTypes:
        return Future<BridgeRoutedCgyyPurposeTypes>.value(
          BridgeRoutedCgyyPurposeTypes(
            data: BridgeCgyyPurposeTypes(
              items: emptyReads
                  ? const <BridgeCgyyPurposeType>[]
                  : const <BridgeCgyyPurposeType>[
                      BridgeCgyyPurposeType(key: 2, name: '课程讨论用途'),
                    ],
              source: BridgeCgyyPurposeSource.staticFallback,
            ),
            route: _webVpnRoute,
          ),
        );
      case #cgyySites:
        return Future<BridgeRoutedCgyySites>.value(
          BridgeRoutedCgyySites(
            data: emptyReads
                ? const <BridgeCgyyVenueSite>[]
                : const <BridgeCgyyVenueSite>[
                    BridgeCgyyVenueSite(
                      id: 7,
                      siteName: '场馆站点',
                      venueName: '场馆',
                      campusName: '校区',
                      siteTelephone: 'telephone-secret',
                    ),
                  ],
            route: _webVpnRoute,
          ),
        );
      case #classroomSearch:
        return Future<BridgeRoutedClassroomQuery>.value(
          BridgeRoutedClassroomQuery(
            data: BridgeClassroomQuery(
              code: 0,
              message: 'ok',
              floors: emptyReads
                  ? const <BridgeClassroomFloor>[]
                  : const <BridgeClassroomFloor>[
                      BridgeClassroomFloor(
                        name: '主楼',
                        rooms: <BridgeClassroomInfo>[
                          BridgeClassroomInfo(
                            id: 'room-101',
                            floorId: 'F1',
                            name: '教室 101',
                            availableSections: '1,2',
                          ),
                        ],
                      ),
                    ],
            ),
            route: _webVpnRoute,
          ),
        );
      case #evaluationAll:
        return Future<BridgeRoutedEvaluation>.value(
          BridgeRoutedEvaluation(
            data: BridgeEvaluationCoursesResponse(
              courses: emptyReads
                  ? const <BridgeEvaluationCourse>[]
                  : const <BridgeEvaluationCourse>[
                      BridgeEvaluationCourse(
                        id: 'evaluation-read-1',
                        kcmc: '评教课程',
                        bpmc: '测试教师',
                        isEvaluated: false,
                        rwid: 'task-read-1',
                        wjid: 'questionnaire-read-1',
                        kcdm: 'READ1',
                        msid: 'MODEL1',
                      ),
                    ],
              progress: BridgeEvaluationProgress(
                totalCourses: emptyReads ? 0 : 1,
                evaluatedCourses: 0,
                pendingCourses: emptyReads ? 0 : 1,
              ),
            ),
            route: _webVpnRoute,
          ),
        );
      case #examArrangement:
        return Future<BridgeRoutedExamArrangement>.value(
          BridgeRoutedExamArrangement(
            data: BridgeExamArrangement(
              arranged: emptyReads
                  ? const <BridgeExam>[]
                  : const <BridgeExam>[
                      BridgeExam(
                        courseName: '考试课程',
                        examTimeDescription: '第十八周',
                        examPlace: '主楼 101',
                      ),
                    ],
              notArranged: const <BridgeExam>[],
            ),
            route: _webVpnRoute,
          ),
        );
      case #grades:
        return Future<BridgeRoutedGrades>.value(
          BridgeRoutedGrades(
            data: BridgeGradeData(
              termCode: named[#term] as String,
              grades: emptyReads
                  ? const <BridgeGrade>[]
                  : const <BridgeGrade>[
                      BridgeGrade(
                        courseName: '成绩课程',
                        courseCode: 'GRADE1',
                        score: '95',
                        gradePoint: '4.0',
                      ),
                    ],
            ),
            route: _webVpnRoute,
          ),
        );
      case #judgeAssignment:
        return Future<BridgeRoutedJudgeAssignmentDetail>.value(
          BridgeRoutedJudgeAssignmentDetail(
            data: _judgeDetail(
              named[#courseId] as String,
              named[#assignmentId] as String,
            ),
            route: _webVpnRoute,
          ),
        );
      case #judgeAssignmentDetails:
        return Future<BridgeRoutedJudgeAssignmentDetails>.value(
          BridgeRoutedJudgeAssignmentDetails(
            data: emptyReads
                ? const <BridgeJudgeAssignmentDetail>[]
                : (named[#keys] as List<BridgeJudgeAssignmentKey>)
                      .map(
                        (key) => _judgeDetail(
                          key.courseId,
                          key.assignmentId,
                          title: '批量作业 ${key.assignmentId}',
                        ),
                      )
                      .toList(growable: false),
            route: _webVpnRoute,
          ),
        );
      case #judgeAssignments:
        return Future<BridgeRoutedJudgeSummaries>.value(
          BridgeRoutedJudgeSummaries(
            data: emptyReads
                ? const <BridgeJudgeAssignmentSummary>[]
                : const <BridgeJudgeAssignmentSummary>[
                    BridgeJudgeAssignmentSummary(
                      courseId: 'course-list-1',
                      courseName: '课程',
                      assignmentId: 'assignment-list-1',
                      title: '作业列表项',
                      totalProblems: 1,
                      submittedCount: 0,
                      submissionStatus: BridgeJudgeSubmissionStatus.unsubmitted,
                      submissionStatusText: '未提交',
                    ),
                  ],
            route: _webVpnRoute,
          ),
        );
      case #libbookAreaDetail:
        return Future<BridgeRoutedLibBookAreaDetail>.value(
          BridgeRoutedLibBookAreaDetail(
            data: BridgeLibBookAreaDetail(
              id: named[#areaId] as String,
              name: '分区详情',
              availableDates: emptyReads
                  ? const <String>[]
                  : const <String>['2026-09-04'],
              timeSlots: emptyReads
                  ? const <BridgeLibBookTimeSlot>[]
                  : const <BridgeLibBookTimeSlot>[
                      BridgeLibBookTimeSlot(
                        id: 'slot-read-1',
                        start: '08:00',
                        end: '10:00',
                        label: '上午',
                      ),
                    ],
            ),
            route: _webVpnRoute,
          ),
        );
      case #libbookAreas:
        return Future<BridgeRoutedLibBookAreas>.value(
          BridgeRoutedLibBookAreas(
            data: emptyReads
                ? const <BridgeLibBookArea>[]
                : const <BridgeLibBookArea>[
                    BridgeLibBookArea(
                      id: 'area-read-1',
                      name: '图书馆分区',
                      areaName: '一层',
                      premisesId: 'premises-1',
                      storeyId: 'storey-1',
                      freeNum: 3,
                      totalNum: 10,
                    ),
                  ],
            route: _webVpnRoute,
          ),
        );
      case #libbookBookings:
        final page = named[#page] as int;
        final limit = named[#limit] as int;
        return Future<BridgeRoutedLibBookBookings>.value(
          BridgeRoutedLibBookBookings(
            data: BridgeLibBookBookingsPage(
              bookings: emptyReads
                  ? const <BridgeLibBookBooking>[]
                  : const <BridgeLibBookBooking>[
                      BridgeLibBookBooking(
                        id: 'booking-read-1',
                        nameMerge: '预约记录',
                        areaName: '一层',
                        seatNo: 'A-01',
                        day: '2026-09-04',
                        beginTime: '08:00',
                        endTime: '10:00',
                        status: '1',
                        statusName: '有效',
                      ),
                    ],
              page: page,
              limit: limit,
              total: emptyReads ? 0 : 9,
            ),
            route: _webVpnRoute,
          ),
        );
      case #libbookLibraries:
        return Future<BridgeRoutedLibBookLibraries>.value(
          BridgeRoutedLibBookLibraries(
            data: emptyReads
                ? const <BridgeLibBookLibrary>[]
                : const <BridgeLibBookLibrary>[
                    BridgeLibBookLibrary(
                      id: 'library-read-1',
                      name: '测试图书馆',
                      freeNum: 5,
                      totalNum: 20,
                      storeys: <BridgeLibBookStorey>[],
                    ),
                  ],
            route: _webVpnRoute,
          ),
        );
      case #libbookSeats:
        return Future<BridgeRoutedLibBookSeats>.value(
          BridgeRoutedLibBookSeats(
            data: emptyReads
                ? const <BridgeLibBookSeat>[]
                : const <BridgeLibBookSeat>[
                    BridgeLibBookSeat(
                      id: 'seat-read-1',
                      name: '座位 A-01',
                      no: 'A-01',
                      status: '1',
                      statusName: '可用',
                      isAvailable: true,
                    ),
                  ],
            route: _webVpnRoute,
          ),
        );
      case #scheduleTerms:
        return Future<BridgeRoutedTerms>.value(
          BridgeRoutedTerms(
            data: emptyReads
                ? const <BridgeTerm>[]
                : const <BridgeTerm>[
                    BridgeTerm(
                      itemCode: '2026-fall',
                      itemName: '秋季学期',
                      selected: true,
                      itemIndex: 1,
                    ),
                  ],
            route: _webVpnRoute,
          ),
        );
      case #scheduleToday:
        return Future<BridgeRoutedTodayClasses>.value(
          BridgeRoutedTodayClasses(
            data: emptyReads
                ? const <BridgeTodayClass>[]
                : const <BridgeTodayClass>[
                    BridgeTodayClass(
                      bizName: '今日课程',
                      place: '主楼 101',
                      time: '08:00',
                    ),
                  ],
            route: _webVpnRoute,
          ),
        );
      case #scheduleWeek:
        return Future<BridgeRoutedWeeklySchedule>.value(
          BridgeRoutedWeeklySchedule(
            data: BridgeWeeklySchedule(
              arrangedList: emptyReads
                  ? const <BridgeCourseClass>[]
                  : const <BridgeCourseClass>[
                      BridgeCourseClass(
                        courseCode: 'WEEK1',
                        courseName: '周课表课程',
                        placeName: '主楼 102',
                      ),
                    ],
              code: 'week',
              name: '周课表',
            ),
            route: _webVpnRoute,
          ),
        );
      case #scheduleWeeks:
        return Future<BridgeRoutedWeeks>.value(
          BridgeRoutedWeeks(
            data: emptyReads
                ? const <BridgeWeek>[]
                : const <BridgeWeek>[
                    BridgeWeek(
                      startDate: '2026-09-01',
                      endDate: '2026-09-07',
                      term: '2026-fall',
                      curWeek: true,
                      serialNumber: 4,
                      name: '第 4 周',
                    ),
                  ],
            route: _webVpnRoute,
          ),
        );
      case #signinToday:
        return Future<BridgeRoutedSigninClasses>.value(
          BridgeRoutedSigninClasses(
            data: emptyReads
                ? const <BridgeSigninClass>[]
                : const <BridgeSigninClass>[
                    BridgeSigninClass(
                      courseId: 'signin-read-1',
                      courseName: '签到课程',
                      classBeginTime: '08:00',
                      classEndTime: '10:00',
                      signStatus: 0,
                    ),
                  ],
            route: _webVpnRoute,
          ),
        );
      case #spocAssignment:
        return Future<BridgeRoutedSpocAssignmentDetail>.value(
          BridgeRoutedSpocAssignmentDetail(
            data: BridgeSpocAssignmentDetail(
              assignmentId: named[#assignmentId] as String,
              courseId: 'course-1',
              courseName: '课程',
              title: '作业详情',
              submissionStatus: BridgeSpocSubmissionStatus.unsubmitted,
              submissionStatusText: '未提交',
            ),
            route: _webVpnRoute,
          ),
        );
      case #spocAssignments:
        return Future<BridgeRoutedSpocAssignments>.value(
          BridgeRoutedSpocAssignments(
            data: BridgeSpocAssignments(
              termCode: '2026-fall',
              assignments: emptyReads
                  ? const <BridgeSpocAssignmentSummary>[]
                  : const <BridgeSpocAssignmentSummary>[
                      BridgeSpocAssignmentSummary(
                        assignmentId: 'spoc-list-1',
                        courseId: 'course-spoc-1',
                        courseName: 'SPOC 课程',
                        title: 'SPOC 列表作业',
                        submissionStatus:
                            BridgeSpocSubmissionStatus.unsubmitted,
                        submissionStatusText: '未提交',
                      ),
                    ],
            ),
            route: _webVpnRoute,
          ),
        );
      case #ygdkOverview:
        return Future<BridgeRoutedYgdkOverview>.value(
          BridgeRoutedYgdkOverview(
            data: BridgeYgdkOverview(
              summary: BridgeYgdkTermSummary(termCount: 0),
              classifyId: 0,
              classifyName: '分类',
              defaultItemId: 0,
              defaultItemName: '项目',
              items: emptyReads
                  ? const <BridgeYgdkItem>[]
                  : const <BridgeYgdkItem>[
                      BridgeYgdkItem(itemId: 7, name: '跑步项目', kind: 1),
                    ],
            ),
            route: _webVpnRoute,
          ),
        );
      case #ygdkRecords:
        final page = named[#page] as int;
        final size = named[#size] as int;
        return Future<BridgeRoutedYgdkRecords>.value(
          BridgeRoutedYgdkRecords(
            data: BridgeYgdkRecordsPage(
              content: emptyReads
                  ? const <BridgeYgdkRecord>[]
                  : const <BridgeYgdkRecord>[
                      BridgeYgdkRecord(
                        recordId: 101,
                        itemId: 7,
                        itemName: '打卡记录',
                        place: '校园',
                        imageCount: 2,
                        isOpen: false,
                      ),
                    ],
              total: emptyReads ? 0 : 9,
              page: page,
              size: size,
              hasMore: !emptyReads,
            ),
            route: _webVpnRoute,
          ),
        );
      default:
        throw UnsupportedError(
          'unexpected read call: ${invocation.memberName}',
        );
    }
  }
}

const _readyLoginOutcome = BridgeLoginOutcome(
  readiness: BridgeLoginReadiness.allReady,
  routes: <BridgeRouteLoginResult>[],
);

const _readMembers = <Symbol>{
  #bykcChosenCourses,
  #bykcCourseDetail,
  #bykcCourses,
  #bykcProfile,
  #bykcStatistics,
  #cgyyDayInfo,
  #cgyyLockCode,
  #cgyyOrderDetail,
  #cgyyOrders,
  #cgyyPurposeTypes,
  #cgyySites,
  #classroomSearch,
  #evaluationAll,
  #examArrangement,
  #grades,
  #judgeAssignment,
  #judgeAssignmentDetails,
  #judgeAssignments,
  #libbookAreaDetail,
  #libbookAreas,
  #libbookBookings,
  #libbookLibraries,
  #libbookSeats,
  #scheduleTerms,
  #scheduleToday,
  #scheduleWeek,
  #scheduleWeeks,
  #signinToday,
  #spocAssignment,
  #spocAssignments,
  #ygdkOverview,
  #ygdkRecords,
};

const _writeMembers = <Symbol, BridgeWriteOperation>{
  #prepareBykcSelectCourse: BridgeWriteOperation.bykcSelectCourse,
  #prepareBykcDeselectCourse: BridgeWriteOperation.bykcDeselectCourse,
  #prepareBykcSignCourse: BridgeWriteOperation.bykcSignCourse,
  #prepareSigninPerform: BridgeWriteOperation.signinPerform,
  #prepareLibbookReserve: BridgeWriteOperation.libbookReserve,
  #prepareLibbookCancelBooking: BridgeWriteOperation.libbookCancelBooking,
  #prepareYgdkSubmit: BridgeWriteOperation.ygdkSubmit,
  #prepareCgyySubmitReservation: BridgeWriteOperation.cgyySubmitReservation,
  #prepareCgyyCancelOrder: BridgeWriteOperation.cgyyCancelOrder,
  #prepareEvaluationSubmitCourses: BridgeWriteOperation.evaluationSubmitCourses,
};

BridgeWriteIntent _bridgeIntent(BridgeWriteOperation operation) =>
    BridgeWriteIntent(
      intentId: 'intent-${operation.name}',
      operation: operation,
      targetSummary: '安全摘要',
      resolvedRoute: BridgeConnectionMode.webVpn,
      warnings: const <String>[],
      expiresAt: 2000000000,
      requestDigest: 'digest-${operation.name}',
    );

BridgeJudgeAssignmentDetail _judgeDetail(
  String courseId,
  String assignmentId, {
  String title = '作业详情',
}) => BridgeJudgeAssignmentDetail(
  courseId: courseId,
  courseName: '课程',
  assignmentId: assignmentId,
  title: title,
  totalProblems: 0,
  submittedCount: 0,
  submissionStatus: BridgeJudgeSubmissionStatus.unsubmitted,
  submissionStatusText: '未提交',
  problems: const <BridgeJudgeProblem>[],
);

String _describeReadCall(Invocation invocation) {
  final named = invocation.namedArguments;
  return switch (invocation.memberName) {
    #bykcCourseDetail => 'bykcCourseDetail:id=${named[#id]}',
    #bykcCourses =>
      'bykcCourses:page=${named[#page]},size=${named[#size]},all=${named[#all]}',
    #cgyyDayInfo => 'cgyyDayInfo:siteId=${named[#siteId]},date=${named[#date]}',
    #cgyyOrderDetail => 'cgyyOrderDetail:id=${named[#id]}',
    #cgyyOrders => 'cgyyOrders:page=${named[#page]},size=${named[#size]}',
    #classroomSearch =>
      'classroomSearch:campus=${named[#campus]},date=${named[#date]}',
    #examArrangement => 'examArrangement:term=${named[#term]}',
    #grades => 'grades:term=${named[#term]}',
    #judgeAssignment =>
      'judgeAssignment:courseId=${named[#courseId]},assignmentId=${named[#assignmentId]}',
    #judgeAssignmentDetails =>
      'judgeAssignmentDetails:keys=${(named[#keys] as List<BridgeJudgeAssignmentKey>).map((key) => '${key.courseId}/${key.assignmentId}').join(',')}',
    #judgeAssignments =>
      'judgeAssignments:includeExpired=${named[#includeExpired]}',
    #libbookAreaDetail => 'libbookAreaDetail:areaId=${named[#areaId]}',
    #libbookAreas =>
      'libbookAreas:premisesId=${named[#premisesId]},storeyId=${named[#storeyId]},day=${named[#day]}',
    #libbookBookings =>
      'libbookBookings:page=${named[#page]},limit=${named[#limit]}',
    #libbookLibraries => 'libbookLibraries:day=${named[#day]}',
    #libbookSeats =>
      'libbookSeats:areaId=${named[#areaId]},day=${named[#day]},startTime=${named[#startTime]},endTime=${named[#endTime]}',
    #scheduleWeek => 'scheduleWeek:term=${named[#term]},week=${named[#week]}',
    #scheduleWeeks => 'scheduleWeeks:term=${named[#term]}',
    #spocAssignment => 'spocAssignment:assignmentId=${named[#assignmentId]}',
    #ygdkRecords => 'ygdkRecords:page=${named[#page]},size=${named[#size]}',
    _ => _symbolName(invocation.memberName),
  };
}

String _symbolName(Symbol symbol) =>
    symbol.toString().substring(8, symbol.toString().length - 2);

String _resultText(FeatureResult result) => <String>[
  if (result.summary case final summary?) summary,
  for (final detail in result.details) ...<String>[
    detail.title,
    if (detail.subtitle case final subtitle?) subtitle,
    for (final field in detail.fields) ...<String>[field.label, field.value],
  ],
].join('|');

part of '../bridge_backend_characterization_test.dart';

void registerAcademicPresentationTests() {
  test('学业展示保留今日缺值且不推断日期或新增请求', () async {
    final client = _AcademicPresentationClient();
    final result = await BridgeBackend(
      client,
    ).loadFeatureQuery(FeatureId.schedule, const FeatureQuery());
    expect(result.details.single.presentation, isA<TodayCoursePresentation>());
    final item = result.details.single.presentation! as TodayCoursePresentation;
    expect(item.time, '时间待定');
    expect(item.place, isNull);
    expect(result.details.single.readNavigation, isNull);
    expect(client.calls, ['today']);
    expect(result.resolvedRoute, ConnectionMode.webvpn);
  });

  test('学期周次导航保留原始typed编码与父请求学期且不自动请求下一层', () async {
    final client = _AcademicPresentationClient();
    final backend = BridgeBackend(client);
    final terms = await backend.loadFeatureQuery(
      FeatureId.schedule,
      const FeatureQuery(view: FeatureQueryView.scheduleTerms),
    );
    expect(terms.details.first.presentation, isA<TermPresentation>());
    final term = terms.details.first.presentation! as TermPresentation;
    expect(term.code, '2026-2027-1');
    expect(term.index, 9);
    expect(terms.details.first.readNavigation?.query.term, term.code);
    expect(
      terms.details.first.readNavigation?.query.view,
      FeatureQueryView.scheduleWeeks,
    );
    expect(terms.details.last.readNavigation, isNull);
    expect(client.calls, ['terms']);
    final weeks = await backend.loadFeatureQuery(
      FeatureId.schedule,
      const FeatureQuery(
        view: FeatureQueryView.scheduleWeeks,
        term: '2026-2027-1',
      ),
    );
    expect(weeks.details.first.presentation, isA<WeekPresentation>());
    final week = weeks.details.first.presentation! as WeekPresentation;
    expect(week.responseTerm, '上游响应学期');
    expect(week.requestTerm, '2026-2027-1');
    expect(week.startDate, '日期待定');
    expect(weeks.details.first.readNavigation?.query.term, '2026-2027-1');
    expect(weeks.details.first.readNavigation?.query.week, 4);
    expect(weeks.details.last.readNavigation, isNull);
    expect(client.calls, ['terms', 'weeks:2026-2027-1']);
  });

  test('两个周课表入口保留周几节次结束时间及null并保持原顺序', () async {
    for (final view in [
      FeatureQueryView.scheduleWeek,
      FeatureQueryView.summary,
    ]) {
      final client = _AcademicPresentationClient();
      final result = await BridgeBackend(client).loadFeatureQuery(
        FeatureId.schedule,
        FeatureQuery(view: view, term: '2026-2027-1', week: 4),
      );
      expect(result.details.map((item) => item.title), ['周二课程', '未知时间课程']);
      expect(
        result.details.first.presentation,
        isA<ScheduleCoursePresentation>(),
      );
      final first =
          result.details.first.presentation! as ScheduleCoursePresentation;
      final last =
          result.details.last.presentation! as ScheduleCoursePresentation;
      expect(first.dayOfWeek, 2);
      expect(first.beginSection, 3);
      expect(first.endSection, 4);
      expect(first.endTime, '十点下课');
      expect(first.credit, '待确认');
      expect(last.dayOfWeek, isNull);
      expect(last.beginSection, isNull);
      expect(last.endTime, isNull);
      expect(client.calls, ['week:2026-2027-1/4']);
    }
  });

  test('考试保留单侧开始结束与座位且安排状态只来自所属列表', () async {
    final client = _AcademicPresentationClient();
    final backend = BridgeBackend(client);
    final result = await backend.loadFeatureQuery(
      FeatureId.exam,
      const FeatureQuery(term: 'term'),
    );
    expect(result.details.first.presentation, isA<ExamPresentation>());
    final first = result.details.first.presentation! as ExamPresentation;
    final last = result.details.last.presentation! as ExamPresentation;
    expect(first.arranged, isTrue);
    expect(first.startTime, '开始待定');
    expect(first.endTime, isNull);
    expect(first.seat, 'A-03');
    expect(last.arranged, isFalse);
    expect(last.startTime, isNull);
    expect(last.endTime, '结束待定');
    for (final view in [
      FeatureQueryView.examArranged,
      FeatureQueryView.examNotArranged,
    ]) {
      final filtered = await backend.loadFeatureQuery(
        FeatureId.exam,
        FeatureQuery(term: 'term', view: view),
      );
      expect(filtered.details, hasLength(1));
      expect(
        (filtered.details.single.presentation! as ExamPresentation).arranged,
        view == FeatureQueryView.examArranged,
      );
    }
    expect(client.calls, ['exam:term', 'exam:term', 'exam:term']);
  });

  test('成绩保留字符串绩点和null并维持已出待出判定', () async {
    final client = _AcademicPresentationClient();
    final backend = BridgeBackend(client);
    final result = await backend.loadFeatureQuery(
      FeatureId.grades,
      const FeatureQuery(term: 'term'),
    );
    expect(result.details.first.presentation, isA<GradePresentation>());
    final first = result.details.first.presentation! as GradePresentation;
    final last = result.details.last.presentation! as GradePresentation;
    expect(first.score, '通过');
    expect(first.gradePoint, '优秀');
    expect(first.credit, 2.5);
    expect(last.score, isNull);
    expect(last.gradePoint, isNull);
    expect(last.courseName, isNull);
    final scored = await backend.loadFeatureQuery(
      FeatureId.grades,
      const FeatureQuery(term: 'term', view: FeatureQueryView.gradesScored),
    );
    final missing = await backend.loadFeatureQuery(
      FeatureId.grades,
      const FeatureQuery(term: 'term', view: FeatureQueryView.gradesMissing),
    );
    expect(scored.details, hasLength(1));
    expect(missing.details, hasLength(1));
    expect(client.calls, ['grades:term', 'grades:term', 'grades:term']);
  });

  test('空教室展示保留父楼层与精确节次且不增加上游筛选参数', () async {
    final client = _AcademicPresentationClient();
    final result = await BridgeBackend(client).loadFeatureQuery(
      FeatureId.classroom,
      FeatureQuery(
        campus: 2,
        date: DateTime(2026, 9, 8),
        floorId: 'F03',
        section: '3',
      ),
    );
    expect(result.details, hasLength(1));
    expect(result.details.single.presentation, isA<ClassroomPresentation>());
    final room = result.details.single.presentation! as ClassroomPresentation;
    expect(room.roomId, 'room-3');
    expect(room.floorId, 'F03');
    expect(room.floorName, '主楼三层');
    expect(room.availableSections, '3, 13');
    expect(room.sectionTokens, ['3', '13']);
    expect(() => room.sectionTokens.add('99'), throwsUnsupportedError);
    expect(client.calls, ['rooms:2/2026-09-08']);
  });
}

class _AcademicPresentationClient extends _CharacterizationBridgeClient {
  @override
  Future<BridgeRoutedTodayClasses> scheduleToday() async {
    calls.add('today');
    return const BridgeRoutedTodayClasses(
      data: [BridgeTodayClass(bizName: '今日课程', time: '时间待定')],
      route: _webVpnRoute,
    );
  }

  @override
  Future<BridgeRoutedTerms> scheduleTerms() async {
    calls.add('terms');
    return const BridgeRoutedTerms(
      data: [
        BridgeTerm(
          itemCode: '2026-2027-1',
          itemName: '不同于编码的标题',
          selected: true,
          itemIndex: 9,
        ),
        BridgeTerm(
          itemCode: ' ',
          itemName: '无编码',
          selected: false,
          itemIndex: 0,
        ),
      ],
      route: _webVpnRoute,
    );
  }

  @override
  Future<BridgeRoutedWeeks> scheduleWeeks({required String term}) async {
    calls.add('weeks:$term');
    return const BridgeRoutedWeeks(
      data: [
        BridgeWeek(
          startDate: '日期待定',
          endDate: '结束待定',
          term: '上游响应学期',
          curWeek: true,
          serialNumber: 4,
          name: '第四周',
        ),
        BridgeWeek(
          startDate: '',
          endDate: '',
          term: '',
          curWeek: false,
          serialNumber: 0,
          name: '未知周',
        ),
      ],
      route: _webVpnRoute,
    );
  }

  @override
  Future<BridgeRoutedWeeklySchedule> scheduleWeek({
    required String term,
    required int week,
  }) async {
    calls.add('week:$term/$week');
    return const BridgeRoutedWeeklySchedule(
      data: BridgeWeeklySchedule(
        code: 'response-code',
        name: '周表',
        arrangedList: [
          BridgeCourseClass(
            courseCode: 'B',
            courseName: '周二课程',
            beginTime: '开始待定',
            endTime: '十点下课',
            beginSection: 3,
            endSection: 4,
            dayOfWeek: 2,
            credit: '待确认',
          ),
          BridgeCourseClass(courseCode: 'A', courseName: '未知时间课程'),
        ],
      ),
      route: _webVpnRoute,
    );
  }

  @override
  Future<BridgeRoutedExamArrangement> examArrangement({
    required String term,
  }) async {
    calls.add('exam:$term');
    return const BridgeRoutedExamArrangement(
      data: BridgeExamArrangement(
        arranged: [
          BridgeExam(courseName: '已安排', startTime: '开始待定', examSeatNo: 'A-03'),
        ],
        notArranged: [BridgeExam(courseName: '未安排', endTime: '结束待定')],
      ),
      route: _webVpnRoute,
    );
  }

  @override
  Future<BridgeRoutedGrades> grades({required String term}) async {
    calls.add('grades:$term');
    return const BridgeRoutedGrades(
      data: BridgeGradeData(
        termCode: 'term',
        grades: [
          BridgeGrade(
            courseName: '成绩课程',
            score: '通过',
            gradePoint: '优秀',
            credit: 2.5,
          ),
          BridgeGrade(courseCode: 'pending'),
        ],
      ),
      route: _webVpnRoute,
    );
  }

  @override
  Future<BridgeRoutedClassroomQuery> classroomSearch({
    required int campus,
    required String date,
  }) async {
    calls.add('rooms:$campus/$date');
    return const BridgeRoutedClassroomQuery(
      data: BridgeClassroomQuery(
        code: 0,
        message: '',
        floors: [
          BridgeClassroomFloor(
            name: '主楼三层',
            rooms: [
              BridgeClassroomInfo(
                id: 'room-3',
                floorId: 'F03',
                name: '三号教室',
                availableSections: '3, 13',
              ),
              BridgeClassroomInfo(
                id: 'room-13',
                floorId: 'F03',
                name: '十三号教室',
                availableSections: '13',
              ),
            ],
          ),
        ],
      ),
      route: _webVpnRoute,
    );
  }
}

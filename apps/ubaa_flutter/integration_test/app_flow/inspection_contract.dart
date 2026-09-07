part of '../app_flow_test.dart';

/// 巡检数据必须遵守输入和结果合同，避免用错误假数据掩盖界面问题。
void registerInspectionBackendTests() {
  Future<_InspectionBackend> ready({String state = 'normal'}) async {
    final backend = _InspectionBackend(state: state);
    await backend.login(
      const LoginInput(username: 'fixture', password: 'fixture'),
    );
    return backend;
  }

  test('巡检座位查询目标保留每次分区日期时段', () async {
    final backend = await ready();
    for (final area in ['area-1', 'area-2']) {
      final result = await backend.loadFeatureQuery(
        FeatureId.libbook,
        FeatureQuery(
          view: FeatureQueryView.libbookSeats,
          areaId: area,
          date: DateTime(2026, 9, 10),
          segment: '8',
          startTime: '14:00',
          endTime: '16:00',
        ),
      );
      final action = result.details.single.action<LibbookReserveAction>()!;
      expect(action.areaId, area);
      expect(action.day, '2026-09-10');
      expect(action.segment, '8');
      expect(action.startTime, '14:00');
      expect(action.endTime, '16:00');
    }
  });

  test('巡检场馆目标保留站点与日期', () async {
    final backend = await ready();
    for (final site in [3, 7]) {
      final result = await backend.loadFeatureQuery(
        FeatureId.cgyy,
        FeatureQuery(
          view: FeatureQueryView.cgyyDayInfo,
          siteId: site,
          date: DateTime(2026, 9, 12),
        ),
      );
      final action = result.details.single.action<CgyyReserveAction>()!;
      expect(action.venueSiteId, site);
      expect(action.reservationDate, '2026-09-12');
    }
  });

  test('巡检大量记录的分页容量总数和末页一致', () async {
    final backend = await ready(state: 'many');
    final pages = <FeatureResult>[];
    for (var page = 1; page <= 3; page++) {
      pages.add(
        await backend.loadFeatureQuery(
          FeatureId.libbook,
          FeatureQuery(
            view: FeatureQueryView.libbookBookings,
            page: page,
            size: 20,
          ),
        ),
      );
    }
    expect(pages[0].details, hasLength(20));
    expect(pages[1].details, hasLength(20));
    expect(pages[0].details.first.title, isNot(pages[1].details.first.title));
    expect(pages[0].pagination?.hasMore, isTrue);
    expect(pages[1].pagination?.hasMore, isFalse);
    expect(pages[2].isEmpty, isTrue);
    expect(pages[2].pagination?.total, 40);
    final bykc = await backend.loadFeatureQuery(
      FeatureId.bykc,
      const FeatureQuery(page: 1, size: 10),
    );
    expect(bykc.details, hasLength(10));
    expect(bykc.pagination?.total, 40);
  });

  test('巡检场馆订单沿用用户可见的一基页码', () async {
    final backend = await ready(state: 'many');
    final first = await backend.loadFeatureQuery(
      FeatureId.cgyy,
      const FeatureQuery(view: FeatureQueryView.cgyyOrders, page: 1, size: 20),
    );
    final second = await backend.loadFeatureQuery(
      FeatureId.cgyy,
      const FeatureQuery(view: FeatureQueryView.cgyyOrders, page: 2, size: 20),
    );
    expect(first.pagination?.page, 1);
    expect(first.pagination?.hasMore, isTrue);
    expect(second.pagination?.page, 2);
    expect(second.details, hasLength(20));
    expect(first.details.first.title, isNot(second.details.first.title));
  });

  test('巡检希冀批量按真实选择键顺序返回', () async {
    final backend = await ready();
    const keys = [
      JudgeAssignmentQueryKey(courseId: 'course-b', assignmentId: 'job-2'),
      JudgeAssignmentQueryKey(courseId: 'course-a', assignmentId: 'job-1'),
    ];
    final result = await backend.loadFeatureQuery(
      FeatureId.judge,
      const FeatureQuery(
        view: FeatureQueryView.judgeBatchDetails,
        judgeKeys: keys,
      ),
    );
    final assignments = result.details
        .where((detail) => detail.fields.any((f) => f.label == '作业编号'))
        .toList();
    expect(
      assignments.map(
        (d) => d.fields.firstWhere((f) => f.label == '作业编号').value,
      ),
      ['job-2', 'job-1'],
    );
    expect(
      assignments.map(
        (d) => d.fields.firstWhere((f) => f.label == '课程编号').value,
      ),
      ['course-b', 'course-a'],
    );
  });

  test('巡检签到按提交事实过滤未签到与已签到', () async {
    final backend = await ready();
    const completed = FeatureQuery(view: FeatureQueryView.signinCompleted);
    const pending = FeatureQuery(view: FeatureQueryView.signinPending);
    expect(
      (await backend.loadFeatureQuery(FeatureId.signin, completed)).isEmpty,
      isTrue,
    );
    final intent = await backend.prepareSigninPerform(
      courseId: 'signin-course',
    );
    await backend.commitWrite(intent.intentId);
    expect(
      (await backend.loadFeatureQuery(FeatureId.signin, pending)).isEmpty,
      isTrue,
    );
    expect(
      (await backend.loadFeatureQuery(FeatureId.signin, completed)).details,
      hasLength(1),
    );
  });

  test('巡检评教提交后待评清空且原路线回读显示已评', () async {
    final backend = await ready();
    final before = await backend.loadFeature(FeatureId.evaluation);
    final target = before.details.single
        .action<EvaluationSubmitAction>()!
        .target!;
    final intent = await backend.prepareEvaluationSubmitCourses([target]);
    await backend.commitWrite(intent.intentId);
    expect(
      (await backend.loadFeatureQuery(
        FeatureId.evaluation,
        const FeatureQuery(view: FeatureQueryView.evaluationPending),
      )).isEmpty,
      isTrue,
    );
    final after = await backend.loadEvaluationOnRoute(
      route: ConnectionMode.direct,
    );
    expect(
      after.details.single.fields.firstWhere((f) => f.label == '状态').value,
      '已评',
    );
    expect(
      after.details.single.action<EvaluationSubmitAction>()?.eligibility,
      isNot(ActionEligibility.allowed),
    );
  });
}

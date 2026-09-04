part of '../bridge_backend_characterization_test.dart';

void registerBridgeBackendReadCharacterization() {
  test('博雅摘要详情和已选记录只投影各自 typed 写能力', () async {
    final backend = BridgeBackend(_CharacterizationBridgeClient());

    final summary = await backend.loadFeatureQuery(
      FeatureId.bykc,
      const FeatureQuery(),
    );
    final detail = await backend.loadFeatureQuery(
      FeatureId.bykc,
      const FeatureQuery(view: FeatureQueryView.bykcDetail, courseId: '42'),
    );
    final chosen = await backend.loadFeatureQuery(
      FeatureId.bykc,
      const FeatureQuery(view: FeatureQueryView.bykcChosenCourses),
    );

    final summaryAction = summary.details.single.action<BykcSelectAction>();
    expect(summaryAction?.courseId, 101);
    expect(summaryAction?.eligibility, ActionEligibility.allowed);
    expect(summary.details.single.actions.whereType<BykcSignAction>(), isEmpty);

    final detailAction = detail.details.single.action<BykcSelectAction>();
    expect(detailAction?.courseId, 42);
    expect(detailAction?.eligibility, ActionEligibility.denied);
    final detailDeselectAction = detail.details.single
        .action<BykcDeselectAction>();
    expect(detailDeselectAction?.courseId, 42);
    expect(detailDeselectAction?.eligibility, ActionEligibility.allowed);
    expect(detail.details.single.actions.whereType<BykcSignAction>(), isEmpty);

    final chosenAction = chosen.details.single.action<BykcDeselectAction>();
    expect(chosenAction?.courseId, 9527);
    expect(chosenAction?.eligibility, ActionEligibility.allowed);
    final chosenSignActions = chosen.details.single.actions
        .whereType<BykcSignAction>()
        .toList(growable: false);
    expect(chosenSignActions, hasLength(2));
    expect(chosenSignActions.map((action) => action.courseId), <int>[
      9527,
      9527,
    ]);
    expect(chosenSignActions.map((action) => action.kind), <BykcSignKind>[
      BykcSignKind.signIn,
      BykcSignKind.signOut,
    ]);
    expect(
      chosenSignActions.map((action) => action.eligibility),
      <ActionEligibility>[ActionEligibility.allowed, ActionEligibility.denied],
    );
    final renamedChosen = FeatureDetail(
      title: chosen.details.single.title,
      fields: chosen.details.single.fields
          .map(
            (field) => FeatureField(
              label: '展示名-${field.label}',
              value: '展示值-${field.value}',
            ),
          )
          .toList(growable: false),
      actions: chosen.details.single.actions,
    );
    expect(renamedChosen.action<BykcDeselectAction>()?.courseId, 9527);
    expect(
      renamedChosen.actions.whereType<BykcSignAction>().map(
        (action) => (action.courseId, action.signType),
      ),
      <(int, int)>[(9527, 1), (9527, 2)],
    );

    final renamedDisplayDetail = FeatureDetail(
      title: detail.details.single.title,
      fields: detail.details.single.fields
          .map(
            (field) =>
                FeatureField(label: '展示名-${field.label}', value: field.value),
          )
          .toList(growable: false),
      actions: detail.details.single.actions,
    );
    expect(renamedDisplayDetail.action<BykcSelectAction>()?.courseId, 42);
    expect(
      renamedDisplayDetail.action<BykcSelectAction>()?.eligibility,
      ActionEligibility.denied,
    );
    expect(renamedDisplayDetail.action<BykcDeselectAction>()?.courseId, 42);
  });

  test('三十二项读取完整转发参数路线分页并仅投影白名单字段', () async {
    final client = _CharacterizationBridgeClient();
    final backend = BridgeBackend(client);
    final results = <FeatureResult>[];

    final chosen = await backend.loadFeatureQuery(
      FeatureId.bykc,
      const FeatureQuery(view: FeatureQueryView.bykcChosenCourses),
    );
    results.add(chosen);
    results.add(
      await backend.loadFeatureQuery(
        FeatureId.bykc,
        const FeatureQuery(view: FeatureQueryView.bykcDetail, courseId: '42'),
      ),
    );
    final bykcPage = await backend.loadFeatureQuery(
      FeatureId.bykc,
      const FeatureQuery(page: 0, size: 101),
    );
    results.add(bykcPage);
    final profile = await backend.loadFeatureQuery(
      FeatureId.bykc,
      const FeatureQuery(view: FeatureQueryView.bykcProfile),
    );
    results.add(profile);
    results.add(
      await backend.loadFeatureQuery(
        FeatureId.bykc,
        const FeatureQuery(view: FeatureQueryView.bykcStatistics),
      ),
    );
    results.add(
      await backend.loadFeatureQuery(
        FeatureId.cgyy,
        FeatureQuery(
          view: FeatureQueryView.cgyyDayInfo,
          siteId: 7,
          date: DateTime(2026, 9, 4),
        ),
      ),
    );
    results.add(
      await backend.loadFeatureQuery(
        FeatureId.cgyy,
        const FeatureQuery(view: FeatureQueryView.cgyyLockCode),
      ),
    );
    results.add(
      await backend.loadFeatureQuery(
        FeatureId.cgyy,
        const FeatureQuery(view: FeatureQueryView.cgyyOrderDetail, orderId: 9),
      ),
    );
    final cgyyPage = await backend.loadFeatureQuery(
      FeatureId.cgyy,
      const FeatureQuery(
        view: FeatureQueryView.cgyyOrders,
        page: -2,
        size: 500,
      ),
    );
    results.add(cgyyPage);
    results.add(
      await backend.loadFeatureQuery(
        FeatureId.cgyy,
        const FeatureQuery(view: FeatureQueryView.cgyyPurposeTypes),
      ),
    );
    final sites = await backend.loadFeatureQuery(
      FeatureId.cgyy,
      const FeatureQuery(),
    );
    results.add(sites);
    results.add(
      await backend.loadFeatureQuery(
        FeatureId.classroom,
        FeatureQuery(campus: 2, date: DateTime(2026, 9, 4)),
      ),
    );
    results.add(
      await backend.loadFeatureQuery(
        FeatureId.evaluation,
        const FeatureQuery(),
      ),
    );
    results.add(
      await backend.loadFeatureQuery(
        FeatureId.exam,
        const FeatureQuery(term: '2026-fall'),
      ),
    );
    results.add(
      await backend.loadFeatureQuery(
        FeatureId.grades,
        const FeatureQuery(term: '2026-fall'),
      ),
    );
    results.add(
      await backend.loadFeatureQuery(
        FeatureId.judge,
        const FeatureQuery(
          view: FeatureQueryView.judgeDetail,
          courseId: 'course-1',
          assignmentId: 'assignment-1',
        ),
      ),
    );
    results.add(
      await backend.loadFeatureQuery(
        FeatureId.judge,
        const FeatureQuery(
          view: FeatureQueryView.judgeBatchDetails,
          judgeKeys: <JudgeAssignmentQueryKey>[
            JudgeAssignmentQueryKey(
              courseId: 'course-2',
              assignmentId: 'assignment-2',
            ),
            JudgeAssignmentQueryKey(
              courseId: 'course-3',
              assignmentId: 'assignment-3',
            ),
          ],
        ),
      ),
    );
    results.add(
      await backend.loadFeatureQuery(
        FeatureId.judge,
        const FeatureQuery(includeExpired: true),
      ),
    );
    results.add(
      await backend.loadFeatureQuery(
        FeatureId.libbook,
        const FeatureQuery(
          view: FeatureQueryView.libbookAreaDetail,
          areaId: 'area-1',
        ),
      ),
    );
    results.add(
      await backend.loadFeatureQuery(
        FeatureId.libbook,
        FeatureQuery(
          view: FeatureQueryView.libbookAreas,
          premisesId: 'premises-1',
          storeyId: 'storey-1',
          date: DateTime(2026, 9, 4),
        ),
      ),
    );
    final libbookPage = await backend.loadFeatureQuery(
      FeatureId.libbook,
      const FeatureQuery(
        view: FeatureQueryView.libbookBookings,
        page: 2,
        size: 0,
      ),
    );
    results.add(libbookPage);
    results.add(
      await backend.loadFeatureQuery(
        FeatureId.libbook,
        FeatureQuery(date: DateTime(2026, 9, 4)),
      ),
    );
    results.add(
      await backend.loadFeatureQuery(
        FeatureId.libbook,
        FeatureQuery(
          view: FeatureQueryView.libbookSeats,
          areaId: 'area-1',
          date: DateTime(2026, 9, 4),
          startTime: '08:00',
          endTime: '10:00',
        ),
      ),
    );
    results.add(
      await backend.loadFeatureQuery(
        FeatureId.schedule,
        const FeatureQuery(view: FeatureQueryView.scheduleTerms),
      ),
    );
    results.add(
      await backend.loadFeatureQuery(
        FeatureId.schedule,
        const FeatureQuery(view: FeatureQueryView.scheduleToday),
      ),
    );
    results.add(
      await backend.loadFeatureQuery(
        FeatureId.schedule,
        const FeatureQuery(
          view: FeatureQueryView.scheduleWeek,
          term: '2026-fall',
          week: 4,
        ),
      ),
    );
    results.add(
      await backend.loadFeatureQuery(
        FeatureId.schedule,
        const FeatureQuery(
          view: FeatureQueryView.scheduleWeeks,
          term: '2026-fall',
        ),
      ),
    );
    results.add(
      await backend.loadFeatureQuery(FeatureId.signin, const FeatureQuery()),
    );
    results.add(
      await backend.loadFeatureQuery(
        FeatureId.spoc,
        const FeatureQuery(
          view: FeatureQueryView.spocDetail,
          assignmentId: 'spoc-1',
        ),
      ),
    );
    results.add(
      await backend.loadFeatureQuery(FeatureId.spoc, const FeatureQuery()),
    );
    results.add(
      await backend.loadFeatureQuery(FeatureId.ygdk, const FeatureQuery()),
    );
    final ygdkPage = await backend.loadFeatureQuery(
      FeatureId.ygdk,
      const FeatureQuery(view: FeatureQueryView.ygdkRecords, page: 3, size: 77),
    );
    results.add(ygdkPage);

    expect(client.calls, <String>[
      'bykcChosenCourses',
      'bykcCourseDetail:id=42',
      'bykcCourses:page=1,size=100,all=true',
      'bykcProfile',
      'bykcStatistics',
      'cgyyDayInfo:siteId=7,date=2026-09-04',
      'cgyyLockCode',
      'cgyyOrderDetail:id=9',
      'cgyyOrders:page=1,size=100',
      'cgyyPurposeTypes',
      'cgyySites',
      'classroomSearch:campus=2,date=2026-09-04',
      'evaluationAll',
      'examArrangement:term=2026-fall',
      'grades:term=2026-fall',
      'judgeAssignment:courseId=course-1,assignmentId=assignment-1',
      'judgeAssignmentDetails:keys=course-2/assignment-2,course-3/assignment-3',
      'judgeAssignments:includeExpired=true',
      'libbookAreaDetail:areaId=area-1',
      'libbookAreas:premisesId=premises-1,storeyId=storey-1,day=2026-09-04',
      'libbookBookings:page=2,limit=1',
      'libbookLibraries:day=2026-09-04',
      'libbookSeats:areaId=area-1,day=2026-09-04,startTime=08:00,endTime=10:00',
      'scheduleTerms',
      'scheduleToday',
      'scheduleWeek:term=2026-fall,week=4',
      'scheduleWeeks:term=2026-fall',
      'signinToday',
      'spocAssignment:assignmentId=spoc-1',
      'spocAssignments',
      'ygdkOverview',
      'ygdkRecords:page=3,size=77',
    ]);
    expect(results, hasLength(32));
    expect(
      results.map((result) => result.resolvedRoute).toSet(),
      <ConnectionMode?>{ConnectionMode.webvpn},
    );
    const expectedProjectionFragments = <String>[
      '课程 ID|9527',
      '状态|available',
      '课程分页',
      '学号|student-placeholder',
      '要求数量|2',
      '空间组 ID|10',
      '门锁状态',
      '订单编号|9',
      '订单编号|101',
      '用途编号|2',
      '站点 ID|7',
      '可用节次|1,2',
      '任务 ID|task-read-1',
      '地点|主楼 101',
      '成绩|95',
      '作业编号|assignment-1',
      '作业编号|assignment-2',
      '进度|0/1',
      '可用日期|2026-09-04',
      '空闲座位|3',
      '预约 ID|booking-read-1',
      '馆 ID|library-read-1',
      '座位 ID|seat-read-1',
      '学期编码|2026-fall',
      '地点|主楼 101',
      '地点|主楼 102',
      '周次|4',
      '课程 ID|signin-read-1',
      '作业编号|spoc-1',
      '课程编号|course-spoc-1',
      '项目编号|7',
      '图片数量|2',
    ];
    expect(expectedProjectionFragments, hasLength(32));
    for (var index = 0; index < results.length; index += 1) {
      expect(results[index].isEmpty, isFalse, reason: client.calls[index]);
      expect(
        _resultText(results[index]),
        contains(expectedProjectionFragments[index]),
        reason: client.calls[index],
      );
    }
    expect(
      <List<int?>>[
        <int?>[
          bykcPage.pagination?.page,
          bykcPage.pagination?.size,
          bykcPage.pagination?.total,
          bykcPage.pagination?.totalPages,
        ],
        <int?>[
          cgyyPage.pagination?.page,
          cgyyPage.pagination?.size,
          cgyyPage.pagination?.total,
          cgyyPage.pagination?.totalPages,
        ],
        <int?>[
          libbookPage.pagination?.page,
          libbookPage.pagination?.size,
          libbookPage.pagination?.total,
        ],
        <int?>[
          ygdkPage.pagination?.page,
          ygdkPage.pagination?.size,
          ygdkPage.pagination?.total,
        ],
      ],
      <List<int>>[
        <int>[1, 100, 201, 3],
        <int>[1, 100, 201, 3],
        <int>[2, 1, 9],
        <int>[3, 77, 9],
      ],
    );

    final chosenText = _resultText(chosen);
    final profileText = _resultText(profile);
    final sitesText = _resultText(sites);
    expect(chosenText, contains('指定位置（1 处）'));
    expect(chosenText, isNot(anyOf(contains('39.9901'), contains('116.3001'))));
    expect(profileText, isNot(contains('employee-secret')));
    expect(sitesText, isNot(contains('telephone-secret')));
  });
}

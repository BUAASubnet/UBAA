part of '../bridge_backend_characterization_test.dart';

void registerBykcPresentationTests() {
  test('博雅课程保留时间容量和typed详情导航，不由展示状态改变资格', () async {
    final client = _BoyaPresentationClient();
    final result = await BridgeBackend(
      client,
    ).loadFeatureQuery(FeatureId.bykc, const FeatureQuery(page: 2, size: 5));
    final detail = result.details.single;
    expect(detail.presentation, isNotNull);
    final dynamic p = detail.presentation;
    expect(p.id, 101);
    expect(p.courseStartDate, '2026-09-09 08:00:00');
    expect(p.courseEndDate, '2026-09-09 10:00:00');
    expect(p.courseSelectStartDate, '2026-09-01 08:00:00');
    expect(p.courseCurrentCount, 3);
    expect(p.courseMaxCount, 3);
    expect(p.selected, isNull);
    expect(p.isDetail, isFalse);
    expect(detail.readNavigation?.query.courseId, '101');
    expect(detail.readNavigation?.query.view, FeatureQueryView.bykcDetail);
    expect(
      detail.action<BykcSelectAction>()?.eligibility,
      ActionEligibility.unknown,
    );
    expect(client.calls, ['bykcCourses:page=2,size=5,all=true']);
    expect(result.pagination?.page, 2);
  });
  test('博雅详情使用公开课程结构，未选和未知资格不补签到动作', () async {
    final result = await BridgeBackend(_CharacterizationBridgeClient())
        .loadFeatureQuery(
          FeatureId.bykc,
          const FeatureQuery(view: FeatureQueryView.bykcDetail, courseId: '42'),
        );
    final d = result.details.single;
    expect(d.presentation, isNotNull);
    expect((d.presentation as dynamic).isDetail, isTrue);
    expect(d.readNavigation, isNull);
    expect(d.actions.whereType<BykcSignAction>(), isEmpty);
    expect(d.action<BykcSelectAction>()?.eligibility, ActionEligibility.denied);
  });
  test('博雅已选记录保留考勤考核与课程目标，记录ID不能代替课程ID', () async {
    final result = await BridgeBackend(_CharacterizationBridgeClient())
        .loadFeatureQuery(
          FeatureId.bykc,
          const FeatureQuery(view: FeatureQueryView.bykcChosenCourses),
        );
    final d = result.details.single;
    expect(d.presentation, isNotNull);
    final dynamic p = d.presentation;
    expect(p.recordId, 9001);
    expect(p.courseId, 9527);
    expect(p.checkin, 0);
    expect(p.pass, isNull);
    expect(p.signPointCount, 1);
    expect(d.actions.whereType<BykcSignAction>().map((a) => a.courseId), [
      9527,
      9527,
    ]);
    expect(d.action<BykcDeselectAction>()?.courseId, 9527);
  });
  test('博雅统计总次数独立保留，不能由分类数或通过数量重算', () async {
    final result = await BridgeBackend(_BoyaPresentationClient())
        .loadFeatureQuery(
          FeatureId.bykc,
          const FeatureQuery(view: FeatureQueryView.bykcStatistics),
        );
    expect(result.details, hasLength(2));
    final dynamic total = result.details.first.presentation;
    expect(total.totalValidCount, 0);
    final dynamic category = result.details.last.presentation;
    expect(category.passedCount, 9);
    expect(category.requiredCount, 1);
    expect(category.qualified, isFalse);
  });
  test('博雅空分类仍保留总次数未知，资料不新增employeeId', () async {
    final backend = BridgeBackend(
      _CharacterizationBridgeClient(emptyReads: true),
    );
    final statistics = await backend.loadFeatureQuery(
      FeatureId.bykc,
      const FeatureQuery(view: FeatureQueryView.bykcStatistics),
    );
    expect(statistics.isEmpty, isFalse);
    expect(statistics.details, hasLength(1));
    expect(
      (statistics.details.single.presentation as dynamic).totalValidCount,
      isNull,
    );
    final profile = await backend.loadFeatureQuery(
      FeatureId.bykc,
      const FeatureQuery(view: FeatureQueryView.bykcProfile),
    );
    expect(profile.details.single.presentation, isNotNull);
    expect(
      (profile.details.single.presentation as dynamic).collegeName,
      '测试学院',
    );
    expect(
      profile.details.single.fields.map((f) => f.value),
      isNot(contains('employee-secret')),
    );
  });
}

class _BoyaPresentationClient extends _CharacterizationBridgeClient {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #bykcCourses) {
      calls.add(_describeReadCall(invocation));
      return Future.value(
        BridgeRoutedBykcCourses(
          route: _webVpnRoute,
          data: BridgeBykcCoursePage(
            content: const [
              BridgeBykcCourse(
                id: 101,
                courseName: '合成课程',
                courseStartDate: '2026-09-09 08:00:00',
                courseEndDate: '2026-09-09 10:00:00',
                courseSelectStartDate: '2026-09-01 08:00:00',
                courseCurrentCount: 3,
                courseMaxCount: 3,
                status: BridgeBykcCourseStatus.available,
                selectEligibility: BridgeActionEligibility.unknown,
                deselectEligibility: BridgeActionEligibility.denied,
              ),
            ],
            number: invocation.namedArguments[#page] as int,
            size: invocation.namedArguments[#size] as int,
            totalElements: 20,
            totalPages: 4,
          ),
        ),
      );
    }
    if (invocation.memberName == #bykcStatistics) {
      return Future.value(
        const BridgeRoutedBykcStatistics(
          route: _webVpnRoute,
          data: BridgeBykcStatistics(
            totalValidCount: 0,
            categories: [
              BridgeBykcStatistic(
                categoryName: '博雅课程',
                subCategoryName: '美育',
                passedCount: 9,
                requiredCount: 1,
                qualified: false,
              ),
            ],
          ),
        ),
      );
    }
    return super.noSuchMethod(invocation);
  }
}

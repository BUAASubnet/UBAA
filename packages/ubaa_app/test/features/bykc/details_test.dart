import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('新目录只读方法保留typed分类校区点数和服务器分页', () async {
    final client = _DetailClient();
    final result = await BridgeBackend(
      client,
    ).loadFeatureQuery(FeatureId.bykc, const FeatureQuery(page: 2, size: 10));
    expect(client.calls, ['bykcCourseCatalog']);
    final course =
        result.details.single.presentation! as BykcCoursePresentation;
    expect(course.category, BykcCourseCategory.boya);
    expect(course.subCategory, BykcCourseSubCategory.unknown);
    expect(course.categoryDisplayName, '未知类型');
    expect(course.audienceCampuses, ['未指定校区']);
    expect(course.hasSignPoints, isTrue);
    expect(course.selected, isNull);
    expect(result.pagination?.total, 61);
    expect(result.pagination?.page, 2);
    expect(client.arguments, {'page': 2, 'size': 10, 'all': true});
  });
  test('完整详情保留空窗口和零考勤且显示对象不生成签到资格', () async {
    final client = _DetailClient(selected: true);
    final result = await BridgeBackend(client).loadFeatureQuery(
      FeatureId.bykc,
      const FeatureQuery(view: FeatureQueryView.bykcDetail, courseId: '71'),
    );
    expect(client.calls, ['bykcCourseFullDetail']);
    final detail = result.details.single;
    final course = detail.presentation! as BykcCoursePresentation;
    expect(course.isDetail, isTrue);
    final supplement = course.supplement!;
    expect(supplement.courseContact, '合成联系人');
    expect(supplement.courseContactMobile, '000-TEST-01');
    expect(supplement.organizerCollegeName, '合成开课单位');
    expect(supplement.descriptionPlainText, '纯文本\n第二行');
    expect(supplement.audienceColleges, ['合成学院']);
    expect(supplement.audienceTerms, isEmpty);
    expect(supplement.audienceGroups, ['合成人群']);
    expect(supplement.signConfig?.signPointCount, 0);
    expect(supplement.signConfig?.signEndDate, isNull);
    expect(supplement.attendance?.recordId, 7001);
    expect(supplement.attendance?.checkin, 0);
    expect(supplement.attendance?.pass, isNull);
    expect(detail.actions.whereType<BykcSignAction>(), isEmpty);
    expect(
      detail.readNavigation?.query.view,
      FeatureQueryView.bykcChosenCourses,
    );
    expect(
      detail.action<BykcDeselectAction>()?.eligibility,
      ActionEligibility.unknown,
    );
    expect(detail.fields.any((f) => f.value == '000-TEST-01'), isFalse);
  });
  test('已选详情组合独立记录和完整补充，补查身份不覆盖动作源', () async {
    final client = _DetailClient(selected: true);
    final result = await BridgeBackend(client).loadFeatureQuery(
      FeatureId.bykc,
      const FeatureQuery(
        view: FeatureQueryView.bykcChosenCourses,
        courseId: '71',
      ),
    );
    expect(client.calls, ['bykcChosenCourses', 'bykcCourseFullDetail']);
    final detail = result.details.single;
    final record = detail.presentation! as BykcChosenPresentation;
    expect(record.recordId, 7002);
    expect(record.courseId, 71);
    expect(record.checkin, 5);
    expect(record.pass, isNull);
    expect(record.fullDetail?.supplement?.attendance?.recordId, 7001);
    expect(record.fullDetail?.supplement?.attendance?.checkin, 0);
    expect(
      detail.actions.whereType<BykcSignAction>().map((a) => a.eligibility),
      [ActionEligibility.unknown, ActionEligibility.unknown],
    );
    expect(detail.action<BykcDeselectAction>()?.courseId, 71);
  });
  test('已选详情补充失败或两次读取路线不同均失败而不是保留旧动作', () async {
    for (final client in [
      _DetailClient(failFull: true),
      _DetailClient(otherRoute: true),
    ]) {
      await expectLater(
        BridgeBackend(client).loadFeatureQuery(
          FeatureId.bykc,
          const FeatureQuery(
            view: FeatureQueryView.bykcChosenCourses,
            courseId: '71',
          ),
        ),
        throwsA(isA<BackendException>()),
      );
      expect(client.calls, ['bykcChosenCourses', 'bykcCourseFullDetail']);
    }
    final invalid = _DetailClient();
    await expectLater(
      BridgeBackend(invalid).loadFeatureQuery(
        FeatureId.bykc,
        const FeatureQuery(
          view: FeatureQueryView.bykcChosenCourses,
          courseId: '0',
        ),
      ),
      throwsA(isA<BackendException>()),
    );
    expect(invalid.calls, isEmpty);
  });

  test('完整详情补查失败不得调用旧详情降级成功', () async {
    final client = _DetailClient(failFull: true);
    await expectLater(
      BridgeBackend(client).loadFeatureQuery(
        FeatureId.bykc,
        const FeatureQuery(view: FeatureQueryView.bykcDetail, courseId: '71'),
      ),
      throwsA(isA<BackendException>()),
    );
    expect(client.calls, ['bykcCourseFullDetail']);
  });
}

const _route = BridgeRouteDecision(
  policy: BridgeRoutePolicy.direct,
  resolvedRoute: BridgeConnectionMode.direct,
  network: BridgeNetworkState.unknown,
  initialRoute: BridgeConnectionMode.direct,
  usedFallback: false,
);

class _DetailClient implements BridgeClient {
  @override
  int contractVersion() => 41;
  _DetailClient({
    this.selected,
    this.failFull = false,
    this.otherRoute = false,
  });
  final bool? selected;
  final bool failFull, otherRoute;
  final calls = <String>[];
  Map<String, Object?> arguments = {};
  BridgeBykcCourse get course => BridgeBykcCourse(
    id: 71,
    courseName: '合成课程',
    selected: selected,
    status: BridgeBykcCourseStatus.available,
    selectEligibility: BridgeActionEligibility.unknown,
    deselectEligibility: BridgeActionEligibility.unknown,
  );
  BridgeBykcCourseCatalogItem get item => BridgeBykcCourseCatalogItem(
    course: course,
    category: BridgeBykcCourseCategory.boya,
    subCategory: BridgeBykcCourseSubCategory.unknown,
    audienceCampuses: const ['未指定校区'],
    hasSignPoints: true,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString().split('"')[1];
    calls.add(name);
    if (invocation.memberName == #bykcCourseCatalog ||
        invocation.memberName == #bykcCourses) {
      arguments = {
        'page': invocation.namedArguments[#page],
        'size': invocation.namedArguments[#size],
        'all': invocation.namedArguments[#all],
      };
      if (invocation.memberName == #bykcCourses) {
        return Future.value(
          BridgeRoutedBykcCourses(
            route: _route,
            data: BridgeBykcCoursePage(
              content: [course],
              totalElements: 61,
              totalPages: 7,
              size: 10,
              number: 2,
            ),
          ),
        );
      }
      return Future.value(
        BridgeRoutedBykcCourseCatalog(
          route: _route,
          data: BridgeBykcCourseCatalogPage(
            content: [item],
            totalElements: 61,
            totalPages: 7,
            size: 10,
            number: 2,
          ),
        ),
      );
    }
    if (invocation.memberName == #bykcChosenCourses) {
      return Future.value(
        const BridgeRoutedBykcChosenCourses(
          route: _route,
          data: [
            BridgeBykcChosenCourse(
              id: 7002,
              courseId: 71,
              courseName: '合成具体记录',
              checkin: 5,
              signEligibility: BridgeActionEligibility.unknown,
              signOutEligibility: BridgeActionEligibility.unknown,
              deselectEligibility: BridgeActionEligibility.allowed,
            ),
          ],
        ),
      );
    }
    if (invocation.memberName == #bykcCourseDetail) {
      return Future.value(BridgeRoutedBykcCourse(route: _route, data: course));
    }
    if (invocation.memberName == #bykcCourseFullDetail) {
      if (failFull)
        return Future<BridgeRoutedBykcCourseFullDetail>.error(
          const BackendException(UbaaErrorCode.upstreamChanged),
        );
      return Future.value(
        BridgeRoutedBykcCourseFullDetail(
          route: otherRoute
              ? const BridgeRouteDecision(
                  policy: BridgeRoutePolicy.webVpn,
                  resolvedRoute: BridgeConnectionMode.webVpn,
                  network: BridgeNetworkState.unknown,
                  initialRoute: BridgeConnectionMode.webVpn,
                  usedFallback: false,
                )
              : _route,
          data: BridgeBykcCourseFullDetail(
            course: item,
            courseContact: '合成联系人',
            courseContactMobile: '000-TEST-01',
            organizerCollegeName: '合成开课单位',
            descriptionPlainText: '纯文本\n第二行',
            audienceColleges: const ['合成学院'],
            audienceTerms: const [],
            audienceGroups: const ['合成人群'],
            signConfig: const BridgeBykcSignDisplayConfig(signPointCount: 0),
            attendance: const BridgeBykcCourseAttendanceDisplay(
              recordId: 7001,
              courseId: 71,
              checkin: 0,
            ),
          ),
        ),
      );
    }
    return super.noSuchMethod(invocation);
  }
}

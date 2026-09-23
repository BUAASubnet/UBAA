import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_bindings/src/rust/frb_generated.dart' show RustLibApi;
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  setUp(() => _Cache.hasDetail = true);
  test('博雅详情错ID保留同查询旧缓存且没有旧值时拒绝', () async {
    final backend = BridgeBackend(_Client(), configDirectory: '/synthetic');
    await backend.openOfflineAccount(
      const LocalAccount(id: 'synthetic', username: 'synthetic'),
      List.filled(32, 1),
    );
    const query = FeatureQuery(
      view: FeatureQueryView.bykcDetail,
      courseId: '42',
    );
    final result = await backend.loadFeatureQuery(FeatureId.bykc, query);
    expect(result.details.single.title, '合成详情');
    expect(result.details.single.actions, isEmpty);
    expect(result.evidence!.origin, DataOrigin.persisted);
    expect(result.evidence!.complete, isFalse);
    _Cache.hasDetail = false;
    await expectLater(
      backend.loadFeatureQuery(FeatureId.bykc, query),
      throwsA(
        isA<BackendException>().having(
          (e) => e.code,
          '错归属',
          UbaaErrorCode.upstreamChanged,
        ),
      ),
    );
  });
  test('其余博雅查询与首页已选保留范围并剥离学校动作', () async {
    final backend = BridgeBackend(_Client(), configDirectory: '/synthetic');
    await backend.openOfflineAccount(
      const LocalAccount(id: 'synthetic', username: 'synthetic'),
      List.filled(32, 1),
    );
    for (final query in [
      const FeatureQuery(view: FeatureQueryView.bykcDetail, courseId: '42'),
      const FeatureQuery(view: FeatureQueryView.bykcProfile),
      const FeatureQuery(view: FeatureQueryView.bykcStatistics),
      const FeatureQuery(view: FeatureQueryView.bykcChosenCourses),
    ]) {
      final read = await backend.readCachedQuery(
        FeatureId.bykc,
        query,
        RoutePolicy.direct,
      );
      expect(read.projection!.details, isNotEmpty);
      expect(read.projection!.details.expand((v) => v.actions), isEmpty);
    }
    final home = await backend.readCachedHome(RoutePolicy.direct);
    final chosen = home.single.toSnapshot();
    expect(chosen.readContext?.query?.view, FeatureQueryView.bykcChosenCourses);
    expect(
      (chosen.overview as BykcChosenOverview).semesterStart,
      '2026-09-01 00:00:00',
    );
    expect(
      (chosen.details.single.presentation as BykcChosenPresentation)
          .signPointCount,
      isNull,
    );
    expect(
      chosen.details.single.fields.any(
        (v) => v.label == '可签到' || v.label == '可签退',
      ),
      isFalse,
    );
  });

  setUpAll(() => RustLib.initMock(api: _Api()));
  test('博雅缓存保留原分页与只读详情导航，在线动作和既定回读独立', () async {
    final client = _Client();
    final backend = BridgeBackend(client, configDirectory: '/synthetic');
    await backend.openOfflineAccount(
      const LocalAccount(id: 'synthetic', username: 'synthetic'),
      List.filled(32, 1),
    );
    final cached = await backend.readCachedQuery(
      FeatureId.bykc,
      const FeatureQuery(page: 2, size: 20),
      RoutePolicy.direct,
    );
    expect(cached.projection, isNotNull);
    final snapshot = cached.projection!.toSnapshot();
    expect(snapshot.pagination?.page, 2);
    expect(snapshot.pagination?.total, 21);
    expect(snapshot.details.single.actions, isEmpty);
    expect(snapshot.details.single.readNavigation?.query.courseId, '42');
    expect(_Cache.requestPage, 2);
    final fresh = await backend.loadFeatureQuery(
      FeatureId.bykc,
      const FeatureQuery(page: 2, size: 20),
    );
    expect(
      fresh.details.single.actions
          .whereType<BykcSelectAction>()
          .single
          .eligibility,
      ActionEligibility.allowed,
    );
    expect(fresh.pagination?.page, 2);
    expect(fresh.evidence!.origin, DataOrigin.online);
    expect(client.cachedReads, 1);
    await (backend as BykcReadbackBackend).readBykcAfterWrite(
      const FeatureQuery(),
    );
    expect(client.cachedReads, 1);
    expect(client.plainReads, 1);
  });
}

const route = BridgeRouteDecision(
  policy: BridgeRoutePolicy.direct,
  resolvedRoute: BridgeConnectionMode.direct,
  network: BridgeNetworkState.unknown,
  initialRoute: BridgeConnectionMode.direct,
  usedFallback: false,
);
const course = BridgeBykcCourse(
  id: 42,
  courseName: '合成课程',
  status: BridgeBykcCourseStatus.available,
  selectEligibility: BridgeActionEligibility.allowed,
  deselectEligibility: BridgeActionEligibility.denied,
);
const coursePage = BridgeBykcCoursePage(
  content: [course],
  number: 1,
  size: 20,
  totalElements: 21,
  totalPages: 2,
);

class _Api implements RustLibApi {
  @override
  Future<BridgeOfflineCache> crateApiOfflineBridgeOfflineCacheOpen({
    required String configDir,
    required String accountId,
    required String expectedIdentity,
    required List<int> key,
  }) async => _Cache();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cache implements BridgeOfflineCache {
  @override
  Future<BridgeCachedCgyyOrdersRecord?> readCgyyOrders({
    required BridgeConnectionMode route,
    required int page,
    required int size,
  }) async => null;

  static int? requestPage;
  static bool hasDetail = true;
  @override
  Future<BridgeCachedBykcDetailRecord?> readBykcDetail({
    required BridgeConnectionMode route,
    required int courseId,
  }) async => !hasDetail
      ? null
      : BridgeCachedBykcDetailRecord(
          data: BridgeCachedBykcCourse(
            id: courseId,
            courseName: '合成详情',
            status: BridgeBykcCourseStatus.available,
          ),
          sourceRoute: route,
          fetchedAt: 100,
          complete: true,
        );
  @override
  Future<BridgeCachedBykcProfileRecord?> readBykcProfile({
    required BridgeConnectionMode route,
  }) async => BridgeCachedBykcProfileRecord(
    data: const BridgeBykcUserProfile(id: 1, realName: '合成姓名'),
    sourceRoute: route,
    fetchedAt: 100,
    complete: true,
  );
  @override
  Future<BridgeCachedBykcStatisticsRecord?> readBykcStatistics({
    required BridgeConnectionMode route,
  }) async => BridgeCachedBykcStatisticsRecord(
    data: const BridgeBykcStatistics(totalValidCount: 3, categories: []),
    sourceRoute: route,
    fetchedAt: 100,
    complete: true,
  );
  @override
  Future<BridgeCachedBykcChosenRecord?> readBykcChosen({
    required BridgeConnectionMode route,
  }) async => BridgeCachedBykcChosenRecord(
    data: const BridgeCachedBykcChosen(
      semesterStart: '2026-09-01 00:00:00',
      semesterEnd: '2027-01-31 23:59:59',
      courses: [
        BridgeCachedBykcChosenCourse(
          id: 1,
          courseId: 42,
          courseName: '合成已选',
          signWindow: BridgeCachedBykcSignWindow(
            hasPoints: true,
            signStartDate: '2026-09-22 08:00:00',
          ),
        ),
      ],
    ),
    sourceRoute: route,
    fetchedAt: 100,
    complete: true,
  );
  @override
  Future<BridgeCachedToday?> readToday({
    required BridgeConnectionMode route,
  }) async => null;
  @override
  Future<BridgeCachedJudge?> readJudge({
    required BridgeConnectionMode route,
    required bool includeExpired,
  }) async => null;
  @override
  Future<BridgeCachedHomeSignin?> readHomeSignin({
    required BridgeConnectionMode route,
  }) async => null;
  @override
  Future<BridgeCachedHomeSpoc?> readHomeSpoc({
    required BridgeConnectionMode route,
  }) async => null;
  @override
  Future<BridgeCachedHomeYgdk?> readHomeYgdk({
    required BridgeConnectionMode route,
  }) async => null;

  @override
  Future<void> activate() async {}
  @override
  Future<BridgeCachedBykcCoursesRecord?> readBykcCourses({
    required BridgeConnectionMode route,
    required int page,
    required int size,
    required bool all,
  }) async {
    requestPage = page;
    return const BridgeCachedBykcCoursesRecord(
      data: BridgeCachedBykcCoursePage(
        content: [
          BridgeCachedBykcCourse(
            id: 42,
            courseName: '合成课程',
            status: BridgeBykcCourseStatus.available,
          ),
        ],
        number: 1,
        size: 20,
        totalElements: 21,
        totalPages: 2,
      ),
      sourceRoute: BridgeConnectionMode.direct,
      fetchedAt: 100,
      complete: true,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements BridgeClient {
  int cachedReads = 0, plainReads = 0;
  @override
  Future<BridgeBykcDetailRefresh> bykcDetailCached({
    required BridgeOfflineCache cache,
    required int courseId,
  }) async => const BridgeBykcDetailRefresh(
    data: BridgeBykcCourse(
      id: 88,
      courseName: '别的课程',
      status: BridgeBykcCourseStatus.available,
      selectEligibility: BridgeActionEligibility.allowed,
      deselectEligibility: BridgeActionEligibility.denied,
    ),
    route: route,
    state: BridgeBykcRefreshState(
      fetchedAt: 200,
      saveError: BridgeCacheFailure.invalidInput,
    ),
  );

  @override
  int contractVersion() => 33;
  @override
  Future<BridgeBykcCoursesRefresh> bykcCoursesCached({
    required BridgeOfflineCache cache,
    required int page,
    required int size,
    required bool all,
  }) async {
    cachedReads++;
    return const BridgeBykcCoursesRefresh(
      data: coursePage,
      route: route,
      state: BridgeBykcRefreshState(fetchedAt: 200),
    );
  }

  @override
  Future<BridgeRoutedBykcCourses> bykcCourses({
    required int page,
    required int size,
    required bool all,
  }) async {
    plainReads++;
    return const BridgeRoutedBykcCourses(data: coursePage, route: route);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

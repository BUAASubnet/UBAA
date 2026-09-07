part of '../app_controller_test.dart';

void _registerReadContextTests() {
  test('三种固定路线回读开始使父缓存失效且结果携带对应查询归属', () async {
    final evaluation = AppController(backend: _EvaluationBackend());
    final ygdk = AppController(
      backend: _YgdkReadbackBackend(
        overview: const FeatureResult.empty(
          resolvedRoute: ConnectionMode.direct,
        ),
        records: const FeatureResult.empty(
          resolvedRoute: ConnectionMode.direct,
        ),
      ),
    );
    final cgyy = AppController(
      backend: _CgyyCancelReadbackBackend(
        (_) async =>
            const FeatureResult.empty(resolvedRoute: ConnectionMode.direct),
      ),
    );
    addTearDown(evaluation.dispose);
    addTearDown(ygdk.dispose);
    addTearDown(cgyy.dispose);
    final evaluationRun = evaluation.refreshEvaluationAfterWrite(
      expectedRoute: ConnectionMode.direct,
    );
    final ygdkRun = ygdk.refreshYgdkAfterWrite(
      expectedRoute: ConnectionMode.direct,
    );
    final cgyyRun = cgyy.verifyCgyyCancellation(
      orderId: 1,
      expectedRoute: ConnectionMode.direct,
    );
    for (final controller in [evaluation, ygdk, cgyy]) {
      expect(controller.readCacheEpoch, greaterThan(0));
    }
    await evaluationRun;
    await ygdkRun;
    await cgyyRun;
    expect(
      evaluation.snapshots[FeatureId.evaluation]!.readContext?.query?.view,
      FeatureQueryView.summary,
    );
    expect(
      ygdk.ygdkReadbackState.overview.readContext?.query?.view,
      FeatureQueryView.summary,
    );
    expect(
      ygdk.ygdkReadbackState.records.readContext?.query?.view,
      FeatureQueryView.ygdkRecords,
    );
    expect(ygdk.ygdkReadbackState.records.readContext?.query?.page, 1);
    expect(
      cgyy.snapshots[FeatureId.cgyy]!.readContext?.query?.view,
      FeatureQueryView.cgyyOrders,
    );
    expect(cgyy.snapshots[FeatureId.cgyy]!.readContext?.query?.page, 0);
  });

  test('学期成功后周次失败清旧数据且结果归属周次参数', () async {
    final backend = _QueryBackend(
      onQuery: (_, query) {
        if (query.view == FeatureQueryView.scheduleWeeks) {
          throw const BackendException(UbaaErrorCode.networkError);
        }
        return const FeatureResult.success(
          summary: '学期数据',
          details: [FeatureDetail(title: '旧学期')],
          resolvedRoute: ConnectionMode.direct,
          pagination: FeaturePagination(page: 1, size: 20, total: 1),
        );
      },
    );
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.refreshFeatureQuery(
      FeatureId.schedule,
      const FeatureQuery(view: FeatureQueryView.scheduleTerms),
    );
    await controller.refreshFeatureQuery(
      FeatureId.schedule,
      const FeatureQuery(
        view: FeatureQueryView.scheduleWeeks,
        term: '2026-2027-1',
      ),
    );
    final snapshot = controller.snapshots[FeatureId.schedule]!;
    expect(snapshot.status, FeatureLoadStatus.failure);
    expect(snapshot.details, isEmpty);
    expect(snapshot.summary, isNull);
    expect(snapshot.pagination, isNull);
    expect(snapshot.resolvedRoute, isNull);
    expect(snapshot.readContext?.query?.view, FeatureQueryView.scheduleWeeks);
    expect(snapshot.readContext?.query?.term, '2026-2027-1');
    expect(snapshot.readContext?.requestRevision, 2);
  });

  test('同参数失败保留stale但读取revision更新', () async {
    var calls = 0;
    final controller = AppController(
      backend: _QueryBackend(
        onQuery: (_, query) {
          if (++calls > 1)
            throw const BackendException(UbaaErrorCode.networkError);
          return const FeatureResult.success(
            summary: '同一查询数据',
            details: [FeatureDetail(title: '旧课程')],
          );
        },
      ),
    );
    addTearDown(controller.dispose);
    const query = FeatureQuery(
      view: FeatureQueryView.scheduleWeek,
      term: 'term',
      week: 3,
    );
    await controller.refreshFeatureQuery(FeatureId.schedule, query);
    await controller.refreshFeatureQuery(FeatureId.schedule, query);
    final snapshot = controller.snapshots[FeatureId.schedule]!;
    expect(snapshot.status, FeatureLoadStatus.stale);
    expect(snapshot.details.single.title, '旧课程');
    expect(snapshot.readContext?.hasSameQuery(query), isTrue);
    expect(snapshot.readContext?.requestRevision, 2);
  });

  test('默认读取与显式summary不同且全局失效代次覆盖首页路线和写后读取', () async {
    final controller = AppController(backend: _RefreshMatrixBackend());
    addTearDown(controller.dispose);
    final initial = controller.readCacheEpoch;
    await controller.refreshHome(only: [FeatureId.schedule]);
    expect(controller.readCacheEpoch, greaterThan(initial));
    final context = controller.snapshots[FeatureId.schedule]!.readContext;
    expect(context, isNotNull);
    expect(context!.query, isNull);
    expect(context.hasSameQuery(const FeatureQuery()), isFalse);
    final homeEpoch = controller.readCacheEpoch;
    await controller.refreshFeatureQuery(
      FeatureId.schedule,
      const FeatureQuery(),
    );
    expect(controller.readCacheEpoch, homeEpoch);
    expect(
      controller.snapshots[FeatureId.schedule]!.readContext?.query,
      isNotNull,
    );
    await controller.setRoutePolicy(RoutePolicy.direct);
    expect(controller.readCacheEpoch, greaterThan(homeEpoch));
    final routeEpoch = controller.readCacheEpoch;
    await controller.refreshAfterWrite(WriteOperation.libbookReserve);
    expect(controller.readCacheEpoch, greaterThan(routeEpoch));
    expect(
      controller.snapshots[FeatureId.libbook]!.readContext?.query?.view,
      FeatureQueryView.libbookBookings,
    );
  });
}

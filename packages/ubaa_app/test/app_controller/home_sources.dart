part of '../app_controller_test.dart';

void _registerHomeSourceTests() {
  test('领域新查询不丢弃并行的首页默认结果，也不回写覆盖领域', () async {
    final backend = _HomeSourcesBackend();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.refreshHome(only: [FeatureId.spoc]);
    final gate = Completer<FeatureResult>();
    backend.defaultPending = gate;
    final home = controller.refreshHome(only: [FeatureId.spoc]);
    await controller.refreshFeatureQuery(
      FeatureId.spoc,
      const FeatureQuery(
        view: FeatureQueryView.spocDetail,
        assignmentId: 'detail',
      ),
    );
    gate.complete(
      const FeatureResult.success(
        details: [FeatureDetail(title: '合成新首页作业')],
        resolvedRoute: ConnectionMode.direct,
      ),
    );
    await home;
    expect(
      controller.homeSnapshots[FeatureId.spoc]!.status,
      FeatureLoadStatus.success,
    );
    expect(
      controller.homeSnapshots[FeatureId.spoc]!.details.single.title,
      '合成新首页作业',
    );
    expect(
      controller.snapshots[FeatureId.spoc]!.readContext!.query!.view,
      FeatureQueryView.spocDetail,
    );
  });

  test('首页保留默认今日和作业来源，领域单项查询不覆盖首页', () async {
    final backend = _HomeSourcesBackend();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.refreshHome(only: [FeatureId.spoc]);
    final home = controller.homeSnapshots[FeatureId.spoc];
    expect(home?.status, FeatureLoadStatus.success);
    await controller.refreshFeatureQuery(
      FeatureId.spoc,
      const FeatureQuery(view: FeatureQueryView.spocDetail, assignmentId: 'a'),
    );
    expect(controller.homeSnapshots[FeatureId.spoc], same(home));
    expect(
      controller.snapshots[FeatureId.spoc]!.readContext!.query!.view,
      FeatureQueryView.spocDetail,
    );
    await controller.logout();
    expect(
      controller.homeSnapshots.values.every((s) => s.details.isEmpty),
      isTrue,
    );
  });
  test('首页额外读取合并同代请求，不覆盖领域当前查询', () async {
    final gate = Completer<FeatureResult>();
    final backend = _HomeSourcesBackend()..pending = gate;
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.refreshHome(only: [FeatureId.bykc]);
    final before = controller.snapshots[FeatureId.bykc];
    final a = controller.loadHomeSupplement(HomeSupplement.bykcChosen);
    final b = controller.loadHomeSupplement(HomeSupplement.bykcChosen);
    expect(backend.queries, hasLength(1));
    gate.complete(
      const FeatureResult.success(
        details: [FeatureDetail(title: '合成已选')],
        resolvedRoute: ConnectionMode.direct,
      ),
    );
    expect((await a).details, hasLength(1));
    expect(await b, same(await a));
    await controller.loadHomeSupplement(HomeSupplement.bykcChosen);
    expect(backend.queries, hasLength(1));
    expect(controller.snapshots[FeatureId.bykc], same(before));
  });
  test('首页新代请求不被旧代完成清掉，注销后不允许额外读', () async {
    final old = Completer<FeatureResult>(), fresh = Completer<FeatureResult>();
    final backend = _HomeSourcesBackend()..pending = old;
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    final a = controller.loadHomeSupplement(HomeSupplement.cgyyOrders);
    await controller.refreshHome(only: [FeatureId.grades]);
    backend.pending = fresh;
    final b = controller.loadHomeSupplement(HomeSupplement.cgyyOrders);
    old.complete(const FeatureResult.empty());
    expect((await a).error?.code, UbaaErrorCode.operationConflict);
    final c = controller.loadHomeSupplement(HomeSupplement.cgyyOrders);
    expect(backend.queries, hasLength(2));
    fresh.complete(
      const FeatureResult.empty(resolvedRoute: ConnectionMode.webvpn),
    );
    expect((await b).resolvedRoute, ConnectionMode.webvpn);
    expect(await c, same(await b));
    await controller.logout();
    expect(
      (await controller.loadHomeSupplement(
        HomeSupplement.cgyyOrders,
      )).error?.code,
      UbaaErrorCode.authenticationRequired,
    );
    expect(backend.queries, hasLength(2));
  });
  test('首页周次使用明确当前学期，未标当前周不能猜第一周', () async {
    final backend = _HomeSourcesBackend();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    final result = await controller.loadHomeSupplement(
      HomeSupplement.currentWeek,
    );
    expect(backend.queries.map((q) => q.view), [
      FeatureQueryView.scheduleTerms,
      FeatureQueryView.scheduleWeeks,
    ]);
    expect(backend.queries.last.term, 'synthetic-term');
    expect(result.details.single.presentation, isA<WeekPresentation>());
    expect((result.details.single.presentation as WeekPresentation).number, 12);
    backend.noCurrentWeek = true;
    final missing = await controller.loadHomeSupplement(
      HomeSupplement.currentWeek,
      forceRefresh: true,
    );
    expect(missing.isEmpty, isTrue);
  });
}

class _HomeSourcesBackend extends _QueryBackend {
  _HomeSourcesBackend() : super(onQuery: (_, _) => const FeatureResult.empty());
  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;
  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'synthetic-home');
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      defaultPending?.future ??
      const FeatureResult.success(details: [FeatureDetail(title: '合成首页来源')]);
  Completer<FeatureResult>? defaultPending;
  final queries = <FeatureQuery>[];
  Completer<FeatureResult>? pending;
  bool noCurrentWeek = false;
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    queries.add(query);
    if (pending case final gate?) return gate.future;
    if (query.view == FeatureQueryView.scheduleTerms)
      return const FeatureResult.success(
        details: [
          FeatureDetail(
            title: '合成学期',
            presentation: TermPresentation(
              code: 'synthetic-term',
              selected: true,
              index: 1,
            ),
          ),
        ],
      );
    if (query.view == FeatureQueryView.scheduleWeeks)
      return FeatureResult.success(
        details: [
          FeatureDetail(
            title: '合成周',
            presentation: WeekPresentation(
              requestTerm: 'synthetic-term',
              responseTerm: 'synthetic-term',
              number: 12,
              current: !noCurrentWeek,
              startDate: '2026-03-23',
              endDate: '2026-03-29',
            ),
          ),
        ],
        resolvedRoute: ConnectionMode.direct,
      );
    return const FeatureResult.success(details: [FeatureDetail(title: '合成详情')]);
  }
}

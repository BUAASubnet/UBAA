part of '../app_controller_test.dart';

void _registerCgyyPurposeTests() {
  test('研讨室用途独立读取合并并发且不覆盖原时段快照', () async {
    final gate = Completer<FeatureResult>();
    final backend = _PurposeBackend(() => gate.future);
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.refreshHome(only: [FeatureId.cgyy]);
    final before = controller.snapshots[FeatureId.cgyy];
    final api = controller;
    final Future<FeatureResult> first = api.loadCgyyPurposes();
    final Future<FeatureResult> second = api.loadCgyyPurposes();
    expect(backend.calls, 1);
    gate.complete(_purposeResult());
    expect(await first, same(await second));
    expect((await api.loadCgyyPurposes()).resolvedRoute, ConnectionMode.webvpn);
    expect(backend.calls, 1);
    expect(controller.snapshots[FeatureId.cgyy], same(before));
  });
  test('研讨室用途失败不缓存且保留原key及回退来源', () async {
    var calls = 0;
    final controller = AppController(
      backend: _PurposeBackend(() {
        if (++calls == 1)
          throw const BackendException(UbaaErrorCode.networkError);
        return Future.value(_purposeResult());
      }),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final api = controller;
    expect(
      (await api.loadCgyyPurposes()).error?.code,
      UbaaErrorCode.networkError,
    );
    final FeatureResult result = await api.loadCgyyPurposes();
    final p = result.details.single.presentation! as CgyyPurposePresentation;
    expect(p.key, 37);
    expect(p.isStaticFallback, isTrue);
    expect(() => result.details.clear(), throwsUnsupportedError);
    expect(calls, 2);
  });
  for (final route in [false, true]) {
    test('研讨室用途在${route ? '换路线' : '注销'}后拒绝迟到结果', () async {
      final gate = Completer<FeatureResult>();
      final controller = AppController(
        backend: _PurposeBackend(() => gate.future),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final api = controller;
      final Future<FeatureResult> pending = api.loadCgyyPurposes();
      if (route) {
        await controller.setRoutePolicy(RoutePolicy.direct);
      } else {
        await controller.logout();
      }
      gate.complete(_purposeResult());
      expect((await pending).error?.code, UbaaErrorCode.operationConflict);
    });
  }
}

FeatureResult _purposeResult() => const FeatureResult.success(
  resolvedRoute: ConnectionMode.webvpn,
  details: [
    FeatureDetail(
      title: '错误展示编号999',
      presentation: CgyyPurposePresentation(
        key: 37,
        name: '合成研讨',
        isStaticFallback: true,
      ),
    ),
  ],
);

class _PurposeBackend extends _QueryBackend {
  _PurposeBackend(this.load)
    : super(onQuery: (_, _) => const FeatureResult.empty());
  final Future<FeatureResult> Function() load;
  int calls = 0;
  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;
  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'synthetic');
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) {
    expect(feature, FeatureId.cgyy);
    expect(query.view, FeatureQueryView.cgyyPurposeTypes);
    calls++;
    return load();
  }
}

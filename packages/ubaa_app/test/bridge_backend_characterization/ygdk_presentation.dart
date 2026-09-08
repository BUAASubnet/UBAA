part of '../bridge_backend_characterization_test.dart';

void registerYgdkPresentationTests() {
  test('阳光显式首页按概览实际路线读取同页记录，后台和固定回读不增加请求', () async {
    final client = _CharacterizationBridgeClient();
    final backend = BridgeBackend(client);
    final background = await backend.loadFeature(FeatureId.ygdk);
    expect(client.calls, ['ygdkOverview']);
    expect((background.overview as dynamic).records, isNull);
    client.calls.clear();
    final home = await backend.loadFeatureQuery(
      FeatureId.ygdk,
      const FeatureQuery(page: 2, size: 5),
    );
    expect(client.calls, [
      'ygdkOverview',
      'ygdkRecordsOnRoute:route=webVpn,page=2,size=5',
    ]);
    final dynamic records = (home.overview as dynamic).records;
    expect(records.page, 2);
    expect(records.size, 5);
    expect(records.total, 9);
    expect(records.content.single.recordId, 101);
    expect(records.errorCode, isNull);
    expect(home.resolvedRoute, ConnectionMode.webvpn);
    expect(home.details.single.action<YgdkSubmitAction>()?.itemId, 7);
  });
  test('阳光首页记录失败保留概要且不伪造空成功，认证失败仍向外传播', () async {
    final client = _YgdkRecordsErrorClient();
    final backend = BridgeBackend(client);
    final result = await backend.loadFeatureQuery(
      FeatureId.ygdk,
      const FeatureQuery(),
    );
    expect((result.overview as dynamic).termCount, 0);
    expect(
      (result.overview as dynamic).records.errorCode,
      UbaaErrorCode.networkError,
    );
    expect(result.resolvedRoute, ConnectionMode.webvpn);
    client.recordError = const BridgeError(
      code: BridgeErrorCode.authenticationRequired,
      message: '敏感原文不应显示',
      kind: BridgeErrorKind.authentication,
      retryable: false,
    );
    await expectLater(
      backend.loadFeatureQuery(FeatureId.ygdk, const FeatureQuery()),
      throwsA(
        isA<BackendException>().having(
          (e) => e.code,
          'code',
          UbaaErrorCode.authenticationRequired,
        ),
      ),
    );
  });
  test('阳光空项目仍保留学期周月公开概要，零与未知不混同', () async {
    final client = _CharacterizationBridgeClient(
      ygdkOverviewFixture: const BridgeYgdkOverview(
        summary: BridgeYgdkTermSummary(
          termId: 11,
          termName: '合成学期',
          termCount: 0,
          termTarget: null,
          weekCount: 0,
          weekTarget: 3,
          monthCount: null,
          monthTarget: 9,
          dayCount: 0,
          goodCount: 4,
        ),
        classifyId: 31,
        classifyName: '合成体育',
        defaultItemId: 99,
        defaultItemName: '合成默认项目',
        items: [],
      ),
    );
    final result = await BridgeBackend(client).loadFeature(FeatureId.ygdk);
    expect(result.overview, isNotNull);
    final dynamic p = result.overview;
    expect(p.termCount, 0);
    expect(p.termTarget, isNull);
    expect(p.weekCount, 0);
    expect(p.weekTarget, 3);
    expect(p.monthCount, isNull);
    expect(p.monthTarget, 9);
    expect(p.dayCount, 0);
    expect(p.goodCount, 4);
    expect(p.defaultItemId, 99);
    expect(result.details, isEmpty);
    expect(result.isEmpty, isFalse);
    expect(client.calls, ['ygdkOverview']);
  });
  test('阳光项目typed投影不替代原独立提交目标，固定回读保留相同概要', () async {
    final client = _CharacterizationBridgeClient();
    final backend = BridgeBackend(client);
    final result = await backend.loadFeature(FeatureId.ygdk);
    final pinned = await backend.loadYgdkOverviewOnRoute(
      route: ConnectionMode.direct,
    );
    for (final value in [result, pinned]) {
      expect(value.overview, isNotNull);
      expect((value.overview as dynamic).classifyId, 31);
      expect(value.details.single.presentation, isNotNull);
      expect((value.details.single.presentation as dynamic).itemId, 7);
      expect(value.details.single.action<YgdkSubmitAction>()?.classifyId, 31);
    }
    expect(pinned.resolvedRoute, ConnectionMode.direct);
    expect(client.calls, ['ygdkOverview', 'ygdkOverviewOnRoute:route=direct']);
  });
  test('阳光记录投影只含公开计数与原始状态，普通及固定分页不漂移', () async {
    final client = _CharacterizationBridgeClient();
    final backend = BridgeBackend(client);
    final normal = await backend.loadFeatureQuery(
      FeatureId.ygdk,
      const FeatureQuery(view: FeatureQueryView.ygdkRecords, page: 2, size: 5),
    );
    final pinned = await backend.loadYgdkRecordsOnRoute(
      route: ConnectionMode.direct,
      page: 2,
      size: 5,
    );
    for (final result in [normal, pinned]) {
      expect(result.details.single.presentation, isNotNull);
      final dynamic p = result.details.single.presentation;
      expect(p.recordId, 101);
      expect(p.itemId, 7);
      expect(p.imageCount, 2);
      expect(p.isOpen, isFalse);
      expect(p.state, isNull);
      expect(result.pagination?.page, 2);
      expect(result.pagination?.size, 5);
      expect(result.pagination?.total, 9);
      expect(result.details.single.actions, isEmpty);
    }
    expect(client.calls, [
      'ygdkRecords:page=2,size=5',
      'ygdkRecordsOnRoute:route=direct,page=2,size=5',
    ]);
  });
}

class _YgdkRecordsErrorClient extends _CharacterizationBridgeClient {
  BridgeError recordError = const BridgeError(
    code: BridgeErrorCode.networkError,
    message: '敏感原文不应显示',
    kind: BridgeErrorKind.network,
    retryable: true,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #ygdkRecordsOnRoute) {
      calls.add(_describeReadCall(invocation));
      return Future<BridgeCallerPinnedYgdkRecords>.error(recordError);
    }
    return super.noSuchMethod(invocation);
  }
}

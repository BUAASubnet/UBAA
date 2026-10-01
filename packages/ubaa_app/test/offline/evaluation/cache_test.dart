import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_bindings/src/rust/frb_generated.dart' show RustLibApi;
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  setUpAll(() => RustLib.initMock(api: _Api()));
  test('评教缓存保留集合进度和待评视图身份但没有提交动作', () async {
    final backend = await _backend(_Client());
    for (final view in [
      FeatureQueryView.summary,
      FeatureQueryView.evaluationPending,
    ]) {
      final result = await backend.readCachedQuery(
        FeatureId.evaluation,
        FeatureQuery(view: view),
        RoutePolicy.direct,
      );
      expect(result.projection, isNotNull);
      expect(result.projection!.readContext.query!.view, view);
      expect(result.projection!.overview, isA<EvaluationProgressOverview>());
      expect(
        result.projection!.details.length,
        view == FeatureQueryView.summary ? 2 : 1,
      );
      expect(result.projection!.details.expand((v) => v.actions), isEmpty);
    }
  });
  test('评教部分刷新保留旧课程与时间，首次部分不冒称旧缓存', () async {
    final client = _Client()..partial = true;
    final backend = await _backend(client);
    var value = await backend.loadFeature(FeatureId.evaluation);
    expect(value.details.first.title, '已保存课程');
    expect(value.evidence!.origin, DataOrigin.persisted);
    expect(value.evidence!.complete, isFalse);
    expect(value.evidence!.fetchedAt.millisecondsSinceEpoch, 100000);
    expect(value.details.expand((v) => v.actions), isEmpty);
    client.firstPartial = true;
    value = await backend.loadFeature(FeatureId.evaluation);
    expect(value.details.first.title, '线上课程');
    expect(value.evidence!.origin, DataOrigin.online);
    expect(value.evidence!.complete, isFalse);
    expect(value.details.expand((v) => v.actions), isEmpty);
  });
  test('完整线上资格仍可投影，固定路线写后回读不进入缓存恢复', () async {
    final client = _Client();
    final backend = await _backend(client);
    final value = await backend.loadFeature(FeatureId.evaluation);
    expect(
      value.details.first.action<EvaluationSubmitAction>()!.eligibility,
      ActionEligibility.allowed,
    );
    await (backend as EvaluationSubmissionReadbackBackend)
        .loadEvaluationOnRoute(route: ConnectionMode.webvpn);
    expect(client.cachedCalls, 1);
    expect(client.pinnedCalls, [BridgeConnectionMode.webVpn]);
  });
}

Future<BridgeBackend> _backend(_Client client) async {
  final backend = BridgeBackend(client, configDirectory: '/synthetic');
  await backend.openOfflineAccount(
    const LocalAccount(id: 'synthetic', username: 'synthetic'),
    List.filled(32, 1),
  );
  return backend;
}

const decision = BridgeRouteDecision(
  policy: BridgeRoutePolicy.direct,
  resolvedRoute: BridgeConnectionMode.direct,
  network: BridgeNetworkState.unknown,
  initialRoute: BridgeConnectionMode.direct,
  usedFallback: false,
);
const progress = BridgeEvaluationProgress(
  totalCourses: 2,
  evaluatedCourses: 1,
  pendingCourses: 1,
);
const online = BridgeEvaluationCoursesResponse(
  courses: [
    BridgeEvaluationCourse(
      id: 'rw_wj_kc_',
      kcmc: '线上课程',
      bpmc: '合成教师',
      isEvaluated: false,
      submitEligibility: BridgeActionEligibility.allowed,
      submitTarget: BridgeEvaluationSubmitTarget(
        rwid: 'rw',
        wjid: 'wj',
        kcdm: 'kc',
      ),
    ),
    BridgeEvaluationCourse(
      id: 'done',
      kcmc: '已评课程',
      bpmc: '合成教师',
      isEvaluated: true,
      submitEligibility: BridgeActionEligibility.denied,
    ),
  ],
  progress: progress,
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
  Future<void> activate() async {}
  @override
  Future<BridgeCachedEvaluationRecord?> readEvaluation({
    required BridgeConnectionMode route,
  }) async => BridgeCachedEvaluationRecord(
    data: const BridgeCachedEvaluationCourses(
      courses: [
        BridgeCachedEvaluationCourse(
          id: 'rw_wj_kc_',
          kcmc: '已保存课程',
          bpmc: '合成教师',
          isEvaluated: false,
        ),
        BridgeCachedEvaluationCourse(
          id: 'done',
          kcmc: '已评课程',
          bpmc: '合成教师',
          isEvaluated: true,
        ),
      ],
      progress: progress,
    ),
    sourceRoute: route,
    fetchedAt: 100,
    complete: true,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements BridgeClient {
  bool partial = false, firstPartial = false;
  int cachedCalls = 0;
  final pinnedCalls = <BridgeConnectionMode>[];
  @override
  int contractVersion() => 38;
  @override
  Future<BridgeEvaluationRefresh> evaluationCached({
    required BridgeOfflineCache cache,
  }) async {
    cachedCalls++;
    return BridgeEvaluationRefresh(
      data: online,
      route: decision,
      fetchedAt: 200,
      complete: !partial,
      savedForOffline: !partial || firstPartial,
      preservedPrevious: partial && !firstPartial,
    );
  }

  @override
  Future<BridgeCallerPinnedEvaluation> evaluationAllOnRoute({
    required BridgeConnectionMode route,
  }) async {
    pinnedCalls.add(route);
    return BridgeCallerPinnedEvaluation(data: online, pinnedRoute: route);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

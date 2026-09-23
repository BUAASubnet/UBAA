import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_bindings/src/rust/frb_generated.dart' show RustLibApi;
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'cache_test.dart' as fixtures;

const account = LocalAccount(id: 'synthetic', username: 'fixture-user');
void main() {
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));
  test('评教摘要必须建立可让位任务，中间无账号进度不冒称完整', () async {
    final client = EvaluationClient();
    final backend = BridgeBackend(client);
    final task = await backend.beginFeatureRead(
      FeatureId.evaluation,
      const FeatureQuery(),
    );
    expect(task, isNotNull);
    expect((await task!.next()).publish, isFalse);
    final first = await task.next();
    expect(first.finished, isFalse);
    expect(first.result.details.length, 1);
    expect(first.result.details.single.actions, isEmpty);
    expect(first.result.overview, isNull);
    expect(first.result.summary, contains('尚未核对完整'));
    final last = await task.next();
    expect(last.finished, isTrue);
    expect(last.result.details.length, 2);
    expect(
      last.result.details.first.action<EvaluationSubmitAction>()!.eligibility,
      ActionEligibility.allowed,
    );
    expect(last.result.evidence, isNull);
    task.cancel();
    expect(client.task.cancelled, isTrue);
  });
  test('缺密钥时仍带本机身份，有账号部分进度明确未完成且不声称持久', () async {
    final client = EvaluationClient();
    final backend = BridgeBackend(client);
    final task = (await backend.beginAccountFeatureRead(
      FeatureId.evaluation,
      const FeatureQuery(view: FeatureQueryView.evaluationPending),
      account,
    ))!;
    expect(client.expectedIdentity, account.username);
    await task.next();
    final first = await task.next();
    expect(first.result.evidence!.complete, isFalse);
    expect(first.result.evidence!.savedForOffline, isFalse);
    final last = await task.next();
    expect(last.result.details.length, 1);
    expect(
      (last.result.overview as EvaluationProgressOverview).totalCourses,
      2,
    );
    expect(last.result.evidence!.savedForOffline, isFalse);
  });
  test('部分批次保留旧课程并渐进追加新ID，完整后替换且保留实际保存状态', () async {
    final client = EvaluationClient();
    final backend = BridgeBackend(client, configDirectory: '/synthetic');
    await backend.openOfflineAccount(account, List.filled(32, 5));
    final task = (await backend.beginFeatureRead(
      FeatureId.evaluation,
      const FeatureQuery(),
    ))!;
    expect(client.persistent, isTrue);
    await task.next();
    final first = await task.next();
    expect(first.result.details.map((v) => v.title), ['上次课程', '线上课程']);
    expect(first.result.details.expand((v) => v.actions), isEmpty);
    expect(first.result.evidence!.origin, DataOrigin.mixed);
    expect(first.result.evidence!.fetchedAt.millisecondsSinceEpoch, 50000);
    final last = await task.next();
    expect(last.result.details.map((v) => v.title), ['线上课程', '已评课程']);
    expect(last.result.evidence!.savedForOffline, isTrue);
    expect(last.result.evidence!.fetchedAt.millisecondsSinceEpoch, 100000);
  });
  test('退出后的在途课程不可发布', () async {
    final client = EvaluationClient();
    final backend = BridgeBackend(client);
    final task = (await backend.beginFeatureRead(FeatureId.evaluation, null))!;
    client.gate = Completer<BridgeEvaluationScanBatch>();
    final pending = task.next();
    await backend.deactivateOfflineAccount();
    client.gate!.complete(client.batch(2));
    await expectLater(
      pending,
      throwsA(
        isA<BackendException>().having(
          (v) => v.code,
          '旧代次',
          UbaaErrorCode.operationConflict,
        ),
      ),
    );
  });
  test('局部网络失败保留已读行和错误分类，可由网络变化唤醒识别', () async {
    final client = EvaluationClient()..networkFailure = true;
    final backend = BridgeBackend(client);
    final task = (await backend.beginAccountFeatureRead(
      FeatureId.evaluation,
      const FeatureQuery(),
      account,
    ))!;
    await task.next();
    await task.next();
    final last = await task.next();
    expect(last.finished, isTrue);
    expect(last.result.error?.code, UbaaErrorCode.upstreamUnavailable);
    expect(last.result.details.length, 1);
    expect(last.result.details.single.actions, isEmpty);
    expect(last.result.evidence!.complete, isFalse);
    expect(last.result.evidence!.savedForOffline, isFalse);
  });
}

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
  }) async => const BridgeCachedEvaluationRecord(
    data: BridgeCachedEvaluationCourses(
      courses: [
        BridgeCachedEvaluationCourse(
          id: 'old',
          kcmc: '上次课程',
          bpmc: '合成教师',
          isEvaluated: false,
        ),
      ],
      progress: BridgeEvaluationProgress(
        totalCourses: 1,
        evaluatedCourses: 0,
        pendingCourses: 1,
      ),
    ),
    sourceRoute: BridgeConnectionMode.direct,
    fetchedAt: 50,
    complete: true,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class EvaluationTask implements BridgeEvaluationScan {
  bool cancelled = false;
  @override
  void cancel() {
    cancelled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class EvaluationClient implements BridgeClient {
  final task = EvaluationTask();
  int calls = 0;
  bool persistent = false, networkFailure = false;
  String? expectedIdentity;
  Completer<BridgeEvaluationScanBatch>? gate;
  @override
  int contractVersion() => 34;
  @override
  Future<BridgeEvaluationScan> beginEvaluationOnline({
    String? expectedIdentity,
  }) async {
    this.expectedIdentity = expectedIdentity;
    return task;
  }

  @override
  Future<BridgeEvaluationScan> beginEvaluationScan({
    required BridgeOfflineCache cache,
  }) async {
    persistent = true;
    return task;
  }

  @override
  Future<BridgeEvaluationScanBatch> nextEvaluationScan({
    required BridgeEvaluationScan task,
  }) async => gate?.future ?? batch(calls++);
  BridgeEvaluationScanBatch batch(int step) => BridgeEvaluationScanBatch(
    refresh: BridgeEvaluationRefresh(
      data: step < 2 || networkFailure
          ? BridgeEvaluationCoursesResponse(
              courses: step == 0 ? [] : [fixtures.online.courses.first],
              progress: const BridgeEvaluationProgress(
                totalCourses: 1,
                evaluatedCourses: 0,
                pendingCourses: 1,
              ),
            )
          : fixtures.online,
      route: fixtures.decision,
      fetchedAt: 100,
      complete: step >= 2 && !networkFailure,
      savedForOffline: step >= 2 && persistent && !networkFailure,
      preservedPrevious: step < 2 || networkFailure,
    ),
    error: networkFailure && step >= 2
        ? const BridgeError(
            code: BridgeErrorCode.upstreamUnavailable,
            kind: BridgeErrorKind.upstream,
            retryable: true,
            message: '合成网络失败',
            resolvedRoute: BridgeConnectionMode.direct,
          )
        : null,
    completedCourseLists: step,
    finished: step >= 2,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

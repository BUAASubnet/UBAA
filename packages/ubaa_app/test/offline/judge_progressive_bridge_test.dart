import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_bindings/src/rust/frb_generated.dart' show RustLibApi;
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  setUpAll(() => RustLib.initMock(api: _Api()));
  test('所有课程均失败且没有缓存时显示失败，不冒充空结果或有效部分内容', () async {
    final client = _Client()..allFailed = true;
    final backend = BridgeBackend(client, configDirectory: '/synthetic');
    await backend.openOfflineAccount(
      const LocalAccount(id: 'synthetic', username: 'synthetic'),
      List.filled(32, 9),
    );
    final task = (await backend.beginFeatureRead(FeatureId.judge, null))!;
    final batch = await task.next();
    expect(batch.finished, isTrue);
    expect(batch.result.details, isEmpty);
    expect(batch.result.isEmpty, isFalse);
    expect(batch.result.error?.code, UbaaErrorCode.networkError);
    expect(batch.result.evidence, isNull);
    task.cancel();
  });
  test('生产逐批投影保留旧时间、待更新标题、局部失败与完整刷新参数', () async {
    final client = _Client();
    final backend = BridgeBackend(client, configDirectory: '/synthetic');
    await backend.openOfflineAccount(
      const LocalAccount(id: 'synthetic', username: 'synthetic'),
      List.filled(32, 9),
    );
    expect(backend, isA<ProgressiveReadBackend>());
    final task = (await (backend as ProgressiveReadBackend).beginFeatureRead(
      FeatureId.judge,
      const FeatureQuery(includeExpired: true, fullRefresh: true),
    ))!;
    expect(client.options!.fullRefresh, isTrue);
    final first = await task.next();
    expect(first.finished, isFalse);
    expect(first.result.evidence!.fetchedAt.millisecondsSinceEpoch, 100000);
    expect(first.result.evidence!.origin, DataOrigin.mixed);
    expect(first.result.details.map((item) => item.title), contains('新标题待核实'));
    final pending = first.result.details.singleWhere(
      (item) => item.title == '新标题待核实',
    );
    expect(
      pending.fields.any((field) => field.label == '截止' || field.label == '进度'),
      isFalse,
    );
    final finalBatch = await task.next();
    expect(finalBatch.finished, isTrue);
    expect(finalBatch.result.details.length, 2);
    expect(finalBatch.result.error?.code, UbaaErrorCode.networkError);
    expect(finalBatch.result.evidence!.complete, isFalse);
    expect(finalBatch.result.details.expand((item) => item.actions), isEmpty);
    task.cancel();
    expect(client.task.cancelled, isTrue);
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Task implements BridgeJudgeRefreshTask {
  bool cancelled = false;
  @override
  void cancel() {
    cancelled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements BridgeClient {
  final task = _Task();
  BridgeJudgeRefreshOptions? options;
  int calls = 0;
  bool allFailed = false;
  @override
  int contractVersion() => 32;
  @override
  Future<BridgeJudgeRefreshTask> beginJudgeRefresh({
    required BridgeOfflineCache cache,
    required BridgeJudgeRefreshOptions options,
  }) async {
    this.options = options;
    return task;
  }

  @override
  Future<BridgeJudgeProgress> nextJudgeRefresh({
    required BridgeJudgeRefreshTask task,
  }) async {
    final first = !allFailed && calls++ == 0;
    return BridgeJudgeProgress(
      batch: BridgeJudgeScanBatch(
        kind: first
            ? BridgeJudgeScanKind.assignments
            : BridgeJudgeScanKind.courseFailure,
        route: const BridgeRouteDecision(
          policy: BridgeRoutePolicy.direct,
          resolvedRoute: BridgeConnectionMode.direct,
          network: BridgeNetworkState.unknown,
          initialRoute: BridgeConnectionMode.direct,
          usedFallback: false,
        ),
        courseId: '12',
        assignments: first
            ? const [
                BridgeJudgeAssignmentIndex(
                  assignmentId: '101',
                  courseId: '12',
                  courseName: '合成课程',
                  title: '新标题待核实',
                ),
              ]
            : [],
        error: first
            ? null
            : const BridgeError(
                code: BridgeErrorCode.networkError,
                kind: BridgeErrorKind.network,
                retryable: true,
                message: '合成故障',
                resolvedRoute: BridgeConnectionMode.direct,
              ),
        finished: !first,
        complete: false,
        failedCourses: first ? 0 : 1,
      ),
      summaries: [
        if (!allFailed) _summary('102', '已保存项目'),
        if (!first && !allFailed) _summary('101', '本轮合法项目'),
      ],
      summaryFetchedAt: 100,
      summaryHasCached: true,
      sourceFetchedAt: 200,
      reused: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BridgeJudgeAssignmentSummary _summary(String id, String title) =>
    BridgeJudgeAssignmentSummary(
      courseId: '12',
      courseName: '合成课程',
      assignmentId: id,
      title: title,
      totalProblems: 1,
      submittedCount: 0,
      submissionStatus: BridgeJudgeSubmissionStatus.unsubmitted,
      submissionStatusText: '未提交',
    );

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('无缓存首页从索引逐批呈现，不能退回旧长聚合或声称保存成功', () async {
    final client = OnlineClient();
    final backend = BridgeBackend(client, configDirectory: '/synthetic');
    final task = await backend.beginFeatureRead(FeatureId.judge, null);
    expect(task, isNotNull);
    final first = await task!.next();
    expect(first.finished, isFalse);
    expect(first.result.details.single.title, '合成待核实');
    expect(
      first.result.details.single.fields.any((field) => field.label == '截止'),
      isFalse,
    );
    final last = await task.next();
    expect(last.finished, isTrue);
    expect(last.result.details.single.title, '合成作业');
    expect(last.result.evidence?.savedForOffline ?? false, isFalse);
    expect(client.legacyCalls, 0);
    task.cancel();
    expect(client.task.cancelled, isTrue);
  });
  test('无缓存单详情只接受明确目标，缓存代次变化后迟到内容不能返回', () async {
    final client = OnlineClient();
    final backend = BridgeBackend(client, configDirectory: '/synthetic');
    final task = await backend.beginFeatureRead(
      FeatureId.judge,
      const FeatureQuery(
        view: FeatureQueryView.judgeDetail,
        courseId: '12',
        assignmentId: '101',
      ),
    );
    expect(task, isNotNull);
    expect(client.options!.keys!.single.assignmentId, '101');
    final first = await task!.next();
    expect(first.publish, isFalse);
    client.gate = Completer<BridgeJudgeOnlineProgress>();
    final pending = task.next();
    await backend.deactivateOfflineAccount();
    client.gate!.complete(progress(false));
    await expectLater(
      pending,
      throwsA(
        isA<BackendException>().having(
          (error) => error.code,
          '迟到代次',
          UbaaErrorCode.operationConflict,
        ),
      ),
    );
    task.cancel();
  });
  test('批量详情逐项呈现且不恢复任何写动作', () async {
    final client = OnlineClient();
    final backend = BridgeBackend(client);
    final task = await backend.beginFeatureRead(
      FeatureId.judge,
      const FeatureQuery(
        view: FeatureQueryView.judgeBatchDetails,
        judgeKeys: [
          JudgeAssignmentQueryKey(courseId: '12', assignmentId: '101'),
        ],
      ),
    );
    expect(task, isNotNull);
    expect((await task!.next()).finished, isFalse);
    final last = await task.next();
    expect(last.finished, isTrue);
    expect(last.result.details.single.actions, isEmpty);
    expect(last.result.details.single.title, '合成作业');
    expect(client.legacyCalls, 0);
    task.cancel();
  });
}

class OnlineClient implements BridgeClient {
  final task = OnlineTask();
  int legacyCalls = 0;
  int calls = 0;
  BridgeJudgeOnlineOptions? options;
  Completer<BridgeJudgeOnlineProgress>? gate;
  @override
  int contractVersion() => 37;
  @override
  Future<BridgeJudgeOnlineTask> beginJudgeOnline({
    required BridgeJudgeOnlineOptions options,
  }) async {
    this.options = options;
    return task;
  }

  @override
  Future<BridgeJudgeOnlineProgress> nextJudgeOnline({
    required BridgeJudgeOnlineTask task,
  }) async => gate?.future ?? progress(calls++ == 0);
  @override
  Future<BridgeRoutedJudgeSummaries> judgeAssignments({
    required bool includeExpired,
  }) async {
    legacyCalls++;
    throw StateError('该分段测试禁止旧聚合');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class OnlineTask implements BridgeJudgeOnlineTask {
  bool cancelled = false;
  @override
  void cancel() {
    cancelled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BridgeJudgeOnlineProgress progress(bool first) => BridgeJudgeOnlineProgress(
  fetchedAt: 100,
  summaries: first
      ? []
      : const [
          BridgeJudgeAssignmentSummary(
            courseId: '12',
            courseName: '合成课程',
            assignmentId: '101',
            title: '合成作业',
            totalProblems: 1,
            submittedCount: 0,
            submissionStatus: BridgeJudgeSubmissionStatus.unsubmitted,
            submissionStatusText: '未提交',
          ),
        ],
  batch: BridgeJudgeScanBatch(
    kind: first ? BridgeJudgeScanKind.assignments : BridgeJudgeScanKind.detail,
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
              title: '合成待核实',
            ),
          ]
        : [],
    detail: first
        ? null
        : const BridgeJudgeAssignmentDetail(
            courseId: '12',
            courseName: '合成课程',
            assignmentId: '101',
            title: '合成作业',
            totalProblems: 1,
            submittedCount: 0,
            submissionStatus: BridgeJudgeSubmissionStatus.unsubmitted,
            submissionStatusText: '未提交',
            problems: [],
          ),
    finished: !first,
    complete: !first,
    failedCourses: 0,
  ),
);

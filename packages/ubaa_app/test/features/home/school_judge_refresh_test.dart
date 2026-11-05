import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_bindings/src/rust/frb_generated.dart' show RustLibApi;
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../../support/controller/fakes.dart';

void main() {
  setUpAll(() => RustLib.initMock(api: _Api()));

  for (final joinHome in [false, true]) {
    test(
      joinHome
          ? '学校刷新与首页共享在途希冀计划，并等待详情和完整收尾'
          : '学校刷新经生产BridgeBackend读取希冀索引、详情并等待完整收尾',
      () async {
        final client = _Client();
        final bridge = BridgeBackend(client, configDirectory: '/synthetic');
        await bridge.openOfflineAccount(
          const LocalAccount(id: 'synthetic', username: 'synthetic'),
          List.filled(32, 9),
        );
        final backend = _Backend(bridge);
        final controller = AppController(backend: backend);
        addTearDown(controller.dispose);
        await controller.initialize().timeout(const Duration(seconds: 5));
        await controller
            .refreshHome(only: [FeatureId.judge])
            .timeout(const Duration(seconds: 5));
        final previousPlans = client.tasks.length;
        client.gated = true;
        final home = joinHome
            ? controller.refreshHome(only: [FeatureId.judge])
            : Future<void>.value();
        if (joinHome) await client.gatedTask.future;
        var completed = false;
        final refresh = controller.refreshSchoolAgenda().then((_) {
          completed = true;
        });
        final task = await client.gatedTask.future.timeout(
          const Duration(seconds: 5),
        );
        await task.entered[0].future.timeout(const Duration(seconds: 5));
        await backend.supplementStarted.future.timeout(
          const Duration(seconds: 5),
        );
        expect(client.tasks.length, previousPlans + 1);
        expect(client.options.last.fullRefresh, isFalse);
        expect(client.options.last.currentAssignment, isNull);
        expect(completed, isFalse);

        task.release[0].complete();
        await task.entered[1].future.timeout(const Duration(seconds: 5));
        final index = controller.homeSnapshots[FeatureId.judge]!;
        expect(index.details.single.title, '合成作业');
        expect(index.details.single.presentation, isNull);
        expect(index.status, FeatureLoadStatus.loading);
        expect(completed, isFalse);

        task.release[1].complete();
        await task.entered[2].future.timeout(const Duration(seconds: 5));
        final detail = controller.homeSnapshots[FeatureId.judge]!;
        expect(
          detail.details.single.presentation,
          isA<JudgeAssignmentPresentation>(),
        );
        expect(detail.evidence!.complete, isFalse);
        expect(completed, isFalse);

        task.release[2].complete();
        await Future.wait([home, refresh]);
        final result = controller.homeSnapshots[FeatureId.judge]!;
        expect(completed, isTrue);
        expect(client.tasks.length, previousPlans + 1);
        expect(client.legacyReads, 0);
        expect(task.calls, 3);
        expect(result.status, FeatureLoadStatus.success);
        expect(result.evidence!.complete, isTrue);
        expect(result.evidence!.savedForOffline, isTrue);
        expect(result.details.single.title, '合成作业');
        expect(result.error, isNull);
      },
    );
  }
}

class _Backend extends FixtureQueryBackend
    implements ProgressiveReadBackend, ConcurrentReadBackend {
  _Backend(this.bridge) : super(onQuery: (_, _) => const FeatureResult.empty());
  final BridgeBackend bridge;
  final supplementStarted = Completer<void>();

  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;
  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'synthetic');
  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) => feature == FeatureId.judge
      ? bridge.beginFeatureRead(feature, query)
      : Future.value();
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    if (!supplementStarted.isCompleted) supplementStarted.complete();
    return const FeatureResult.empty(resolvedRoute: ConnectionMode.direct);
  }
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

class _Client implements BridgeClient {
  final tasks = <_Task>[];
  final options = <BridgeJudgeRefreshOptions>[];
  final gatedTask = Completer<_Task>();
  bool gated = false;
  int legacyReads = 0;
  @override
  int contractVersion() => 51;
  @override
  Future<BridgeJudgeRefreshTask> beginJudgeRefresh({
    required BridgeOfflineCache cache,
    required BridgeJudgeRefreshOptions options,
  }) async {
    this.options.add(options);
    final task = _Task(gated);
    tasks.add(task);
    if (gated) gatedTask.complete(task);
    return task;
  }

  @override
  Future<BridgeJudgeProgress> nextJudgeRefresh({
    required BridgeJudgeRefreshTask task,
  }) => (task as _Task).next();
  @override
  Future<BridgeRoutedJudgeSummaries> judgeAssignments({
    required bool includeExpired,
  }) async {
    legacyReads++;
    throw StateError('渐进刷新只能通过逐批接口读取');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Task implements BridgeJudgeRefreshTask {
  _Task(this.gated);
  final bool gated;
  final entered = List.generate(3, (_) => Completer<void>());
  final release = List.generate(3, (_) => Completer<void>());
  int calls = 0;
  @override
  void cancel() {}
  Future<BridgeJudgeProgress> next() async {
    final step = calls++;
    if (gated) {
      entered[step].complete();
      await release[step].future;
    }
    final finished = !gated || step == 2;
    final hasDetail = gated && step > 0;
    return BridgeJudgeProgress(
      batch: BridgeJudgeScanBatch(
        kind: finished
            ? BridgeJudgeScanKind.finished
            : step == 0
            ? BridgeJudgeScanKind.assignments
            : BridgeJudgeScanKind.detail,
        route: const BridgeRouteDecision(
          policy: BridgeRoutePolicy.direct,
          resolvedRoute: BridgeConnectionMode.direct,
          network: BridgeNetworkState.unknown,
          initialRoute: BridgeConnectionMode.direct,
          usedFallback: false,
        ),
        courseId: '12',
        assignments: gated && step == 0
            ? const [
                BridgeJudgeAssignmentIndex(
                  courseId: '12',
                  courseName: '合成课程',
                  assignmentId: '101',
                  title: '合成作业',
                ),
              ]
            : const [],
        detail: hasDetail && !finished
            ? const BridgeJudgeAssignmentDetail(
                courseId: '12',
                courseName: '合成课程',
                assignmentId: '101',
                title: '合成作业',
                totalProblems: 1,
                submittedCount: 0,
                submissionStatus: BridgeJudgeSubmissionStatus.unsubmitted,
                submissionStatusText: '未提交',
                problems: [],
              )
            : null,
        finished: finished,
        complete: finished,
        failedCourses: 0,
      ),
      summaries: hasDetail
          ? const [
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
            ]
          : const [],
      summaryFetchedAt: 200,
      sourceFetchedAt: 200,
      summaryHasCached: false,
      reused: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_test_support/recovery.dart' as support;
import 'progressive_test.dart' show until;

void main() {
  for (final (cached, failed) in [
    (false, false),
    (true, false),
    (true, true),
  ]) {
    test('首页希冀刷新优先交付已有详情，后台读取仍完整完成：缓存=$cached，失败=$failed', () async {
      final backend = _Backend(cached, failed);
      final controller = AppController(backend: backend);
      controller.attachHomePresentation();
      addTearDown(controller.dispose);
      addTearDown(() {
        if (!backend.release.isCompleted) backend.release.complete();
      });
      await controller.initialize();
      await controller.refreshHome();
      backend.gated = true;
      var visible = false;
      var complete = false;
      final refresh = controller.refreshHomePage().then((_) => visible = true);
      await backend.entered.future;
      final all = controller
          .refreshHome(only: [FeatureId.judge])
          .then((_) => complete = true);
      await Future<void>.delayed(Duration.zero);
      expect(visible, cached);
      expect(complete, isFalse, reason: '学校日程等完整刷新仍须等待在线结果');
      expect(controller.homeSnapshots[FeatureId.judge]!.refining, cached);
      if (cached) {
        expect(
          controller.homeSnapshots[FeatureId.judge]!.details.single.title,
          '缓存作业',
        );
        expect(
          controller.homeSnapshots[FeatureId.judge]!.evidence!.fetchedAt,
          backend.old,
        );
      }
      backend.release.complete();
      await Future.wait([refresh, all]);
      await until(
        () =>
            controller.homeSnapshots[FeatureId.judge]!.status ==
            (failed ? FeatureLoadStatus.stale : FeatureLoadStatus.success),
      );
      expect(
        controller.homeSnapshots[FeatureId.judge]!.details.single.title,
        failed ? '缓存作业' : '在线作业',
      );
      expect(controller.homeSnapshots[FeatureId.judge]!.refining, isFalse);
    });
  }
}

class _Backend extends support.FakeRecoveryBackend
    implements ProgressiveReadBackend, ConcurrentReadBackend {
  _Backend(this.cached, this.failed);
  final bool cached;
  final bool failed;
  final old = DateTime.utc(2026, 11, 1);
  final entered = Completer<void>();
  final release = Completer<void>();
  bool gated = false;

  FeatureResult result(String title) => FeatureResult.success(
    details: [
      FeatureDetail(
        title: title,
        presentation: JudgeAssignmentPresentation(
          courseId: '12',
          courseName: '合成课程',
          assignmentId: '101',
          totalProblems: 1,
          submittedCount: 0,
          status: AssignmentSubmissionStatus.unsubmitted,
          statusText: '未提交',
        ),
      ),
    ],
    resolvedRoute: ConnectionMode.direct,
    evidence: DataEvidence(
      accountId: 'synthetic',
      origin: DataOrigin.persisted,
      fetchedAt: old,
      complete: true,
      savedForOffline: true,
    ),
  );

  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async {
    if (feature != FeatureId.judge || !gated) return null;
    entered.complete();
    await release.future;
    return _Task(
      failed
          ? const FeatureResult.failure(
              UiError(
                code: UbaaErrorCode.networkError,
                title: '合成断网',
                message: '合成断网',
              ),
            )
          : result('在线作业'),
    );
  }

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      feature == FeatureId.judge && cached
      ? result('缓存作业')
      : const FeatureResult.empty();
}

class _Task implements FeatureReadTask {
  _Task(this.result);
  final FeatureResult result;
  @override
  Future<FeatureReadBatch> next() async =>
      FeatureReadBatch(result, finished: true);
  @override
  void cancel() {}
}

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_test_support/recovery.dart' as support;
import '../../../reads/progressive_test.dart' show until;

void main() {
  for (final complete in [true, false]) {
    test('希冀部分批次保留旧范围和详情，最终完整=$complete按覆盖更新', () async {
      final backend = Backend();
      final controller = AppController(backend: backend);
      addTearDown(controller.dispose);
      await controller.initialize();
      await until(
        () => controller.homeSnapshots[FeatureId.judge]!.details.length == 2,
      );
      final refresh = controller.refreshHome(only: [FeatureId.judge]);
      await until(() => backend.pending.calls == 1);
      backend.pending.first.complete(
        FeatureReadBatch(
          result([
            item('1', '占位', placeholder: true),
            item('3', '新项'),
          ], complete: false),
          finished: false,
        ),
      );
      await until(() => backend.pending.calls == 2);
      for (final snapshots in [
        controller.homeSnapshots,
        controller.snapshots,
      ]) {
        final snapshot = snapshots[FeatureId.judge]!;
        expect(snapshot.details.map((d) => d.title), ['旧详情', '旧范围', '新项']);
        expect(snapshot.evidence!.origin, DataOrigin.mixed);
        expect(snapshot.evidence!.fetchedAt, DateTime.utc(2026, 9, 20));
        expect(snapshot.evidence!.complete, isFalse);
        expect(snapshot.evidence!.savedForOffline, isFalse);
        expect(
          snapshot.evidence!.cacheFailure,
          CacheMaintenanceFailure.corrupt,
        );
        expect(snapshot.details.expand((d) => d.actions), isEmpty);
      }
      backend.pending.last.complete(
        FeatureReadBatch(
          result([item('3', '新项')], complete: complete),
          finished: true,
        ),
      );
      await refresh;
      expect(
        controller.homeSnapshots[FeatureId.judge]!.details.map((d) => d.title),
        complete ? ['新项'] : ['旧详情', '旧范围', '新项'],
      );
    });
  }
  test('希冀跨路线部分结果不能混合旧路线内容', () async {
    final backend = Backend();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    await until(
      () => controller.homeSnapshots[FeatureId.judge]!.details.length == 2,
    );
    final refresh = controller.refreshHome(only: [FeatureId.judge]);
    await until(() => backend.pending.calls == 1);
    backend.pending.first.complete(
      FeatureReadBatch(
        result(
          [item('3', '新路线')],
          complete: false,
          route: ConnectionMode.webvpn,
        ),
        finished: true,
      ),
    );
    await refresh;
    expect(
      controller.homeSnapshots[FeatureId.judge]!.details.single.title,
      '新路线',
    );
    expect(
      controller.homeSnapshots[FeatureId.judge]!.resolvedRoute,
      ConnectionMode.webvpn,
    );
  });
  for (final changedQuery in [false, true]) {
    test('希冀${changedQuery ? '换查询' : '跨账号'}不合并旧投影', () async {
      final backend = Backend();
      final controller = AppController(backend: backend);
      addTearDown(controller.dispose);
      await controller.initialize();
      await until(
        () => controller.homeSnapshots[FeatureId.judge]!.details.length == 2,
      );
      final refresh = changedQuery
          ? controller.refreshFeatureQuery(
              FeatureId.judge,
              const FeatureQuery(includeExpired: true),
            )
          : controller.refreshHome(only: [FeatureId.judge]);
      await until(() => backend.pending.calls == 1);
      backend.pending.first.complete(
        FeatureReadBatch(
          result(
            [item('3', '新范围')],
            complete: false,
            account: changedQuery ? 'synthetic' : 'another-synthetic',
          ),
          finished: true,
        ),
      );
      await refresh;
      expect(
        controller.snapshots[FeatureId.judge]!.details.single.title,
        '新范围',
      );
      if (changedQuery)
        expect(
          controller.homeSnapshots[FeatureId.judge]!.details.map(
            (d) => d.title,
          ),
          ['旧详情', '旧范围'],
        );
    });
  }
}

FeatureDetail item(String id, String title, {bool placeholder = false}) =>
    FeatureDetail(
      title: title,
      presentation: placeholder
          ? null
          : JudgeAssignmentPresentation(
              courseId: '12',
              courseName: '合成课程',
              assignmentId: id,
              totalProblems: 3,
              submittedCount: 1,
              status: AssignmentSubmissionStatus.partial,
              statusText: '合成进度',
            ),
      readNavigation: FeatureReadNavigation(
        feature: FeatureId.judge,
        query: FeatureQuery(
          view: FeatureQueryView.judgeDetail,
          courseId: '12',
          assignmentId: id,
        ),
      ),
    );

FeatureResult result(
  List<FeatureDetail> details, {
  required bool complete,
  bool persisted = false,
  ConnectionMode route = ConnectionMode.direct,
  String account = 'synthetic',
}) => FeatureResult.success(
  details: details,
  resolvedRoute: route,
  evidence: DataEvidence(
    accountId: account,
    origin: persisted ? DataOrigin.persisted : DataOrigin.online,
    fetchedAt: DateTime.utc(2026, 9, persisted ? 20 : 23),
    complete: complete,
    savedForOffline: persisted,
    cacheFailure: persisted ? null : CacheMaintenanceFailure.corrupt,
  ),
);

class Backend extends support.FakeRecoveryBackend
    implements ProgressiveReadBackend, FeatureQueryBackend {
  int begins = 0;
  final pending = Task();
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async => throw StateError('必须走分段读取');
  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async {
    if (feature != FeatureId.judge) return null;
    if (begins++ > 0) return pending;
    return Task()
      ..first.complete(
        FeatureReadBatch(
          result(
            [item('1', '旧详情'), item('2', '旧范围')],
            complete: true,
            persisted: true,
          ),
          finished: true,
        ),
      );
  }
}

class Task implements FeatureReadTask {
  int calls = 0;
  final first = Completer<FeatureReadBatch>();
  final last = Completer<FeatureReadBatch>();
  @override
  Future<FeatureReadBatch> next() => calls++ == 0 ? first.future : last.future;
  @override
  void cancel() {}
}

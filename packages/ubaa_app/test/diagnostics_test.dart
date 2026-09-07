import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  test('可选遥测清理晚到失败不进入新会话诊断', () async {
    final telemetry = _DelayedFlushTelemetry();
    final controller = AppController(
      backend: DemoBackend(),
      telemetry: telemetry,
    );
    addTearDown(controller.dispose);
    final pending = controller.clearTelemetryQueue();
    await controller.logout();
    telemetry.completion.completeError(StateError('旧遥测清理失败'));
    await pending;
    expect(controller.diagnostics.records, isEmpty);
  });
  test('失效意图的后台清理失败不进入新代次诊断', () async {
    final diagnostics = LocalDiagnostics();
    final discard = Completer<void>();
    final coordinator = WriteCoordinator(
      diagnostics: diagnostics,
      commit: (_) async => throw StateError('测试不提交'),
      discard: (_) => discard.future,
    );
    addTearDown(coordinator.dispose);
    coordinator.setIntent(
      WriteIntent(
        intentId: 'fixture-intent',
        operation: WriteOperation.bykcSelectCourse,
        targetSummary: '测试目标',
        resolvedRoute: ConnectionMode.direct,
        warnings: const [],
        expiresAt: DateTime.now().add(const Duration(minutes: 1)),
        requestDigest: 'fixture-digest',
      ),
    );
    coordinator.invalidate();
    coordinator.invalidate();
    discard.completeError(StateError('旧清理失败'));
    await Future<void>.delayed(Duration.zero);
    expect(diagnostics.records, isEmpty);
  });

  test('未知异常关联到安全本地诊断且不保留正文', () async {
    final backend = _SuccessfulReadBackend()
      ..failure = StateError('姓名：示例用户，账号：2099000000');
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.refreshHome(only: [FeatureId.schedule]);
    final error = controller.snapshots[FeatureId.schedule]!.error!;
    expect(error.issueId, startsWith('UBAA-'));
    final record = controller.diagnostics.records.single;
    expect(record.issueId, error.issueId);
    expect(record.operation, DiagnosticOperation.read);
    expect(record.cause, DiagnosticCause.state);
    expect(record.feature, FeatureId.schedule);
    expect(controller.exportDiagnostics(), isNot(contains('2099000000')));
  });

  test('注销后晚到的失败不污染诊断或新页面', () async {
    final backend = _DelayedReadBackend();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    final pending = controller.refreshHome(only: [FeatureId.schedule]);
    await controller.logout();
    backend.completion.completeError(StateError('旧会话失败'));
    await pending;
    expect(controller.diagnostics.records, isEmpty);
    expect(controller.snapshots[FeatureId.schedule]!.error, isNull);
  });

  test('可选遥测失败不改变成功读取结果或向业务调用者抛出', () async {
    final controller = AppController(
      backend: _SuccessfulReadBackend(),
      telemetry: _FailingTelemetry(),
    );
    addTearDown(controller.dispose);

    await expectLater(
      controller.refreshHome(only: [FeatureId.schedule]),
      completes,
    );
    expect(
      controller.snapshots[FeatureId.schedule]!.status,
      FeatureLoadStatus.success,
    );
  });

  test('可选遥测失败不把已经成功的登录退回失败状态', () async {
    final controller = AppController(
      backend: DemoBackend(loginDelay: Duration.zero),
      telemetry: _FailingTelemetry(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.setUsername('fixture-user');
    controller.setPassword('fixture-password');
    await controller.submitLogin();
    expect(controller.phase, AppPhase.home);
    expect(controller.error, isNull);
  });
}

class _SuccessfulReadBackend extends DemoBackend {
  Object? failure;
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    if (failure case final error?) throw error;
    return FeatureResult.success(summary: '测试结果');
  }
}

class _DelayedReadBackend extends DemoBackend {
  final completion = Completer<FeatureResult>();
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) => completion.future;
}

class _FailingTelemetry extends MockTelemetryClient {
  @override
  Future<void> track(
    String event, {
    Map<String, Object?> properties = const {},
  }) async => throw StateError('模拟遥测故障');
}

class _DelayedFlushTelemetry extends MockTelemetryClient {
  final completion = Completer<void>();
  @override
  Future<void> flush() => completion.future;
}

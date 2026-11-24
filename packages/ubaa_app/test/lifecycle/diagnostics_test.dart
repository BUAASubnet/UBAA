import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_test_support/ubaa_test_support.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  test('主动打开沿用政策许可和统计开关，读取不增加打开次数', () async {
    for (final accepted in [false, true]) {
      for (final enabled in [false, true]) {
        final telemetry = MockTelemetryClient(enabled: enabled);
        final controller = AppController(
          backend: _SuccessfulReadBackend(),
          privacyAccepted: accepted,
          telemetry: telemetry,
        );
        addTearDown(controller.dispose);
        if (accepted) await controller.refreshHome(only: [FeatureId.schedule]);
        final opens = telemetry.records.where(
          (event) => event.name == 'feature_opened',
        );
        expect(opens, isEmpty);
        controller.recordFeatureOpened('schedule');
        expect(
          telemetry.records
              .where((event) => event.name == 'feature_opened')
              .map((event) => event.properties),
          accepted && enabled
              ? [
                  {'feature': 'schedule', 'route': 'none', 'result': 'success'},
                ]
              : isEmpty,
        );
      }
    }
  });

  test('打开功能不等待遥测，入队失败由现有诊断处理', () async {
    final telemetry = _DelayedTrackTelemetry();
    final controller = AppController(
      backend: DemoBackend(),
      telemetry: telemetry,
    );
    addTearDown(controller.dispose);
    controller.recordFeatureOpened('finance');
    telemetry.completion.completeError(StateError('合成入队失败'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.diagnostics.records, hasLength(1));
  });

  test('主动导出保留原始响应，普通报告和遥测不读取原文', () {
    final backend = _RawBackend();
    final telemetry = MockTelemetryClient();
    final controller = AppController(backend: backend, telemetry: telemetry);
    addTearDown(controller.dispose);
    expect(controller.exportDiagnostics(), isNot(contains('fixture-secret')));
    expect(backend.exports, 0);
    final full = jsonDecode(controller.exportFullDiagnostics()) as Map;
    expect(full['schema_version'], 4);
    expect(
      full['raw_http']['records'][0]['response']['body'],
      'fixture-secret',
    );
    expect(backend.exports, 1);
    expect(controller.exportDiagnostics(), isNot(contains('fixture-secret')));
    expect(telemetry.records, isEmpty);
  });

  test('无统计客户端时不能把开关显示为启用', () async {
    final controller = AppController(backend: _SuccessfulReadBackend());
    addTearDown(controller.dispose);
    final view = await controller.setProductTelemetryEnabled(true);
    expect((view.available, view.telemetryEnabled), (false, false));
  });
  test('注入的统计客户端只记录白名单事件', () async {
    final telemetry = MockTelemetryClient();
    final controller = AppController(
      backend: _SuccessfulReadBackend(),
      telemetry: telemetry,
    );
    addTearDown(controller.dispose);
    await controller.refreshHome(only: [FeatureId.schedule]);
    expect(telemetry.records.map((record) => record.name), [
      TelemetryEvents.featureLoaded,
      TelemetryMetrics.featureLoad,
    ]);
    expect(
      telemetry.records.last.properties['bucket'],
      matches(r'^(lt|ge)_\d+$'),
    );
    expect(telemetry.records.last.properties, isNot(contains('source')));
  });

  test('认证、实际路线、界面错误和崩溃只记录合同维度', () async {
    final backend = _AuthBackend();
    final telemetry = MockTelemetryClient();
    final controller = AppController(backend: backend, telemetry: telemetry);
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.setUsername('synthetic');
    controller.setPassword('synthetic');
    await controller.submitLogin();

    final error = controller.error!;
    controller.recordPresentedError(error);
    controller.recordPresentedError(error);
    await controller.recordAppCrash(
      const _FixtureCrash<int>(),
      StackTrace.fromString(
        '#0  foreign (/private/raw.dart:3:2)\n'
        '#1  local (package:ubaa_app/src/example.dart:25:8)\n'
        '#2  other (package:ubaa_host/src/example.dart:20:4)',
      ),
    );

    TelemetryRecord record(String name) =>
        telemetry.records.where((r) => r.name == name).single;
    expect(record(TelemetryEvents.appStarted).properties, isEmpty);
    expect(
      record(TelemetryEvents.authStarted).properties,
      containsPair('feature', 'auth'),
    );
    expect(
      record(TelemetryEvents.authFailed).properties,
      containsPair('error_kind', 'network'),
    );
    expect(
      record(TelemetryEvents.routeResolved).properties,
      containsPair('route', 'webvpn'),
    );
    expect(
      record(TelemetryMetrics.auth).properties,
      containsPair('route', 'webvpn'),
    );
    expect(
      record(TelemetryEvents.uiErrorShown).properties,
      containsPair('error_code', 'network_error'),
    );
    expect(record(TelemetryEvents.crash).properties, {
      'feature': 'app',
      'error_code': '_FixtureCrash',
      'error_kind': 'internal',
      'retryable': false,
      'source': 'package:ubaa_app/src/example.dart:25',
    });

    backend.fail = false;
    controller.setPassword('synthetic');
    await controller.submitLogin();
    controller.onHomeFirstFrame();
    expect(
      record(TelemetryEvents.authSucceeded).properties,
      containsPair('feature', 'auth'),
    );
    expect(record(TelemetryMetrics.coldStart).properties, contains('bucket'));
    expect(
      record(TelemetryMetrics.firstContent).properties,
      contains('bucket'),
    );
  });

  test('遥测晚到失败不进入新会话诊断', () async {
    final telemetry = _DelayedTrackTelemetry();
    final controller = AppController(
      backend: DemoBackend(),
      telemetry: telemetry,
    );
    addTearDown(controller.dispose);
    final pending = controller.recordAppStarted();
    await controller.logout();
    telemetry.completion.completeError(StateError('旧遥测入队失败'));
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
    final telemetry = MockTelemetryClient();
    final controller = AppController(backend: backend, telemetry: telemetry);
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
    final total = telemetry.records
        .where((record) => record.name == TelemetryEvents.featureLoaded)
        .single;
    expect(total.properties['result'], 'failure');
    expect(
      telemetry.records.where(
        (record) => record.name == TelemetryEvents.featureFailed,
      ),
      hasLength(1),
    );
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
    final telemetry = _FailingTelemetry();
    final controller = AppController(
      backend: _SuccessfulReadBackend(),
      telemetry: telemetry,
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
    expect(telemetry.calls, [
      TelemetryEvents.featureLoaded,
      TelemetryMetrics.featureLoad,
    ]);
    expect(controller.diagnostics.records, hasLength(2));
    expect(
      controller.diagnostics.records.every(
        (r) => r.operation == DiagnosticOperation.telemetry,
      ),
      isTrue,
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
  final calls = <String>[];
  @override
  Future<void> track(
    String event, {
    Map<String, Object?> properties = const {},
  }) async {
    calls.add(event);
    throw StateError('模拟遥测故障');
  }
}

class _DelayedTrackTelemetry extends MockTelemetryClient {
  final completion = Completer<void>();
  @override
  Future<void> track(
    String event, {
    Map<String, Object?> properties = const {},
  }) => completion.future;
}

class _FixtureCrash<T> {
  const _FixtureCrash();
  @override
  String toString() => '不得采集的异常消息';
}

class _AuthBackend extends DemoBackend {
  _AuthBackend() : super(loginDelay: Duration.zero);
  bool fail = true;

  @override
  Future<void> login(LoginInput input) async {
    if (fail) {
      throw const BackendException(
        UbaaErrorCode.networkError,
        kind: UbaaErrorKind.network,
        resolvedRoute: ConnectionMode.webvpn,
      );
    }
    await super.login(input);
  }
}

class _RawBackend extends DemoBackend implements RawDiagnosticsBackend {
  int exports = 0;
  @override
  String exportRawDiagnostics() {
    exports++;
    return '{"records":[{"response":{"body":"fixture-secret"}}]}';
  }
}

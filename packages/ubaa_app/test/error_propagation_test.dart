import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  test('逐路线登录失败保留实际路线和禁止重试标志', () async {
    final backend = BridgeBackend(_LoginFailureClient('network_error'));
    await expectLater(
      backend.login(const LoginInput(username: 'fixture', password: 'fixture')),
      throwsA(
        isA<BackendException>()
            .having((error) => error.code, '代码', UbaaErrorCode.networkError)
            .having((error) => error.kind, '类别', UbaaErrorKind.network)
            .having((error) => error.retryable, '重试', false)
            .having((error) => error.resolvedRoute, '路线', ConnectionMode.webvpn)
            .having((error) => error.detail, '无原文', isNull),
      ),
    );
  });

  test('登录兼容错误字符串未知时归约内部错误且不保留原文', () async {
    final backend = BridgeBackend(_LoginFailureClient('future_error'));
    await expectLater(
      backend.login(const LoginInput(username: 'fixture', password: 'fixture')),
      throwsA(
        isA<BackendException>()
            .having((error) => error.code, '代码', UbaaErrorCode.internalError)
            .having((error) => error.detail, '无原文', isNull),
      ),
    );
  });

  test('写流程三个兼容入口重新抛出时保留禁止重试与路线', () async {
    const failure = BackendException(
      UbaaErrorCode.networkError,
      kind: UbaaErrorKind.network,
      retryable: false,
      resolvedRoute: ConnectionMode.webvpn,
    );
    for (final operation in ['prepare', 'cancel', 'confirm']) {
      final coordinator = WriteCoordinator(
        commit: (_) async => throw failure,
        discard: (_) async => throw failure,
      );
      if (operation != 'prepare') {
        coordinator.setIntent(
          WriteIntent(
            intentId: 'fixture-intent',
            operation: WriteOperation.ygdkSubmit,
            targetSummary: '测试目标',
            resolvedRoute: ConnectionMode.webvpn,
            warnings: const [],
            expiresAt: DateTime.now().add(const Duration(minutes: 1)),
            requestDigest: 'fixture-digest',
          ),
        );
      }
      final future = switch (operation) {
        'prepare' => coordinator.prepare(() async => throw failure),
        'cancel' => coordinator.cancel(),
        _ => coordinator.confirm(),
      };
      await expectLater(
        future,
        throwsA(
          isA<BackendException>()
              .having((error) => error.retryable, '重试/$operation', false)
              .having(
                (error) => error.kind,
                '类别/$operation',
                UbaaErrorKind.network,
              )
              .having(
                (error) => error.resolvedRoute,
                '路线/$operation',
                ConnectionMode.webvpn,
              ),
        ),
      );
      coordinator.dispose();
    }
  });
  test('生产读取错误到页面后仍保留解析错误码及禁止重试语义', () async {
    final backend = BridgeBackend(_FailingReadClient());
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);

    await controller.refreshFeatureQuery(
      FeatureId.schedule,
      const FeatureQuery(view: FeatureQueryView.scheduleToday),
    );

    final error = controller.snapshots[FeatureId.schedule]!.error!;
    expect(error.code, UbaaErrorCode.parseError);
    expect(error.retryable, isFalse);
    expect(error.kind, UbaaErrorKind.parse);
    expect(error.resolvedRoute, ConnectionMode.webvpn);
    expect(error.message, isNot(contains('upstream-secret')));
  });

  test('Core 禁止重试的网络错误不被默认文案重新开启重试', () async {
    final controller = AppController(
      backend: BridgeBackend(
        _FailingReadClient(
          code: BridgeErrorCode.networkError,
          kind: BridgeErrorKind.network,
        ),
      ),
    );
    addTearDown(controller.dispose);
    await controller.refreshFeatureQuery(
      FeatureId.schedule,
      const FeatureQuery(view: FeatureQueryView.scheduleToday),
    );
    final error = controller.snapshots[FeatureId.schedule]!.error!;
    expect(error.code, UbaaErrorCode.networkError);
    expect(error.retryable, isFalse);
    expect(error.resolvedRoute, ConnectionMode.webvpn);
  });

  test('应用与平台入口对所有机器码提供同一错误策略', () {
    for (final code in UbaaErrorCode.values) {
      final app = UbaaErrorMapper.fromCode(code);
      final platform = mapCoreError(code: code.wireName);
      expect(app.code, platform.code, reason: code.name);
      expect(app.retryable, platform.retryable, reason: code.name);
      expect(app.title, platform.title, reason: code.name);
      expect(app.message, platform.message, reason: code.name);
      expect(app.actionLabel, platform.actionLabel, reason: code.name);
    }
  });
}

class _FailingReadClient implements BridgeClient {
  _FailingReadClient({
    this.code = BridgeErrorCode.parseError,
    this.kind = BridgeErrorKind.parse,
  });

  final BridgeErrorCode code;
  final BridgeErrorKind kind;
  @override
  int contractVersion() => 9;

  @override
  Future<BridgeRoutedTodayClasses> scheduleToday() async => throw BridgeError(
    code: code,
    kind: kind,
    retryable: false,
    message: 'upstream-secret',
    resolvedRoute: BridgeConnectionMode.webVpn,
  );

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('测试不允许其它 Bridge 调用');
}

class _LoginFailureClient extends _FailingReadClient {
  _LoginFailureClient(this.failureCode);
  final String failureCode;

  @override
  Future<BridgeRouteSettings> setDefaultRoutePolicy({
    required BridgeRoutePolicy policy,
  }) async =>
      BridgeRouteSettings(defaultPolicy: policy, activeRoutes: const []);

  @override
  Future<BridgeLoginOutcome> login({
    required String username,
    required String password,
  }) async => BridgeLoginOutcome(
    readiness: BridgeLoginReadiness.noneReady,
    routes: [
      BridgeRouteLoginResult(
        route: BridgeConnectionMode.webVpn,
        state: BridgeRouteLoginState.failed,
        error: BridgeSafeError(
          code: failureCode,
          kind: 'network',
          retryable: false,
          message: '模拟原始个人资料',
        ),
      ),
    ],
  );
}

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

const _input = LoginInput(
  username: 'synthetic-bridge-account',
  password: 'synthetic-password',
);

void main() {
  test('生产 BridgeBackend 保留另一条挑战帧并独立提交答案，不重复准备或改策略', () async {
    final client = _Client();
    final backend = BridgeBackend(client);
    final partial = await backend.beginInteractiveLogin(_input);
    expect(partial.readyRoutes, <ConnectionMode>[ConnectionMode.direct]);
    final image = partial.forRoute(ConnectionMode.webvpn)!.frame!;
    expect(image.rgba, <int>[17, 83, 149, 255]);
    final completed = await backend.submitInteractiveLogin(
      _input,
      <ConnectionMode, String>{ConnectionMode.webvpn: 'synthetic-answer'},
    );
    expect(completed.readyRoutes, ConnectionMode.values);
    expect(image.isReleased, isTrue);
    expect(client.answers.single.answer, 'synthetic-answer');
    expect(
      identical(client.answers.single.challenge, client.challenge),
      isTrue,
    );
    await backend.continueInteractiveLogin(ConnectionMode.direct);
    expect(client.setCalls, 1);
    expect(client.prepareCalls, 1);
    expect(client.ordinaryLogins, 0);
    expect(client.continued, <bool>[false]);
  });

  test('刷新撤销旧句柄和像素，取消后的迟到结果不返回 App', () async {
    final client = _Client();
    final backend = BridgeBackend(client);
    final state = await backend.beginInteractiveLogin(_input);
    final frame = state.forRoute(ConnectionMode.webvpn)!.frame!;
    client.refreshGate = Completer<BridgeInteractiveLoginOutcome>();
    final refreshing = backend.refreshInteractiveCaptcha(ConnectionMode.webvpn);
    expect(client.challenge.cancelled, isTrue);
    expect(frame.isReleased, isTrue);
    backend.cancelInteractiveLogin();
    client.refreshGate!.complete(client.outcome(frame: true));
    await expectLater(
      refreshing,
      throwsA(
        isA<BackendException>().having(
          (error) => error.code,
          '安全代码',
          UbaaErrorCode.invalidInput,
        ),
      ),
    );
    expect(client.answers, isEmpty);
    expect(client.setCalls, 1);
  });

  test('普通 Auto 拒绝保持上下文，显式固定直接传递继续标记且不走旧策略重开', () async {
    final client = _Client()..rejectAuto = true;
    final backend = BridgeBackend(client);
    final state = await backend.beginInteractiveLogin(_input);
    await expectLater(
      backend.continueInteractiveLogin(ConnectionMode.direct),
      throwsA(isA<BackendException>()),
    );
    expect(state.forRoute(ConnectionMode.webvpn)!.frame!.isReleased, isFalse);
    final complete = await backend.continueInteractiveLogin(
      ConnectionMode.direct,
      pinRoute: true,
    );
    expect(complete.settings.defaultPolicy, RoutePolicy.direct);
    expect(complete.settings.activeRoutes, <ConnectionMode>[
      ConnectionMode.direct,
    ]);
    expect(client.setCalls, 1);
    expect(client.prepareCalls, 1);
    expect(client.continued, <bool>[false, true]);
  });

  test('新登录等待策略保存时 dispose 阻止迟到创建交互句柄', () async {
    final client = _Client()..policyGate = Completer<BridgeRouteSettings>();
    final backend = BridgeBackend(client);
    final pending = backend.beginInteractiveLogin(_input);
    await backend.dispose();
    client.policyGate!.complete(
      const BridgeRouteSettings(
        defaultPolicy: BridgeRoutePolicy.auto,
        activeRoutes: <BridgeConnectionMode>[],
      ),
    );
    await expectLater(pending, throwsA(isA<BackendException>()));
    expect(client.beginCalls, 0);
    expect(client.prepareCalls, 0);
  });
}

class _Login implements BridgeInteractiveLogin {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Challenge implements BridgeCaptchaChallenge {
  bool cancelled = false;
  @override
  void cancel() {
    cancelled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements BridgeClient {
  final loginHandle = _Login();
  final challenge = _Challenge();
  int setCalls = 0;
  int prepareCalls = 0;
  int beginCalls = 0;
  int ordinaryLogins = 0;
  int phase = 0;
  bool rejectAuto = false;
  List<BridgeCaptchaAnswer> answers = <BridgeCaptchaAnswer>[];
  final continued = <bool>[];
  Completer<BridgeInteractiveLoginOutcome>? refreshGate;
  Completer<BridgeRouteSettings>? policyGate;

  BridgeInteractiveLoginOutcome outcome({bool frame = false}) =>
      BridgeInteractiveLoginOutcome(
        login: loginHandle,
        readiness: phase == 0
            ? BridgeLoginReadiness.noneReady
            : phase == 1
            ? BridgeLoginReadiness.partial
            : BridgeLoginReadiness.allReady,
        profile: phase == 0
            ? null
            : const BridgeUserProfile(username: 'synthetic-bridge-account'),
        routes: <BridgeInteractiveRouteResult>[
          BridgeInteractiveRouteResult(
            route: BridgeConnectionMode.direct,
            state: phase == 0
                ? BridgeInteractiveRouteState.prepared
                : BridgeInteractiveRouteState.ready,
            revision: BigInt.zero,
            validForMillis: 0,
          ),
          BridgeInteractiveRouteResult(
            route: BridgeConnectionMode.webVpn,
            state: phase == 2
                ? BridgeInteractiveRouteState.ready
                : BridgeInteractiveRouteState.captchaRequired,
            challenge: phase == 2 ? null : challenge,
            revision: phase == 2 ? BigInt.zero : BigInt.one,
            validForMillis: phase == 2 ? 0 : 120000,
            frame: frame
                ? BridgeCaptchaFrame(
                    width: 1,
                    height: 1,
                    rgba: Uint8List.fromList(<int>[17, 83, 149, 255]),
                  )
                : null,
          ),
        ],
      );

  @override
  int contractVersion() => 43;
  @override
  void cancelInteractiveLogin() {}
  @override
  Future<BridgeRouteSettings> setDefaultRoutePolicy({
    required BridgeRoutePolicy policy,
  }) async {
    setCalls++;
    return policyGate?.future ??
        Future<BridgeRouteSettings>.value(
          BridgeRouteSettings(
            defaultPolicy: policy,
            activeRoutes: const <BridgeConnectionMode>[],
          ),
        );
  }

  @override
  BridgeInteractiveLogin beginInteractiveLogin({required String username}) {
    beginCalls++;
    return loginHandle;
  }

  @override
  Future<BridgeInteractiveLoginOutcome> prepareInteractiveLogin({
    required BridgeInteractiveLogin login,
  }) async {
    prepareCalls++;
    return outcome(frame: true);
  }

  @override
  Future<BridgeInteractiveLoginOutcome> submitInteractiveLogin({
    required BridgeInteractiveLogin login,
    required String username,
    required String password,
    required List<BridgeCaptchaAnswer> answers,
  }) async {
    this.answers = answers;
    phase = answers.isEmpty ? 1 : 2;
    return outcome();
  }

  @override
  Future<BridgeInteractiveLoginOutcome> refreshInteractiveCaptcha({
    required BridgeInteractiveLogin login,
    required BridgeConnectionMode route,
  }) async =>
      refreshGate?.future ??
      Future<BridgeInteractiveLoginOutcome>.value(outcome(frame: true));
  @override
  Future<BridgeInteractiveLoginCompletion> continueInteractiveLogin({
    required BridgeInteractiveLogin login,
    required BridgeConnectionMode selectedRoute,
    required bool pinReadyRoute,
  }) async {
    continued.add(pinReadyRoute);
    if (rejectAuto && !pinReadyRoute)
      throw const BridgeError(
        code: BridgeErrorCode.authenticationRequired,
        kind: BridgeErrorKind.authentication,
        retryable: false,
        message: '合成自动路线未就绪',
      );
    return BridgeInteractiveLoginCompletion(
      outcome: BridgeLoginOutcome(
        readiness: phase == 2
            ? BridgeLoginReadiness.allReady
            : BridgeLoginReadiness.partial,
        routes: const <BridgeRouteLoginResult>[],
        profile: const BridgeUserProfile(username: 'synthetic-bridge-account'),
      ),
      settings: BridgeRouteSettings(
        defaultPolicy: pinReadyRoute
            ? BridgeRoutePolicy.direct
            : BridgeRoutePolicy.auto,
        activeRoutes: phase == 2
            ? BridgeConnectionMode.values
            : const <BridgeConnectionMode>[BridgeConnectionMode.direct],
      ),
    );
  }

  @override
  Future<BridgeLoginOutcome> login({
    required String username,
    required String password,
  }) async {
    ordinaryLogins++;
    throw StateError('不应调用旧登录');
  }

  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

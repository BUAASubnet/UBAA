import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../support/bridge/recording_client.dart'
    show FixtureCharacterizationBridgeClient, FixtureSetterRecordingBackend;

void registerBridgeBackendAuthCharacterization() {
  test('登录准备走公开策略入口而登录直写策略并保持路线认证注销顺序', () async {
    final events = <String>[];
    final client = FixtureCharacterizationBridgeClient(events: events);
    final backend = FixtureSetterRecordingBackend(client, events);

    await backend.prepareLogin(RoutePolicy.webvpn);
    await backend.login(
      const LoginInput(
        username: '  student  ',
        password: 'safe-placeholder',
        routePolicy: RoutePolicy.direct,
      ),
    );
    final settings = await backend.routeSettings();
    final status = await backend.authStatus();
    await backend.logout();

    expect(events, <String>[
      'backend.set:webvpn',
      'client.set:webVpn',
      'client.prepareLogin',
      'client.set:direct',
      'client.login:student',
      'client.routeSettings',
      'client.authStatus',
      'client.logout',
    ]);
    expect(settings.defaultPolicy, RoutePolicy.auto);
    expect(settings.activeRoutes, <ConnectionMode>[
      ConnectionMode.direct,
      ConnectionMode.webvpn,
    ]);
    expect(status, AuthStatus.signedIn);

    client.loginOutcome = const BridgeLoginOutcome(
      readiness: BridgeLoginReadiness.noneReady,
      routes: <BridgeRouteLoginResult>[
        BridgeRouteLoginResult(
          route: BridgeConnectionMode.direct,
          state: BridgeRouteLoginState.failed,
          error: BridgeSafeError(
            code: 'invalid_credentials',
            kind: 'authentication',
            retryable: false,
            message: '凭据无效',
          ),
        ),
      ],
    );
    try {
      await backend.login(
        const LoginInput(
          username: 'student',
          password: 'safe-placeholder',
          routePolicy: RoutePolicy.direct,
        ),
      );
      fail('noneReady 应映射为 BackendException');
    } on BackendException catch (error) {
      expect(error.code, UbaaErrorCode.invalidCredentials);
    }
    expect(events.sublist(events.length - 2), <String>[
      'client.set:direct',
      'client.login:student',
    ]);
  });
}

void main() {
  registerBridgeBackendAuthCharacterization();
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('聚合认证的网络失败不能被投影成可自动提交密码的会话失效', () async {
    final backend = BridgeBackend(_Client('network_error'));
    await expectLater(
      backend.authStatus(),
      throwsA(
        isA<BackendException>()
            .having((e) => e.code, '网络原因', UbaaErrorCode.networkError)
            .having((e) => e.resolvedRoute, '原路线', ConnectionMode.webvpn),
      ),
    );
  });
  test('所需路线适配保留 Core 目标与身份，不再调用聚合认证或资料接口', () async {
    final client = _RequiredClient();
    final backend = BridgeBackend(client);
    final recovered = await backend.recoverRequiredSession(FeatureId.signin);
    expect(client.feature, BridgeRecoveryFeature.signin);
    expect(recovered.route, ConnectionMode.webvpn);
    expect(recovered.profile.username, 'fixture-user');
    await backend.loginRequiredRoute(
      ConnectionMode.webvpn,
      const LoginInput(username: 'fixture-user', password: 'synthetic'),
    );
    expect(client.loginRoute, BridgeConnectionMode.webVpn);
  });
  test('状态只提供已核实学号时仍可作为恢复身份，不能借用本机资料填空', () async {
    final client = _RequiredClient()
      ..profile = const BridgeUserProfile(schoolId: 'fixture-user');
    final recovered = await BridgeBackend(
      client,
    ).recoverRequiredSession(FeatureId.schedule);
    expect(recovered.profile.username, 'fixture-user');
    expect(recovered.profile.schoolId, 'fixture-user');
  });
  test('只有两条路线均明确缺少认证时才返回 signedOut', () async {
    expect(
      await BridgeBackend(_Client('authentication_required')).authStatus(),
      AuthStatus.signedOut,
    );
  });
}

class _Client implements BridgeClient {
  _Client(this.code);
  final String code;
  @override
  int contractVersion() => 43;
  @override
  Future<BridgeLoginOutcome> authStatus() async => BridgeLoginOutcome(
    readiness: BridgeLoginReadiness.noneReady,
    routes: [
      const BridgeRouteLoginResult(
        route: BridgeConnectionMode.direct,
        state: BridgeRouteLoginState.failed,
        error: BridgeSafeError(
          code: 'authentication_required',
          kind: 'authentication',
          retryable: false,
          message: '需要认证',
        ),
      ),
      BridgeRouteLoginResult(
        route: BridgeConnectionMode.webVpn,
        state: BridgeRouteLoginState.failed,
        error: BridgeSafeError(
          code: code,
          kind: 'network',
          retryable: true,
          message: '合成错误',
        ),
      ),
    ],
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RequiredClient extends _Client {
  _RequiredClient() : super('authentication_required');
  BridgeRecoveryFeature? feature;
  BridgeConnectionMode? loginRoute;
  BridgeUserProfile profile = const BridgeUserProfile(username: 'fixture-user');
  @override
  Future<BridgeLoginOutcome> authStatus() => throw StateError('该路径禁止聚合认证');
  @override
  Future<BridgeRequiredSession> recoverRequiredSession({
    required BridgeRecoveryFeature feature,
  }) async {
    this.feature = feature;
    return _session;
  }

  @override
  Future<BridgeRequiredSession> loginRequiredRoute({
    required BridgeConnectionMode route,
    required String username,
    required String password,
  }) async {
    loginRoute = route;
    return _session;
  }

  BridgeRequiredSession get _session => BridgeRequiredSession(
    route: BridgeConnectionMode.webVpn,
    profile: profile,
  );
}

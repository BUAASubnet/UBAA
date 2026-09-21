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
  int contractVersion() => 10;
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

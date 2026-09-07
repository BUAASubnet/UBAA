import 'package:ubaa_bindings/ubaa_bindings.dart';

/// 真实 BridgeBackend 的合成输入；不创建 FRB client 或真实会话。
final class AccountPartialBridgeClient implements BridgeClient {
  bool signedIn = false;
  int loginCalls = 0;
  int unsupportedReads = 0;
  BridgeRoutePolicy policy = BridgeRoutePolicy.auto;

  static const outcome = BridgeLoginOutcome(
    readiness: BridgeLoginReadiness.partial,
    routes: [
      BridgeRouteLoginResult(
        route: BridgeConnectionMode.direct,
        state: BridgeRouteLoginState.ready,
      ),
      BridgeRouteLoginResult(
        route: BridgeConnectionMode.webVpn,
        state: BridgeRouteLoginState.failed,
        error: BridgeSafeError(
          code: 'network_error',
          kind: 'network',
          retryable: true,
          message: '合成WebVPN不可用',
        ),
      ),
    ],
  );

  BridgeRouteSettings get settings => BridgeRouteSettings(
    defaultPolicy: policy,
    activeRoutes: signedIn ? [BridgeConnectionMode.direct] : [],
  );

  @override
  int contractVersion() => 9;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #setDefaultRoutePolicy:
        policy = invocation.namedArguments[#policy] as BridgeRoutePolicy;
        return Future<BridgeRouteSettings>.value(settings);
      case #routeSettings:
        return Future<BridgeRouteSettings>.value(settings);
      case #prepareLogin:
        return Future<BridgeLoginPreparation>.value(
          const BridgeLoginPreparation(routes: []),
        );
      case #authStatus:
        return Future<BridgeLoginOutcome>.value(
          signedIn
              ? outcome
              : const BridgeLoginOutcome(
                  readiness: BridgeLoginReadiness.noneReady,
                  routes: [],
                ),
        );
      case #login:
        loginCalls++;
        signedIn = true;
        return Future<BridgeLoginOutcome>.value(outcome);
      case #userInfo:
        return Future<BridgeRoutedUserProfile>.value(
          const BridgeRoutedUserProfile(
            data: BridgeUserProfile(
              username: 'partial-fixture',
              name: '合成部分路线同学',
              email: 'partial@example.invalid',
            ),
            route: BridgeRouteDecision(
              policy: BridgeRoutePolicy.auto,
              resolvedRoute: BridgeConnectionMode.direct,
              network: BridgeNetworkState.campus,
              initialRoute: BridgeConnectionMode.direct,
              usedFallback: false,
            ),
          ),
        );
      case #logout:
        signedIn = false;
        return Future<void>.value();
      case #dispose:
        return Future<void>.value();
      default:
        // 未实现领域读显式不支持，不能填充全领域成功数据。
        unsupportedReads++;
        throw UnsupportedError('合成客户端未实现该业务读取');
    }
  }
}

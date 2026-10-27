import 'package:ubaa_bindings/ubaa_bindings.dart';

/// 真实 BridgeBackend 的合成输入；不创建 FRB client 或真实会话。
final class AccountPartialBridgeClient implements BridgeClient {
  bool signedIn = false;
  int loginCalls = 0;
  int unsupportedReads = 0;
  int continuationCalls = 0;
  final interactiveHandle = _PartialLogin();
  BridgeRoutePolicy policy = BridgeRoutePolicy.auto;

  static const outcome = BridgeLoginOutcome(
    readiness: BridgeLoginReadiness.partial,
    profile: BridgeUserProfile(
      username: 'partial-fixture',
      name: '合成部分路线同学',
      email: 'partial@example.invalid',
    ),
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
  int contractVersion() => 42;

  BridgeInteractiveLoginOutcome interactiveOutcome({bool prepared = false}) =>
      BridgeInteractiveLoginOutcome(
        login: interactiveHandle,
        readiness: prepared
            ? BridgeLoginReadiness.noneReady
            : outcome.readiness,
        profile: prepared ? null : outcome.profile,
        routes: [
          for (final route in outcome.routes)
            BridgeInteractiveRouteResult(
              route: route.route,
              state: prepared
                  ? BridgeInteractiveRouteState.prepared
                  : route.state == BridgeRouteLoginState.ready
                  ? BridgeInteractiveRouteState.ready
                  : BridgeInteractiveRouteState.failed,
              error: prepared ? null : route.error,
              revision: BigInt.zero,
              validForMillis: 0,
            ),
        ],
      );

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
                  routes: [
                    BridgeRouteLoginResult(
                      route: BridgeConnectionMode.direct,
                      state: BridgeRouteLoginState.failed,
                      error: BridgeSafeError(
                        code: 'authentication_required',
                        kind: 'authentication',
                        retryable: true,
                        message: '合成直连未登录',
                      ),
                    ),
                    BridgeRouteLoginResult(
                      route: BridgeConnectionMode.webVpn,
                      state: BridgeRouteLoginState.failed,
                      error: BridgeSafeError(
                        code: 'authentication_required',
                        kind: 'authentication',
                        retryable: true,
                        message: '合成 WebVPN 未登录',
                      ),
                    ),
                  ],
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
      case #beginInteractiveLogin:
        return interactiveHandle;
      case #prepareInteractiveLogin:
        return Future<BridgeInteractiveLoginOutcome>.value(
          interactiveOutcome(prepared: true),
        );
      case #submitInteractiveLogin:
        loginCalls++;
        return Future<BridgeInteractiveLoginOutcome>.value(
          interactiveOutcome(),
        );
      case #continueInteractiveLogin:
        if (invocation.namedArguments[#selectedRoute] !=
                BridgeConnectionMode.direct ||
            invocation.namedArguments[#pinReadyRoute] != true) {
          throw StateError('合成部分成功必须显式选择就绪的直连路线');
        }
        continuationCalls++;
        signedIn = true;
        policy = BridgeRoutePolicy.direct;
        return Future<BridgeInteractiveLoginCompletion>.value(
          BridgeInteractiveLoginCompletion(
            outcome: outcome,
            settings: settings,
          ),
        );
      case #logout:
        signedIn = false;
        return Future<void>.value();
      case #cancelInteractiveLogin:
        return null;
      case #dispose:
        return Future<void>.value();
      default:
        // 未实现领域读显式不支持，不能填充全领域成功数据。
        unsupportedReads++;
        throw UnsupportedError('合成客户端未实现该业务读取');
    }
  }
}

class _PartialLogin implements BridgeInteractiveLogin {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

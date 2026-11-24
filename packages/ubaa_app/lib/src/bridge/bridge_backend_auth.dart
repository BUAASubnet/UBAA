part of 'bridge_backend.dart';

mixin BridgeBackendAuth {
  BridgeContext get _context;
  BridgeClient get client;
  void clearAppServiceAccount();

  NetworkChangeOperation beginNetworkChange({
    required bool online,
    required Duration budget,
  }) {
    try {
      return BridgeNetworkOperation(
        client.beginNetworkChange(
          online: online,
          timeoutMillis: budget.inMilliseconds,
        ),
      );
    } on BridgeError catch (error, stack) {
      Error.throwWithStackTrace(bridgeMapError(error), stack);
    }
  }

  void cancelNetworkReads() => client.cancelNetworkReads();

  RequiredRecoveryOperation startTargetRecovery(
    RecoveryTarget target,
    Duration limit,
  ) => BridgeRequiredSessionBackend(
    _context.client,
  ).startTargetRecovery(target, limit);
  Future<RecoveredRouteSession> recoverTargetSession(RecoveryTarget target) =>
      BridgeRequiredSessionBackend(
        _context.client,
      ).recoverTargetSession(target);

  RequiredRecoveryOperation startRequiredRecovery(
    FeatureId feature,
    Duration limit,
  ) => BridgeRequiredSessionBackend(
    _context.client,
  ).startRequiredRecovery(feature, limit);
  RequiredRecoveryOperation startRequiredLogin(
    ConnectionMode route,
    LoginInput input,
    Duration limit,
  ) => BridgeRequiredSessionBackend(
    _context.client,
  ).startRequiredLogin(route, input, limit);
  Future<RecoveredRouteSession> recoverRequiredSession(FeatureId feature) =>
      bridgeRecoverRequiredSession(_context, feature);
  Future<RecoveredRouteSession> loginRequiredRoute(
    ConnectionMode route,
    LoginInput input,
  ) => bridgeLoginRequiredRoute(_context, route, input);
  Future<LoginVerificationState> beginInteractiveLogin(LoginInput input) =>
      bridgeBeginInteractiveLogin(_context, input);
  Future<LoginVerificationState> resumeRequiredCaptcha(
    LoginInput input,
    ConnectionMode route,
  ) => bridgeResumeRequiredCaptcha(_context, input, route);
  Future<LoginVerificationState> submitInteractiveLogin(
    LoginInput input,
    Map<ConnectionMode, String> answers,
  ) => bridgeSubmitInteractiveLogin(_context, input, answers);
  Future<LoginVerificationState> refreshInteractiveCaptcha(
    ConnectionMode route,
  ) => bridgeRefreshInteractiveCaptcha(_context, route);
  Future<InteractiveLoginCompletion> continueInteractiveLogin(
    ConnectionMode route, {
    bool pinRoute = false,
  }) => bridgeContinueInteractiveLogin(_context, route, pinRoute: pinRoute);
  void discardInteractiveCaptcha(ConnectionMode route) =>
      bridgeDiscardInteractiveCaptcha(_context, route);
  void cancelInteractiveLogin() => bridgeCancelInteractiveLogin(_context);

  Future<bool> hasSavedSession() => _context.client.hasSavedSession();

  Future<AuthStatus> authStatus() => bridgeAuthStatus(_context);

  Future<UserSummary?> userInfo() => bridgeUserInfo(_context);
  Future<OfflineProfileRead> readCachedProfile(RoutePolicy policy) =>
      bridgeWithOfflineRead(
        _context,
        () => bridgeReadCachedProfile(_context, policy),
      );
  Future<ProfileRefresh> refreshProfile({required LocalAccount account}) =>
      bridgeWithOfflineRead(
        _context,
        () => bridgeRefreshProfile(_context, account),
      );

  Future<void> prepareLogin(RoutePolicy policy) =>
      bridgePrepareLogin(_context, policy, setDefaultRoutePolicy);

  Future<BackendRouteSettings> setDefaultRoutePolicy(RoutePolicy policy) =>
      bridgeSetDefaultRoutePolicy(_context, policy);

  Future<BackendRouteSettings> routeSettings() => bridgeRouteSettings(_context);

  Future<void> login(LoginInput input) => bridgeLogin(_context, input);

  Future<void> logout() {
    clearAppServiceAccount();
    return bridgeLogout(_context);
  }
}

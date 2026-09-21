part of '../../app_controller.dart';

extension _AppControllerRequiredRecovery on AppController {
  Future<LoginInput?> _approvedRecoveryInput(int epoch) async {
    if (_automaticCredentialBlocked) return null;
    final saved = await _credentialVault.read();
    if (!_recoveryIsCurrent(epoch)) return null;
    if (saved == null ||
        !saved.isUsable ||
        !saved.autoLogin ||
        !_credentialVault.isAvailable ||
        (_localAccount != null && saved.username != _localAccount!.username) ||
        (_localAccount == null &&
            _user != null &&
            saved.username != _user!.username &&
            saved.username != _user!.schoolId))
      return null;
    return LoginInput(
      username: saved.username,
      password: saved.password,
      rememberPassword: true,
      autoLogin: true,
      routePolicy: _loginForm.routePolicy,
    );
  }

  Future<UserSummary?> _recoverRequiredProfile(
    RequiredSessionBackend backend,
    FeatureId feature,
    int epoch,
  ) async {
    RecoveredRouteSession recovered;
    try {
      recovered = await backend.recoverRequiredSession(feature);
    } on BackendException catch (error) {
      if (!_recoveryIsCurrent(epoch)) return null;
      // 只使用 Core 已返回的目标；无路线或临时故障不能尝试提交密码。
      if (error.code != UbaaErrorCode.authenticationRequired ||
          error.resolvedRoute == null)
        rethrow;
      final input = await _approvedRecoveryInput(epoch);
      if (!_recoveryIsCurrent(epoch)) return null;
      if (input == null) rethrow;
      recovered = await backend.loginRequiredRoute(error.resolvedRoute!, input);
      if (recovered.route != error.resolvedRoute)
        throw const BackendException(UbaaErrorCode.upstreamChanged);
    }
    if (!_recoveryIsCurrent(epoch)) return null;
    _recoveredRoute = recovered.route;
    return recovered.profile;
  }

  Future<UserSummary?> _recoverLegacyProfile(int epoch) async {
    final status = await _backend.authStatus();
    if (!_recoveryIsCurrent(epoch)) return null;
    if (status == AuthStatus.signedOut) {
      final input = await _approvedRecoveryInput(epoch);
      if (!_recoveryIsCurrent(epoch) || input == null) return null;
      await _backend.login(input);
      if (!_recoveryIsCurrent(epoch)) return null;
    }
    return _backend.userInfo();
  }
}

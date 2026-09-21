part of '../app_controller.dart';

extension _AppControllerAuthentication on AppController {
  Future<void> _initializeController() async {
    if (_initialized) return;
    _initialized = true;
    if (_localAccountStore != null && await _initializeLocalHome()) return;
    _beginWriteTransition();
    _setPhase(AppPhase.checkingSession);
    try {
      if (_backend case final RouteSettingsBackend routeBackend) {
        final settings = await routeBackend.routeSettings();
        if (_disposed) return;
        _applyRouteSettings(settings);
      }
      final status = await _backend.authStatus();
      if (_disposed) return;
      if (status == AuthStatus.signedIn) {
        _user = await _backend.userInfo();
        if (_disposed) return;
        if (_user != null) {
          _setPhase(AppPhase.home);
          await _recordAppOpen();
          unawaited(refreshHome());
          return;
        }
      }
      final saved = await _credentialVault.read();
      if (_disposed) return;
      if (saved != null && saved.isUsable) {
        _loginForm = _loginForm.copyWith(
          username: saved.username,
          autoLogin: saved.autoLogin,
          rememberPassword: _credentialVault.isAvailable,
        );
        if (saved.autoLogin && _credentialVault.isAvailable) {
          // 密码只在当前登录调用的短生命周期内放入 controller；submitLogin 成功
          // 或失败都会清空密码字段，且失败凭据会被清理。
          _loginForm = _loginForm.copyWith(password: saved.password);
          await submitLogin();
          return;
        }
      }
      _setPhase(AppPhase.login);
    } on BackendException catch (exception, stackTrace) {
      _error = _recordFailure(
        exception,
        DiagnosticOperation.initialization,
        stackTrace: stackTrace,
      );
      _setPhase(AppPhase.login);
    } catch (error, stackTrace) {
      _error = _recordFailure(
        error,
        DiagnosticOperation.initialization,
        stackTrace: stackTrace,
      );
      _setPhase(AppPhase.login);
    } finally {
      _endWriteTransition();
    }
  }

  Future<void> _submitLoginController({bool preserveHome = false}) async {
    if (_disposed || isLoggingIn || _sessionRecoveryFuture != null) return;
    final username = _loginForm.username.trim();
    if (username.isEmpty || _loginForm.password.isEmpty) {
      _error = UbaaErrorMapper.fromCode(UbaaErrorCode.invalidInput);
      _notify();
      return;
    }
    final input = LoginInput(
      username: username,
      password: _loginForm.password,
      captcha: _loginForm.captcha.trim().isEmpty
          ? null
          : _loginForm.captcha.trim(),
      rememberPassword: _loginForm.rememberPassword,
      autoLogin: _loginForm.autoLogin,
      routePolicy: _loginForm.routePolicy,
    );
    final inPlace = preserveHome && _phase == AppPhase.home;
    _inPlaceLogin = inPlace;
    if (inPlace) {
      // 认证使旧在途读取失效，但不销毁当前页面、筛选草稿和返回位置。
      _writeTransitions++;
      _lifecycleEpoch++;
      _ygdkGeneration++;
      _writeCoordinator.invalidate();
    } else {
      _beginWriteTransition();
    }
    final epoch = _lifecycleEpoch;
    bool current() => !_disposed && epoch == _lifecycleEpoch;
    _error = null;
    _activeRoutes = const <ConnectionMode>[];
    _sessionRecoveryStatus = SessionRecoveryStatus.restoring;
    if (inPlace) {
      _notify();
    } else {
      _setPhase(AppPhase.loggingIn);
    }
    try {
      await _backend.login(input);
      if (!current()) return;
      await _refreshRouteSettings();
      if (!current()) return;
      final profile = await _backend.userInfo();
      if (!current()) return;
      if (_localAccountStore != null && profile == null) {
        throw const BackendException(UbaaErrorCode.authenticationRequired);
      }
      if (_localAccountStore != null &&
          profile != null &&
          profile.username != username &&
          profile.schoolId != username) {
        _user = null;
        _resetFeatureSnapshots();
        _sessionRecoveryStatus = SessionRecoveryStatus.needsLogin;
        _error = UbaaErrorMapper.fromCode(UbaaErrorCode.authenticationRequired);
        _notify();
        try {
          await _localAccountStore.signOut();
        } on Object catch (error, stackTrace) {
          _error = _recordFailure(
            error,
            DiagnosticOperation.login,
            stackTrace: stackTrace,
          );
        }
        return;
      }
      _user = profile ?? UserSummary(username: username);
      try {
        if (input.rememberPassword && _credentialVault.isAvailable) {
          await _credentialVault.write(
            Credential(
              username: username,
              password: input.password,
              autoLogin: input.autoLogin,
            ),
          );
        } else if (!input.rememberPassword) {
          await _credentialVault.clear();
        }
      } on Object catch (error, stackTrace) {
        if (!current()) return;
        _error = _recordFailure(
          error,
          DiagnosticOperation.login,
          stackTrace: stackTrace,
        );
      }
      if (!current()) return;
      await _retainCurrentAccount(
        username: username,
        retainSession: input.rememberPassword,
      );
      if (!current()) return;
      _sessionRecoveryStatus = SessionRecoveryStatus.ready;
      _setPhase(AppPhase.home);
      await _recordAppOpen();
      if (current()) unawaited(refreshHome());
    } on Object catch (error, stackTrace) {
      if (!current()) return;
      if (error is BackendException &&
          error.code == UbaaErrorCode.invalidCredentials) {
        try {
          await _credentialVault.clear();
        } on Object {
          /* 保留原认证错误。 */
        }
        if (!current()) return;
      }
      _error = _recordFailure(
        error,
        DiagnosticOperation.login,
        stackTrace: stackTrace,
      );
      _sessionRecoveryStatus = SessionRecoveryStatus.needsLogin;
      _setPhase(inPlace ? AppPhase.home : AppPhase.login);
    } finally {
      _inPlaceLogin = false;
      _loginForm = _loginForm.copyWith(password: '', captcha: '');
      _endWriteTransition();
      _notify();
    }
  }
}

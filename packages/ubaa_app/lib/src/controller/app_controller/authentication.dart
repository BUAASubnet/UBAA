part of '../app_controller.dart';

extension _AppControllerAuthentication on AppController {
  bool get _canEditLoginOptions =>
      !_disposed &&
      !_isSigningOut &&
      _phase != AppPhase.loggingIn &&
      _phase != AppPhase.checkingSession &&
      _credentialVault.isAvailable;

  bool _isCurrentAuthentication(int generation) =>
      !_disposed && generation == _lifecycleEpoch;

  void _releaseLoginSecret() {
    _loginForm = _loginForm.copyWith(password: '', captcha: '');
  }

  Future<void> _initializeController({UiError? previousLoginError}) async {
    if (_initialized || _disposed || _isSigningOut) return;
    _initialized = true;
    if (_localAccountStore != null &&
        !_manualAuthenticationRequired &&
        await _initializeLocalHome())
      return;
    final formRevision = _loginFormRevision;
    _beginWriteTransition();
    final generation = _lifecycleEpoch;
    _error = previousLoginError;
    _setPhase(AppPhase.checkingSession);
    try {
      if (_needsManualLogin(formRevision)) return;
      if (_backend case final RouteSettingsBackend routeBackend) {
        final settings = await routeBackend.routeSettings();
        if (!_isCurrentAuthentication(generation)) return;
        _applyRouteSettings(settings);
        if (_needsManualLogin(formRevision)) return;
      }
      final status = await _backend.authStatus();
      if (!_isCurrentAuthentication(generation)) return;
      if (_needsManualLogin(formRevision)) return;
      if (status == AuthStatus.signedIn) {
        final user = await _backend.userInfo();
        if (!_isCurrentAuthentication(generation)) return;
        if (_needsManualLogin(formRevision)) return;
        if (user != null) {
          _error = null;
          _user = user;
          _releaseLoginSecret();
          _setPhase(AppPhase.home);
          await _recordAppOpen();
          if (_isCurrentAuthentication(generation)) unawaited(refreshHome());
          return;
        }
      }
      // 修订号在 controller 生命周期内保留：重建只能恢复尚未被用户
      // 改填、提交或退出的表单，不能重新授权已消费的自动登录尝试。
      if (_credentialRestoreAllowed &&
          _loginFormRevision == 0 &&
          _credentialVault.isAvailable) {
        final saved = await _credentialVault.read();
        if (!_isCurrentAuthentication(generation)) return;
        if (_needsManualLogin(formRevision)) return;
        if (_loginFormRevision == formRevision &&
            _credentialVault.isAvailable &&
            saved != null &&
            saved.isUsable) {
          _loginForm = _loginForm.copyWith(
            username: saved.username,
            password: saved.password,
            autoLogin: saved.autoLogin,
            rememberPassword: true,
          );
          // 手动恢复仅供遮罩表单使用；自动登录只尝试一次，成功或失败
          // 都释放表单中的密码，账号变化和销毁也会使本次恢复失效。
          if (saved.autoLogin) {
            await _submitLoginController();
            return;
          }
        }
      }
      _setPhase(AppPhase.login);
    } on Object catch (error, stackTrace) {
      if (!_isCurrentAuthentication(generation)) return;
      final failure = _recordFailure(
        error,
        DiagnosticOperation.initialization,
        stackTrace: stackTrace,
      );
      _error = _loginFormRevision == formRevision
          ? previousLoginError ?? failure
          : failure;
      _setPhase(AppPhase.login);
    } finally {
      _endWriteTransition();
    }
  }

  bool _needsManualLogin(int formRevision) {
    if (!_manualAuthenticationRequired && _loginFormRevision == formRevision) {
      return false;
    }
    // 明确退出或改填账号后，后台不能接受残留旧会话；手动认证成功才
    // 重新允许会话恢复。恢复在途出现新输入也必须交还给当前登录表单。
    _user = null;
    _activeRoutes = const <ConnectionMode>[];
    _setPhase(AppPhase.login);
    return true;
  }

  Future<void> _submitLoginController({bool preserveHome = false}) async {
    if (_disposed ||
        _isSigningOut ||
        isLoggingIn ||
        _sessionRecoveryFuture != null)
      return;
    final username = _loginForm.username.trim();
    if (username.isEmpty || _loginForm.password.isEmpty) {
      _error = UbaaErrorMapper.fromCode(UbaaErrorCode.invalidInput);
      _notify();
      return;
    }
    _credentialRestoreAllowed = false;
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
      await _completeAuthenticatedLogin(input, profile, epoch);
    } on Object catch (error, stackTrace) {
      if (!current()) return;
      if (error is BackendException &&
          error.code == UbaaErrorCode.invalidCredentials) {
        try {
          await _mutateCredential(epoch, _credentialVault.clear);
        } on Object catch (clearError, clearStack) {
          _recordFailure(
            clearError,
            DiagnosticOperation.logout,
            stackTrace: clearStack,
          );
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

  Future<void> _completeAuthenticatedLogin(
    LoginInput input,
    UserSummary? profile,
    int epoch,
  ) async {
    final username = input.username.trim();
    bool current() => !_disposed && epoch == _lifecycleEpoch;
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
    if (_localAccount != null && _localAccount!.username != username) {
      // 原位换账号不能让旧账号的内容继续挂在新身份下面。
      _user = null;
      _resetFeatureSnapshots(advanceLifecycle: false);
      _notify();
      await _localAccountStore?.signOut();
      if (!current()) return;
      await _closeOfflineAccount();
      if (!current()) return;
      _localAccount = null;
    }
    _user = profile ?? UserSummary(username: username);
    try {
      if (input.rememberPassword && _credentialVault.isAvailable) {
        await _mutateCredential(
          epoch,
          () => _credentialVault.write(
            Credential(
              username: username,
              password: input.password,
              autoLogin: input.autoLogin,
            ),
          ),
        );
      } else if (!input.rememberPassword) {
        await _mutateCredential(epoch, _credentialVault.clear);
      }
    } on Object catch (error, stackTrace) {
      if (!current()) return;
      _recordFailure(error, DiagnosticOperation.login, stackTrace: stackTrace);
      _error = UiError(
        code: UbaaErrorCode.internalError,
        kind: UbaaErrorKind.internal,
        title: '本机登录材料未保存',
        message: input.rememberPassword
            ? '已登录，但账号密码未能保存，下次需要重新输入。'
            : '已登录，但之前保存的账号密码未能清除，请稍后重试。',
      );
    }
    if (!current()) return;
    await _retainCurrentAccount(
      username: username,
      retainSession: input.rememberPassword,
    );
    if (!current()) return;
    if (_error == null) _automaticCredentialBlocked = false;
    _manualAuthenticationRequired = false;
    _sessionRecoveryStatus = SessionRecoveryStatus.ready;
    _setPhase(AppPhase.home);
    unawaited(_queueProfileRefresh(force: true));
    await _recordAppOpen();
    if (current()) unawaited(refreshHome());
  }

  Future<void> _mutateCredential(
    int epoch,
    Future<void> Function() action,
  ) async {
    final previous = _credentialMutation;
    final pending = () async {
      if (previous != null) {
        try {
          await previous;
        } on Object {
          /* 后续清除仍继续。 */
        }
      }
      if (!_disposed && epoch == _lifecycleEpoch) await action();
    }();
    _credentialMutation = pending;
    try {
      await pending;
    } finally {
      if (identical(_credentialMutation, pending)) _credentialMutation = null;
    }
  }
}

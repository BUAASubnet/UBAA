part of '../app_controller.dart';

extension _AppControllerAuthentication on AppController {
  bool get _canEditLoginOptions =>
      !_disposed &&
      !_loggingOut &&
      _phase != AppPhase.loggingIn &&
      _phase != AppPhase.checkingSession &&
      _credentialVault.isAvailable;

  bool _isCurrentAuthentication(int generation) =>
      !_disposed && generation == _authGeneration;

  void _releaseLoginSecret() {
    _loginForm = _loginForm.copyWith(password: '', captcha: '');
  }

  Future<void> _initializeAuthentication({UiError? previousLoginError}) async {
    if (_initialized || _disposed || _loggingOut) return;
    _initialized = true;
    final generation = ++_authGeneration;
    final formRevision = _loginFormRevision;
    _beginWriteTransition();
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
            await submitLogin();
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

  Future<void> _submitLogin() async {
    if (_disposed || _phase == AppPhase.loggingIn || _loggingOut) return;
    final form = _loginForm;
    final username = form.username.trim();
    if (username.isEmpty || form.password.isEmpty) {
      _error = UbaaErrorMapper.fromCode(UbaaErrorCode.invalidInput);
      _notify();
      return;
    }
    _credentialRestoreAllowed = false;
    _manualAuthenticationRequired = true;
    final generation = ++_authGeneration;
    _beginWriteTransition();
    _error = null;
    _activeRoutes = const <ConnectionMode>[];
    _setPhase(AppPhase.loggingIn);
    try {
      if (!_isCurrentAuthentication(generation)) return;
      await _backend.login(
        LoginInput(
          username: username,
          password: form.password,
          captcha: form.captcha.trim().isEmpty ? null : form.captcha.trim(),
          rememberPassword: form.rememberPassword,
          autoLogin: form.autoLogin,
          routePolicy: form.routePolicy,
        ),
      );
      if (!_isCurrentAuthentication(generation)) return;
      _releaseLoginSecret();
      await _refreshRouteSettings(generation);
      if (!_isCurrentAuthentication(generation)) return;
      final user = await _backend.userInfo() ?? UserSummary(username: username);
      if (!_isCurrentAuthentication(generation)) return;
      _user = user;
      _manualAuthenticationRequired = false;
      await _persistLoginCredential(generation, username, form);
      if (!_isCurrentAuthentication(generation)) return;
      _setPhase(AppPhase.home);
      await _recordAppOpen();
      if (_isCurrentAuthentication(generation)) unawaited(refreshHome());
    } on Object catch (error, stackTrace) {
      if (!_isCurrentAuthentication(generation)) return;
      _releaseLoginSecret();
      final authenticationError = _recordFailure(
        error,
        DiagnosticOperation.login,
        stackTrace: stackTrace,
      );
      if (error is BackendException &&
          error.code == UbaaErrorCode.invalidCredentials) {
        try {
          await _mutateCredential(generation, _credentialVault.clear);
        } on Object catch (clearError, clearStackTrace) {
          if (_isCurrentAuthentication(generation)) {
            _recordFailure(
              clearError,
              DiagnosticOperation.login,
              stackTrace: clearStackTrace,
            );
          }
        }
      }
      if (!_isCurrentAuthentication(generation)) return;
      _user = null;
      _activeRoutes = const <ConnectionMode>[];
      _error = authenticationError;
      _setPhase(AppPhase.login);
    } finally {
      _endWriteTransition();
    }
  }

  Future<void> _persistLoginCredential(
    int generation,
    String username,
    LoginFormState form,
  ) async {
    try {
      if (form.rememberPassword) {
        if (!_credentialVault.isAvailable) {
          throw const CredentialVaultException(
            CredentialVaultErrorCode.unavailable,
          );
        }
        await _mutateCredential(
          generation,
          () => _credentialVault.write(
            Credential(
              username: username,
              password: form.password,
              autoLogin: form.autoLogin,
            ),
          ),
        );
      } else {
        await _mutateCredential(generation, _credentialVault.clear);
      }
    } on Object catch (error, stackTrace) {
      if (!_isCurrentAuthentication(generation)) return;
      final failure = _recordFailure(
        error,
        DiagnosticOperation.login,
        stackTrace: stackTrace,
      );
      _loginForm = _loginForm.copyWith(
        rememberPassword: false,
        autoLogin: false,
      );
      // 认证已经确认，本机存储错误不能撤销会话或要求再次提交登录。
      _error = UiError(
        code: failure.code,
        kind: failure.kind,
        issueId: failure.issueId,
        title: form.rememberPassword ? '已登录，保存未完成' : '已登录，清除未完成',
        message: form.rememberPassword
            ? '已登录，但账号密码未能保存，下次需要重新输入。'
            : '已登录，但之前保存的账号密码未能清除，请稍后重试。',
      );
    }
  }

  Future<void> _logout({required bool clearSavedCredential}) async {
    if (_disposed) {
      if (clearSavedCredential) {
        throw const CredentialVaultException(
          CredentialVaultErrorCode.unavailable,
        );
      }
      return;
    }
    if (_loggingOut) {
      if (clearSavedCredential) {
        throw const BackendException(UbaaErrorCode.operationConflict);
      }
      return;
    }
    // 先阻止后台恢复重入，再发出转换通知；明确退出也消费后续自动恢复。
    _loggingOut = true;
    _credentialRestoreAllowed = false;
    _manualAuthenticationRequired = true;
    final generation = ++_authGeneration;
    _beginWriteTransition();
    _releaseLoginSecret();
    try {
      // 若后台替换已经开始，先等待有效 handle 就绪，不能向正在释放的
      // 旧 backend 发注销，也不能让其随后恢复出的会话覆盖退出结果。
      await _backendRebuildCompletion?.future;
      if (!_canFinishLogout(generation, clearSavedCredential)) return;
      try {
        await _backend.logout();
      } on Object catch (error, stackTrace) {
        if (_isCurrentAuthentication(generation)) {
          _recordFailure(
            error,
            DiagnosticOperation.logout,
            stackTrace: stackTrace,
          );
        }
      }
      if (!_canFinishLogout(generation, clearSavedCredential)) return;
      if (clearSavedCredential) {
        try {
          await _mutateCredential(generation, _credentialVault.clear);
        } on Object catch (error, stackTrace) {
          if (_isCurrentAuthentication(generation)) {
            _recordFailure(
              error,
              DiagnosticOperation.logout,
              stackTrace: stackTrace,
            );
          }
          throw error is CredentialVaultException
              ? error
              : const CredentialVaultException(
                  CredentialVaultErrorCode.storageFailure,
                );
        }
        if (!_canFinishLogout(generation, clearSavedCredential)) return;
        _loginForm = LoginFormState(routePolicy: _loginForm.routePolicy);
      }
    } finally {
      // 删除失败也必须丢弃用户、读取快照和活动路线；失败继续交给宿主
      // 汇总其他本地清理结果，不能让个人数据留在已退出的页面。
      if (_isCurrentAuthentication(generation)) {
        _user = null;
        _error = null;
        _activeRoutes = const <ConnectionMode>[];
        _releaseLoginSecret();
        _resetFeatureSnapshots();
        _setPhase(AppPhase.login);
      }
      _endWriteTransition();
      _loggingOut = false;
      _notify();
    }
  }

  bool _canFinishLogout(int generation, bool clearSavedCredential) {
    if (_isCurrentAuthentication(generation)) return true;
    // 迟到结果仍不能回写新账号；明确清除被销毁等边界取消时必须如实失败。
    if (clearSavedCredential) {
      throw const CredentialVaultException(
        CredentialVaultErrorCode.storageFailure,
      );
    }
    return false;
  }

  Future<void> _mutateCredential(
    int generation,
    Future<void> Function() mutate,
  ) async {
    final previous = _credentialMutation;
    final pending = () async {
      if (previous != null) {
        try {
          await previous;
        } on Object {
          // 前一个保存失败仍需尝试用户随后要求的清除。
        }
      }
      if (_isCurrentAuthentication(generation)) await mutate();
    }();
    // 清除必须排在已经发起的保存之后，防止退出后迟到保存重新留下密码。
    _credentialMutation = pending;
    try {
      await pending;
    } finally {
      if (identical(_credentialMutation, pending)) _credentialMutation = null;
    }
  }
}

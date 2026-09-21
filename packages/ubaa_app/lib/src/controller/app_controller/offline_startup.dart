part of '../app_controller.dart';

extension _AppControllerOfflineStartup on AppController {
  Future<bool> _initializeLocalHome() async {
    final epoch = _lifecycleEpoch;
    final store = _localAccountStore!;
    _setPhase(AppPhase.checkingSession);
    try {
      var index = await store.read();
      if (_disposed || epoch != _lifecycleEpoch) return true;
      if (index == null) {
        // 一次性迁移只建立本机索引，不因升级启用旧密码的自动提交。
        final saved = await _credentialVault.read();
        if (_disposed || epoch != _lifecycleEpoch) return true;
        if (saved != null && saved.isUsable) {
          index = await store.retain(saved.username, retainSession: true);
        }
      }
      if (_disposed || epoch != _lifecycleEpoch) return true;
      if (index == null) return false;
      if (!index.canRestore || index.account == null) {
        _sessionRecoveryStatus = SessionRecoveryStatus.signedOut;
        _setPhase(AppPhase.login);
        return true;
      }
      _localAccount = index.account;
      _user = UserSummary(username: index.account!.username);
      _loginForm = _loginForm.copyWith(username: index.account!.username);
      _usesLocalRecovery = true;
      _sessionRecoveryStatus = SessionRecoveryStatus.idle;
      _setPhase(AppPhase.home);
      unawaited(_restoreCachedHome(index.account!, epoch));
      return true;
    } on Object catch (error, stackTrace) {
      if (_disposed || epoch != _lifecycleEpoch) return true;
      // 密钥不可读时只展示非敏感外壳，允许首帧后尝试原会话，不读取密文正文。
      _usesLocalRecovery = true;
      _user = null;
      _error = _recordFailure(
        error,
        DiagnosticOperation.initialization,
        stackTrace: stackTrace,
      );
      _setPhase(AppPhase.home);
      return true;
    }
  }

  Future<void> _recoverSession() {
    if (_disposed ||
        _isSigningOut ||
        !_usesLocalRecovery ||
        _phase != AppPhase.home)
      return Future<void>.value();
    final existing = _sessionRecoveryFuture;
    if (existing != null) return existing;
    // 已准备/提交的操作使用自己的路线和资格；认证不能破坏它的生命周期。
    if (_recoveryMustWait) return _deferRecovery();
    final deferred = _deferredRecovery;
    _deferredRecovery = null;
    final completer = Completer<void>();
    _sessionRecoveryFuture = completer.future;
    final epoch = _lifecycleEpoch;
    _writeTransitions++;
    _sessionRecoveryStatus = SessionRecoveryStatus.restoring;
    _writeCoordinator.invalidate();
    _notify();
    unawaited(
      _performSessionRecovery(epoch).whenComplete(() {
        _writeTransitions--;
        _sessionRecoveryFuture = null;
        if (!_disposed) _notify();
        completer.complete();
        if (deferred != null && !deferred.isCompleted) deferred.complete();
      }),
    );
    return completer.future;
  }

  bool _recoveryIsCurrent(int epoch) =>
      !_disposed && epoch == _lifecycleEpoch && _phase == AppPhase.home;

  Future<void> _performSessionRecovery(int epoch) async {
    try {
      if (_backend case final RouteSettingsBackend settings) {
        final result = await settings.routeSettings();
        if (!_recoveryIsCurrent(epoch)) return;
        _applyRouteSettings(result);
      }
      final status = await _backend.authStatus();
      if (!_recoveryIsCurrent(epoch)) return;
      if (status == AuthStatus.signedOut) {
        final saved = await _credentialVault.read();
        if (!_recoveryIsCurrent(epoch)) return;
        if (saved == null ||
            !saved.isUsable ||
            !saved.autoLogin ||
            !_credentialVault.isAvailable ||
            (_localAccount != null &&
                saved.username != _localAccount!.username) ||
            (_localAccount == null &&
                _user != null &&
                saved.username != _user!.username &&
                saved.username != _user!.schoolId)) {
          _sessionRecoveryStatus = SessionRecoveryStatus.needsLogin;
          return;
        }
        await _backend.login(
          LoginInput(
            username: saved.username,
            password: saved.password,
            rememberPassword: true,
            autoLogin: true,
            routePolicy: _loginForm.routePolicy,
          ),
        );
        if (!_recoveryIsCurrent(epoch)) return;
      }
      final profile = await _backend.userInfo();
      if (!_recoveryIsCurrent(epoch)) return;
      if (profile == null) {
        _sessionRecoveryStatus = SessionRecoveryStatus.needsLogin;
        return;
      }
      final expected = _localAccount?.username ?? _user?.username;
      if (expected != null &&
          profile.username != expected &&
          profile.schoolId != expected) {
        // 禁止把另一账号的在线结果绑定到旧账号的本地内容。
        await _rejectMismatchedAccount();
        return;
      }
      await _refreshRouteSettings();
      if (!_recoveryIsCurrent(epoch)) return;
      _user = profile;
      _error = null;
      _sessionRecoveryStatus = SessionRecoveryStatus.ready;
      _notify();
      if (_appForeground) unawaited(refreshHome());
    } on Object catch (error, stackTrace) {
      if (!_recoveryIsCurrent(epoch)) return;
      if (error is BackendException &&
          error.code == UbaaErrorCode.invalidCredentials) {
        try {
          await _credentialVault.clear();
        } on Object {
          /* 原错误仍然保留。 */
        }
        if (!_recoveryIsCurrent(epoch)) return;
      }
      _error = _recordFailure(
        error,
        DiagnosticOperation.initialization,
        stackTrace: stackTrace,
      );
      _sessionRecoveryStatus =
          error is CredentialVaultException ||
              error is SecureMaterialException ||
              (error is BackendException &&
                  (error.code == UbaaErrorCode.authenticationRequired ||
                      error.code == UbaaErrorCode.invalidCredentials ||
                      error.code == UbaaErrorCode.upstreamChanged))
          ? SessionRecoveryStatus.needsLogin
          : SessionRecoveryStatus.unavailable;
    }
  }

  Future<void> _requireReadSession() async {
    if (!_usesLocalRecovery) return;
    final pending = _sessionRecoveryFuture;
    if (pending != null) await pending;
    if (_disposed)
      throw const BackendException(UbaaErrorCode.operationConflict);
    if (_sessionRecoveryStatus != SessionRecoveryStatus.ready) {
      throw BackendException(
        _sessionRecoveryStatus == SessionRecoveryStatus.unavailable
            ? UbaaErrorCode.networkError
            : UbaaErrorCode.authenticationRequired,
      );
    }
  }

  Future<void> _retainCurrentAccount({
    required String username,
    required bool retainSession,
  }) async {
    final store = _localAccountStore;
    if (store == null || _user == null) return;
    final epoch = _lifecycleEpoch;
    try {
      final index = await store.retain(username, retainSession: retainSession);
      if (_disposed || epoch != _lifecycleEpoch) return;
      _localAccount = index.account;
      _usesLocalRecovery = true;
      if (index.account != null)
        await _restoreCachedHome(index.account!, epoch);
    } on Object catch (error, stackTrace) {
      // 在线登录成功与能否保留本机材料是两件事，保存失败不得假装未登录。
      _error = _recordFailure(
        error,
        DiagnosticOperation.initialization,
        stackTrace: stackTrace,
      );
    }
  }
}

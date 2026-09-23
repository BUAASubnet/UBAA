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
      // 先登记本地打开任务，状态通知中的详情读取也能等待同一账号句柄。
      // 不等待磁盘，首页首帧仍只依赖轻量账号索引。
      unawaited(_restoreCachedHome(index.account!));
      _setPhase(AppPhase.home);
      if (_homeFrameReported) {
        // backend 在已展示首页后被显式替换时不会再产生新的首帧；仍须
        // 沿既有恢复任务重新核对继任实例的会话和身份。
        unawaited(recoverSession());
      }
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

  Future<void> _recoverSession({
    FeatureId feature = FeatureId.schedule,
    bool refreshHomeAfter = true,
  }) {
    if (_disposed ||
        _isSigningOut ||
        _clearingBusinessCache ||
        !_usesLocalRecovery ||
        _phase != AppPhase.home)
      return Future<void>.value();
    final active = _activeRecovery;
    if (active != null && active.feature == feature) {
      active.refreshHomeAfter |= refreshHomeAfter;
      active.interactive |= !refreshHomeAfter;
      return active.completion.future;
    }
    final request = _queuedRecoveries.putIfAbsent(
      feature,
      () => _RecoveryRequest(feature, _lifecycleEpoch, refreshHomeAfter),
    );
    request.refreshHomeAfter |= refreshHomeAfter;
    request.interactive |= !refreshHomeAfter;
    _startNextRecovery();
    return request.completion.future;
  }

  bool _recoveryIsCurrent(int epoch) =>
      !_disposed && epoch == _lifecycleEpoch && _phase == AppPhase.home;

  Future<void> _performSessionRecovery(
    _RecoveryRequest request, {
    bool allowRebuild = true,
  }) async {
    final epoch = request.epoch;
    try {
      if (_backend case final RouteSettingsBackend settings) {
        final result = await settings.routeSettings();
        if (!_recoveryIsCurrent(epoch)) return;
        _applyRouteSettings(result);
      }
      final backend = _backend;
      final profile = backend is RequiredSessionBackend
          ? await _recoverRequiredProfile(
              backend as RequiredSessionBackend,
              request.feature,
              epoch,
            )
          : await _recoverLegacyProfile(epoch);
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
      unawaited(_queueProfileRefresh());
      unawaited(_loadWriteReadbacks());
      _invalidateReadPlansAfterLogin(request);
      _notify();
      for (final entry in request.queriesAfterRebuild.entries) {
        if (!_recoveryIsCurrent(epoch)) return;
        if (_snapshots[entry.key]!.readContext?.hasSameQuery(entry.value) ==
            true)
          unawaited(refreshFeatureQuery(entry.key, entry.value));
      }
      request.queriesAfterRebuild.clear();
      if (request.refreshHomeAfter) _pendingHomeRecoveryEpoch = epoch;
    } on Object catch (caughtError, caughtStackTrace) {
      Object error = caughtError;
      StackTrace stackTrace = caughtStackTrace;
      if (!_recoveryIsCurrent(epoch)) return;
      if (allowRebuild && error is BackendException && error.clientDisposed) {
        try {
          if (await _rebuildDuringRecovery(request)) {
            await _performSessionRecovery(request, allowRebuild: false);
            return;
          }
        } on Object catch (replacementError, replacementTrace) {
          error = replacementError;
          stackTrace = replacementTrace;
        }
        if (!_recoveryIsCurrent(request.epoch)) return;
      }
      request.transientFailure = _temporaryRecoveryFailure(error);
      if (error is BackendException &&
          (error.code == UbaaErrorCode.invalidCredentials ||
              error.code == UbaaErrorCode.upstreamChanged)) {
        _automaticCredentialBlocked = true;
      }
      if (error is BackendException &&
          error.code == UbaaErrorCode.invalidCredentials) {
        try {
          await _credentialVault.clear();
        } on Object {
          /* 原错误仍然保留。 */
        }
        if (!_recoveryIsCurrent(request.epoch)) return;
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

  Future<void> _requireReadSession({FeatureId? feature}) async {
    if (!_usesLocalRecovery) return;
    if (_backend is RequiredSessionBackend &&
        feature != null &&
        recoveryStatusFor(feature) == SessionRecoveryStatus.ready)
      return;
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
      if (index.account != null) {
        // 手动登录已沿原userInfo读取完整资料；不让随后开启的磁盘读取倒退展示。
        _profileDisplay = profileDisplay(
          _user!,
          null,
          null,
          accountScope: index.account!.id,
        );
        _profileDisplayEpoch = epoch;
        await _restoreCachedHome(index.account!);
      }
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

part of '../../app_controller.dart';

/// 宿主本地偏好的拥有者及其生命期，不包含凭据或写资格。
final class LocalDataOwnerScope {
  LocalDataOwnerScope._(this._controller)
    : _epoch = _controller._lifecycleEpoch,
      accountKey = _controller._user?.schoolId?.trim().isNotEmpty == true
          ? _controller._user!.schoolId!
          : (_controller._user?.username ?? ''),
      identities = Set.unmodifiable(
        {
          _controller._localAccount?.username,
          _controller._user?.username,
          _controller._user?.schoolId,
        }.whereType<String>().where((key) => key.trim().isNotEmpty),
      );

  final AppController _controller;
  final int _epoch;
  final String accountKey;
  final Set<String> identities;

  void checkCurrent() {
    final c = _controller;
    if (c._disposed ||
        c._isSigningOut ||
        c._phase != AppPhase.home ||
        c._lifecycleEpoch != _epoch) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
  }
}

extension AppControllerLocalData on AppController {
  LocalDataOwnerScope get localDataOwnerScope => LocalDataOwnerScope._(this);
}

extension _AppControllerLogout on AppController {
  Future<void> _logoutController({
    required bool clearSavedCredential,
    Future<void> Function()? clearLocalData,
  }) async {
    if (_disposed || _isSigningOut) {
      if (clearSavedCredential) {
        throw const BackendException(UbaaErrorCode.operationConflict);
      }
      return;
    }
    _isSigningOut = true;
    _credentialRestoreAllowed = false;
    _manualAuthenticationRequired = true;
    _cancelDeferredRecovery();
    _beginWriteTransition();
    _sessionRecoveryStatus = SessionRecoveryStatus.signedOut;
    _user = null;
    _activeRoutes = const <ConnectionMode>[];
    _loginForm = _loginForm.copyWith(password: '', captcha: '');
    _resetFeatureSnapshots();
    _setPhase(AppPhase.login);
    (Object, StackTrace)? failure;
    Future<void> attempt(Future<void> Function() action) async {
      try {
        await action();
      } on Object catch (error, stackTrace) {
        failure ??= (error, stackTrace);
        _error = _recordFailure(
          error,
          DiagnosticOperation.logout,
          stackTrace: stackTrace,
        );
      }
    }

    try {
      await _backendRebuildCompletion?.future;
      if (_disposed) {
        if (clearSavedCredential)
          throw const CredentialVaultException(
            CredentialVaultErrorCode.storageFailure,
          );
        return;
      }
      await attempt(() async => _localAccountStore?.signOut());
      // 必须保持Core清除成功后才移除账号密钥的原有顺序。
      await attempt(() => _closeOfflineAccount(remove: clearSavedCredential));
      await attempt(_backend.logout);
      if (clearSavedCredential) {
        if (_disposed)
          throw const CredentialVaultException(
            CredentialVaultErrorCode.storageFailure,
          );
        await attempt(
          () => _mutateCredential(_lifecycleEpoch, _credentialVault.clear),
        );
        if (_disposed)
          throw const CredentialVaultException(
            CredentialVaultErrorCode.storageFailure,
          );
        if (clearLocalData != null) await attempt(clearLocalData);
      }
      if (!_disposed) {
        _user = null;
        _activeRoutes = const <ConnectionMode>[];
        _loginForm = clearSavedCredential && failure == null
            ? LoginFormState(routePolicy: _loginForm.routePolicy)
            : _loginForm.copyWith(password: '', captcha: '');
        _resetFeatureSnapshots();
        _setPhase(AppPhase.login);
      }
      if (clearSavedCredential && failure != null) {
        Error.throwWithStackTrace(failure!.$1, failure!.$2);
      }
    } finally {
      _isSigningOut = false;
      _endWriteTransition();
    }
  }
}

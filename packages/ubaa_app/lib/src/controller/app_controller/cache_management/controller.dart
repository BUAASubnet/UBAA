part of '../../app_controller.dart';

extension _AppControllerCacheManagement on AppController {
  bool _cacheOwnerCurrent(String accountId, UbaaBackend backend, int epoch) =>
      !_disposed &&
      !_isSigningOut &&
      _phase == AppPhase.home &&
      _localAccount?.id == accountId &&
      identical(_backend, backend) &&
      epoch == _lifecycleEpoch;

  void _checkCacheManagement(String accountId) {
    if (_disposed ||
        _isSigningOut ||
        _phase != AppPhase.home ||
        _localAccount?.id != accountId ||
        _clearingBusinessCache ||
        isLoggingIn ||
        _rebuildingBackend ||
        _writeTransitions != 0 ||
        _activeRecovery != null ||
        _writeCoordinator.hasPendingOperation) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
    if (_backend is! CacheManagementBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
  }

  Future<CacheUsageSummary> _readCacheUsage(String accountId) async {
    // 数值读取不需要认证或写资格，只避开本地清理和账号切换。
    if (_disposed || cacheAccountId != accountId || _clearingBusinessCache) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
    final backend = _backend, epoch = _lifecycleEpoch;
    await _offlineOpenFuture;
    if (!_cacheOwnerCurrent(accountId, backend, epoch)) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
    final value = await (backend as CacheManagementBackend).cacheUsage(
      accountId: accountId,
    );
    if (!_cacheOwnerCurrent(accountId, backend, epoch) ||
        value.accountId != accountId) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
    return value;
  }

  Future<CacheClearOutcome> _clearControllerCache(String accountId) async {
    _checkCacheManagement(accountId);
    final backend = _backend;
    var epoch = _lifecycleEpoch;
    _clearingBusinessCache = true;
    _writeTransitions++;
    _cancelDeferredRecovery();
    _notify();
    try {
      // 初次保险箱读取可能尚未完成；不能先失效它而使后台从未打开缓存。
      await _offlineOpenFuture;
      if (!_cacheOwnerCurrent(accountId, backend, epoch)) {
        throw const BackendException(UbaaErrorCode.operationConflict);
      }
      epoch = ++_lifecycleEpoch;
      // 清理移交了仓库所有权，旧首页读取不能按路线切换重试。
      _offlineAccountEpoch++;
      _ygdkGeneration++;
      for (final scope in _readScopes.toList()) {
        scope.cancel();
      }
      _pumpReadTasks();
      if (_legacyGradeScores != null) {
        await _clearLegacyGradeScores();
        if (!_cacheOwnerCurrent(accountId, backend, epoch)) {
          throw const BackendException(UbaaErrorCode.operationConflict);
        }
      }
      final result = await _clearBackendCache(backend, accountId, epoch);
      if (!_cacheOwnerCurrent(accountId, backend, epoch)) {
        throw const BackendException(UbaaErrorCode.operationConflict);
      }
      _clearBusinessProjections();
      _businessCacheEpoch++;
      _localCacheError = result.cacheReady
          ? null
          : UbaaErrorMapper.fromCode(UbaaErrorCode.internalError);
      return result;
    } finally {
      if (_cacheOwnerCurrent(accountId, backend, epoch))
        _settleCancelledLoads();
      _clearingBusinessCache = false;
      _writeTransitions--;
      _notify();
    }
  }

  Future<CacheClearOutcome> _clearBackendCache(
    UbaaBackend backend,
    String accountId,
    int epoch,
  ) async {
    if (backend is! CacheRecoveryBackend) {
      return (backend as CacheManagementBackend).clearBusinessCache(
        accountId: accountId,
      );
    }
    final store = _localAccountStore, account = _localAccount;
    if (store == null || account == null || account.id != accountId) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
    final key = await store.cacheKey(account);
    try {
      if (!_cacheOwnerCurrent(accountId, backend, epoch)) {
        throw const BackendException(UbaaErrorCode.operationConflict);
      }
      return await (backend as CacheRecoveryBackend)
          .clearOrRebuildBusinessCache(account: account, key: key);
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  void _clearBusinessProjections() {
    _clearWriteReadbacks();
    for (final feature in FeatureId.values) {
      _snapshots[feature] = FeatureSnapshot(
        feature: feature,
        readContext: _snapshots[feature]!.readContext,
      );
      _homeDefaults[feature] = FeatureSnapshot(
        feature: feature,
        readContext: _homeDefaults[feature]!.readContext,
      );
    }
    _profileDisplay = null;
    _profileDisplayEpoch = -1;
    _profileRefreshedEpoch = -1;
    _profileFailureEpoch = -1;
    _profileRequest = null;
    _homeSupplementCache = null;
    _gradesReadCache = null;
    _academicWeeksCache = null;
    _cgyyPurposeCache = null;
    _academicTermsResult = null;
    _academicTermsPending = null;
    _academicTermsSerial++;
    _ygdkReadbackState = const YgdkReadbackState.empty();
  }

  void _settleCancelledLoads() {
    for (final snapshots in [_snapshots, _homeDefaults]) {
      for (final feature in FeatureId.values) {
        final value = snapshots[feature]!;
        if (value.status != FeatureLoadStatus.loading) continue;
        snapshots[feature] = value.copyWith(
          status:
              value.details.isNotEmpty ||
                  value.overview != null ||
                  value.evidence != null
              ? FeatureLoadStatus.stale
              : FeatureLoadStatus.idle,
        );
      }
    }
  }
}

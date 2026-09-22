part of '../../app_controller.dart';

extension _AppControllerOfflineCache on AppController {
  Future<void> _restoreCachedHome(LocalAccount account) async {
    final backend = _backend;
    if (backend is! OfflineCacheBackend) return;
    final offline = backend as OfflineCacheBackend;
    final accountEpoch = ++_offlineAccountEpoch;
    final opened = Completer<void>();
    _offlineOpenFuture = opened.future;
    bool current() =>
        !_disposed &&
        !_isSigningOut &&
        !_rebuildingBackend &&
        accountEpoch == _offlineAccountEpoch &&
        identical(backend, _backend) &&
        _localAccount?.id == account.id &&
        (_phase == AppPhase.home || _phase == AppPhase.loggingIn);
    try {
      final key = await _localAccountStore!.cacheKey(account);
      try {
        if (!current()) return;
        await offline.openOfflineAccount(account, key);
        opened.complete();
      } finally {
        key.fillRange(0, key.length, 0);
      }
      if (!current()) return;
      final profileEpoch = _lifecycleEpoch;
      unawaited(_restoreCachedProfile(backend, account, profileEpoch));
      final read = await _readCurrentCachedHome(offline, current);
      if (read == null || !current()) return;
      final (projections, policy, readEpoch) = read;
      if (readEpoch != _lifecycleEpoch || policy != _loginForm.routePolicy)
        return;
      if (readEpoch != profileEpoch)
        unawaited(_restoreCachedProfile(backend, account, readEpoch));
      for (final projection in projections) {
        final supplement =
            (projection.feature == FeatureId.bykc &&
                projection.readContext.query?.view ==
                    FeatureQueryView.bykcChosenCourses) ||
            (projection.feature == FeatureId.cgyy &&
                projection.readContext.query?.view ==
                    FeatureQueryView.cgyyOrders);
        if (projection.accountId != account.id ||
            (policy == RoutePolicy.direct &&
                projection.route != ConnectionMode.direct) ||
            (policy == RoutePolicy.webvpn &&
                projection.route != ConnectionMode.webvpn) ||
            (!_homeDefaultFeatures.contains(projection.feature) && !supplement))
          continue;
        final previous = _homeDefaults[projection.feature]!;
        // 磁盘慢于网络时不能倒退；当前查询面板不接收首页默认查询的数据。
        if ((previous.evidence != null &&
                previous.evidence!.origin != DataOrigin.persisted) ||
            previous.status == FeatureLoadStatus.success ||
            previous.status == FeatureLoadStatus.empty)
          continue;
        final snapshot = projection.toSnapshot().copyWith(
          readContext: supplement
              ? projection.readContext
              : previous.readContext,
        );
        _homeDefaults[projection.feature] = snapshot;
        if (supplement) continue;
        final visible = _snapshots[projection.feature]!;
        if (visible.readContext?.query == null &&
            (visible.evidence == null ||
                visible.evidence!.origin == DataOrigin.persisted) &&
            visible.status != FeatureLoadStatus.success &&
            visible.status != FeatureLoadStatus.empty) {
          _snapshots[projection.feature] = snapshot.copyWith(
            readContext: visible.readContext,
          );
        }
      }
      _localCacheError = projections.error == null
          ? null
          : _recordFailure(
              projections.error!,
              DiagnosticOperation.initialization,
            );
      _notify();
    } on Object catch (error, stackTrace) {
      if (!current()) return;
      _localCacheError = _recordFailure(
        error,
        DiagnosticOperation.initialization,
        stackTrace: stackTrace,
      );
      _notify();
    } finally {
      if (!opened.isCompleted) opened.complete();
    }
  }

  Future<(OfflineHomeRead, RoutePolicy, int)?> _readCurrentCachedHome(
    OfflineCacheBackend offline,
    bool Function() ownsAccount,
  ) async {
    // 账号库的打开不从属于某条路线；投影则每次固定路线和页面代次。
    while (ownsAccount()) {
      final epoch = _lifecycleEpoch, policy = _loginForm.routePolicy;
      try {
        final result = await offline.readCachedHome(policy);
        if (!ownsAccount()) return null;
        if (epoch != _lifecycleEpoch || policy != _loginForm.routePolicy)
          continue;
        return (result, policy, epoch);
      } on Object {
        if (!ownsAccount()) return null;
        if (epoch != _lifecycleEpoch || policy != _loginForm.routePolicy)
          continue;
        rethrow;
      }
    }
    return null;
  }

  Future<void> _closeOfflineAccount({bool remove = false}) async {
    _offlineAccountEpoch++;
    final backend = _backend;
    if (backend is OfflineCacheBackend) {
      final offline = backend as OfflineCacheBackend;
      await offline.deactivateOfflineAccount();
      if (remove) await offline.clearOfflineAccount();
    }
    final account = _localAccount;
    if (remove && account != null)
      await _localAccountStore?.removeAccount(account.id);
  }

  Future<void> _rejectMismatchedAccount() async {
    _lifecycleEpoch++;
    _readCacheEpoch++;
    _user = null;
    _resetFeatureSnapshots();
    _sessionRecoveryStatus = SessionRecoveryStatus.needsLogin;
    _setPhase(AppPhase.login);
    try {
      // 同步入队两个关闭动作，不能在等待安全索引时让新登录先启用缓存。
      await Future.wait<void>([
        _localAccountStore?.signOut() ?? Future<void>.value(),
        _closeOfflineAccount(),
      ]);
    } on Object catch (error, stackTrace) {
      _error = _recordFailure(
        error,
        DiagnosticOperation.logout,
        stackTrace: stackTrace,
      );
    }
  }
}

part of '../../app_controller.dart';

extension _AppControllerBackendRecovery on AppController {
  Future<bool> _rebuildDuringRecovery(_RecoveryRequest request) async {
    final factory = _backendFactory;
    if (factory == null ||
        !_appForeground ||
        _rebuildingBackend ||
        _clearingBusinessCache ||
        _isSigningOut ||
        !_recoveryIsCurrent(request.epoch) ||
        !identical(_activeRecovery, request) ||
        _writeTransitions != 1 ||
        _writeCoordinator.hasPendingOperation)
      return false;
    _rebuildingBackend = true;
    try {
      final previous = _backend;
      final replacement = factory();
      if (identical(previous, replacement))
        throw const BackendException(UbaaErrorCode.internalError);
      _invalidateReadsForRebuild(request);
      _featureRecoveryStates.clear();
      _featureRecoveryErrors.clear();
      _recoveredRoute = null;
      _activeRoutes = const [];
      _preserveReadonlyAfterRebuild();
      _notify();
      try {
        await _disposeBackendOnce(previous);
      } on Object catch (error, stackTrace) {
        _recordFailure(
          error,
          DiagnosticOperation.disposal,
          stackTrace: stackTrace,
        );
      }
      if (!_recoveryIsCurrent(request.epoch) || _isSigningOut) {
        try {
          await _disposeBackendOnce(replacement);
        } on Object {
          // 退出/销毁的原错误不被继任实例释放错误替换。
        }
        return false;
      }
      // 释放旧实例期间页面仍可操作；此时新排队的查询也须交给继任实例。
      _invalidateReadsForRebuild(request);
      _backend = replacement;
      _replaceWriteCoordinator(replacement);
      _profileRefreshedEpoch = -1;
      _profileFailureEpoch = -1;
      _profileRequest = null;
      _rebuildingBackend = false;
      final account = _localAccount;
      if (account != null) unawaited(_restoreCachedHome(account));
      return true;
    } finally {
      _rebuildingBackend = false;
      _notify();
    }
  }

  void _invalidateReadsForRebuild(_RecoveryRequest request) {
    for (final scope in _readScopes.toList()) {
      if (scope.valid && scope.query != null)
        request.queriesAfterRebuild[scope.feature] = scope.query!;
      scope.cancel();
    }
    _cancelDeferredRecovery();
    request.epoch = ++_lifecycleEpoch;
    _offlineAccountEpoch++;
    _readCacheEpoch++;
    _ygdkGeneration++;
  }

  void _preserveReadonlyAfterRebuild() {
    for (final snapshots in [_snapshots, _homeDefaults]) {
      for (final feature in FeatureId.values) {
        final old = snapshots[feature]!;
        final hasContent =
            old.details.isNotEmpty ||
            old.overview != null ||
            old.evidence != null;
        snapshots[feature] = old.copyWith(
          status: hasContent ? FeatureLoadStatus.stale : FeatureLoadStatus.idle,
          details: readonlyFeatureDetails(old.details),
          overview: readonlyFeatureOverview(old.overview),
        );
      }
    }
    _homeSupplementCache = null;
    _gradesReadCache = null;
    _academicWeeksCache = null;
    _cgyyPurposeCache = null;
    _academicTermsResult = null;
    _academicTermsPending = null;
    _academicTermsSerial++;
    _ygdkReadbackState = const YgdkReadbackState.empty();
  }
}

part of '../../app_controller.dart';

final class _ReadPlanRestart implements Exception {
  const _ReadPlanRestart();
}

extension _AppControllerScheduledSession on AppController {
  bool get _hasScheduledTargetRecovery =>
      _backend is ProgressiveReadBackend && _backend is RequiredSessionBackend;
  bool get _legacyReadSessionBlocked =>
      _usesLocalRecovery &&
      !_hasScheduledTargetRecovery &&
      _sessionRecoveryStatus != SessionRecoveryStatus.ready;
  bool get _readTransitionBlocked =>
      _writeTransitions != 0 &&
      !(_hasScheduledTargetRecovery && _activeRecovery != null);

  Future<void> _ensureReadTarget(
    FeatureId feature, {
    bool force = false,
  }) async {
    if (!_usesLocalRecovery) return;
    if (_backend is! RequiredSessionBackend) {
      await _requireReadSession(feature: feature);
      return;
    }
    if (force || recoveryStatusFor(feature) != SessionRecoveryStatus.ready) {
      await _recoverSession(feature: feature, refreshHomeAfter: false);
    }
    if (_disposed || _isSigningOut) throw const ReadCancelled();
    final status = recoveryStatusFor(feature);
    if (status == SessionRecoveryStatus.ready) return;
    if (_featureRecoveryErrors[feature] case final error?)
      throw BackendException.fromUi(error);
    throw BackendException(
      status == SessionRecoveryStatus.unavailable
          ? UbaaErrorCode.networkError
          : UbaaErrorCode.authenticationRequired,
    );
  }

  bool _readTargetNeedsRecovery(FeatureId feature) =>
      _usesLocalRecovery &&
      (_backend is RequiredSessionBackend
          ? recoveryStatusFor(feature) != SessionRecoveryStatus.ready
          : _sessionRecoveryStatus != SessionRecoveryStatus.ready);

  Future<void> _scheduleReadAuthentication(
    FeatureId feature,
    ReadPriority priority,
    bool Function() current, {
    bool force = false,
    ReadDemand? demand,
  }) {
    if (!force && !_readTargetNeedsRecovery(feature)) return Future.value();
    return _readScheduler.run(
      priority,
      current,
      () => _ensureReadTarget(feature, force: force),
      demand: demand,
    );
  }

  Future<T> _scheduledRead<T>(
    FeatureId feature,
    ReadPriority priority,
    bool Function() current,
    Future<T> Function() operation, {
    void Function(T)? discard,
    bool writeReadback = false,
    ReadDemand? demand,
  }) async {
    if (writeReadback)
      return _readScheduler.run(
        priority,
        current,
        operation,
        discard: discard,
        continuation: true,
      );
    final recovered = _readTargetNeedsRecovery(feature);
    if (recovered)
      await _scheduleReadAuthentication(
        feature,
        priority,
        current,
        demand: demand,
      );
    try {
      return await _readScheduler.run(
        priority,
        current,
        operation,
        discard: discard,
        continuation: recovered,
        demand: demand,
      );
    } on BackendException catch (error) {
      if (error.code != UbaaErrorCode.authenticationRequired ||
          error.accountMismatch ||
          !_hasScheduledTargetRecovery)
        rethrow;
      _featureRecoveryStates[feature] = SessionRecoveryStatus.needsLogin;
      // 只读请求最多恢复一次；认证错误、缺材料或第二次读取失败直接交付。
      await _scheduleReadAuthentication(
        feature,
        priority,
        current,
        force: true,
        demand: demand,
      );
      return _readScheduler.run(
        priority,
        current,
        operation,
        discard: discard,
        continuation: true,
        demand: demand,
      );
    }
  }

  void _invalidateReadPlansAfterLogin(_RecoveryRequest request) {
    if (!request.replacedAllRoutes && request.replacedRoute == null) return;
    for (final scope in _readScopes) {
      if (scope.task != null &&
          scope.valid &&
          (request.replacedAllRoutes ||
              scope.route == null ||
              scope.route == request.replacedRoute)) {
        scope.restartRequested = true;
        scope.task!.cancel();
      }
    }
  }
}

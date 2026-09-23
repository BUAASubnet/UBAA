part of '../../app_controller.dart';

final class _RecoveryRequest {
  _RecoveryRequest(this.feature, this.epoch, this.refreshHomeAfter)
    : interactive = !refreshHomeAfter;
  final FeatureId feature;
  int epoch;
  bool refreshHomeAfter;
  bool interactive;
  bool transientFailure = false;
  ConnectionMode? replacedRoute;
  bool replacedAllRoutes = false;
  final queriesAfterRebuild = <FeatureId, FeatureQuery>{};
  final completion = Completer<void>();
}

extension _AppControllerDeferredRecovery on AppController {
  bool get _recoveryMustWait =>
      !_appForeground ||
      isLoggingIn ||
      _writeTransitions != 0 ||
      _writeCoordinator.hasPendingOperation;

  void _cancelDeferredRecovery() {
    _clearRecoveryRetries();
    final requests = _queuedRecoveries.values.toList();
    _queuedRecoveries.clear();
    _pendingHomeRecoveryEpoch = null;
    for (final request in requests) {
      if (!request.completion.isCompleted) request.completion.complete();
    }
  }

  void _drainDeferredRecovery() {
    if ((_queuedRecoveries.isEmpty && _pendingHomeRecoveryEpoch == null) ||
        _deferredRecoveryScheduled)
      return;
    if (_disposed || _isSigningOut || _phase == AppPhase.login) {
      _cancelDeferredRecovery();
      return;
    }
    if (_phase != AppPhase.home || _recoveryMustWait || _activeRecovery != null)
      return;
    _deferredRecoveryScheduled = true;
    scheduleMicrotask(() {
      _deferredRecoveryScheduled = false;
      _startNextRecovery();
    });
  }

  void _startNextRecovery() {
    if (_disposed || _isSigningOut || _phase != AppPhase.home) {
      _cancelDeferredRecovery();
      return;
    }
    if (_activeRecovery != null || _recoveryMustWait) return;
    for (final request in _queuedRecoveries.values.toList()) {
      if (request.epoch != _lifecycleEpoch) {
        _queuedRecoveries.remove(request.feature);
        request.completion.complete();
      }
    }
    if (_queuedRecoveries.isEmpty) {
      final epoch = _pendingHomeRecoveryEpoch;
      _pendingHomeRecoveryEpoch = null;
      if (epoch == _lifecycleEpoch) unawaited(refreshHome());
      return;
    }
    // 已发送检查不可抢占；下个安全边界先处理用户显式目标。
    final explicit = _queuedRecoveries.values.where(
      (request) => request.interactive,
    );
    final request = explicit.isEmpty
        ? _queuedRecoveries.values.first
        : explicit.first;
    _queuedRecoveries.remove(request.feature);
    _activeRecovery = request;
    _sessionRecoveryFuture = request.completion.future;
    _writeTransitions++;
    _error = null;
    _sessionRecoveryStatus = SessionRecoveryStatus.restoring;
    _featureRecoveryStates[request.feature] = SessionRecoveryStatus.restoring;
    _writeCoordinator.invalidate();
    _notify();
    unawaited(
      _performSessionRecovery(request).whenComplete(() {
        if (_recoveryIsCurrent(request.epoch)) {
          _featureRecoveryStates[request.feature] = _sessionRecoveryStatus;
          final error = _error;
          if (error == null) {
            _featureRecoveryErrors.remove(request.feature);
          } else {
            _featureRecoveryErrors[request.feature] = error;
          }
        }
        _writeTransitions--;
        _activeRecovery = null;
        _sessionRecoveryFuture = null;
        _finishRecoveryRetry(request);
        request.completion.complete();
        if (!_disposed) _notify();
      }),
    );
  }
}

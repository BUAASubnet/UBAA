part of '../../app_controller.dart';

const _recoveryRetryDelays = [
  Duration(seconds: 30),
  Duration(seconds: 60),
  Duration(minutes: 5),
];

final class _RecoveryRetry {
  _RecoveryRetry(this.epoch, this.attempt, this.query);
  final int epoch;
  final int attempt;
  final FeatureQuery? query;
  Timer? timer;
  bool due = false;
  bool queued = false;
}

bool _temporaryRecoveryFailure(Object? error) {
  final UbaaErrorCode code;
  if (error is BackendException) {
    if (error.accountMismatch || error.retryable == false) return false;
    code = error.code;
  } else if (error is UiError) {
    if (!error.retryable) return false;
    code = error.code;
  } else {
    return false;
  }
  return code == UbaaErrorCode.networkError ||
      code == UbaaErrorCode.timeout ||
      code == UbaaErrorCode.upstreamUnavailable;
}

extension _AppControllerRecoveryRetry on AppController {
  void _clearRecoveryRetries() {
    for (final retry in _recoveryRetries.values) {
      retry.timer?.cancel();
    }
    _recoveryRetries.clear();
    _networkWakeCooldown?.cancel();
    _networkWakeCooldown = null;
  }

  void _finishRecoveryRetry(_RecoveryRequest request) {
    final previous = _recoveryRetries.remove(request.feature);
    previous?.timer?.cancel();
    if (!_recoveryIsCurrent(request.epoch) || _isSigningOut) return;
    if (request.transientFailure) {
      final attempt = ((previous?.attempt ?? -1) + 1).clamp(0, 2);
      _recoveryRetries[request.feature] = _RecoveryRetry(
        request.epoch,
        attempt,
        _snapshots[request.feature]!.readContext?.query,
      );
    } else if (_sessionRecoveryStatus == SessionRecoveryStatus.ready &&
        previous?.query != null) {
      final query = previous!.query!;
      // 只刷新仍属于原查询的失败页；新选项、草稿与导航由现有读代次保护。
      final context = _snapshots[request.feature]!.readContext;
      if (context?.hasSameQuery(query) ?? false) {
        unawaited(_refreshFeatureQuery(request.feature, query));
      }
    }
  }

  void _syncRecoveryRetries() {
    if (_disposed || _isSigningOut || _phase != AppPhase.home) {
      _clearRecoveryRetries();
      return;
    }
    _recoveryRetries.removeWhere((_, retry) {
      if (retry.epoch == _lifecycleEpoch) return false;
      retry.timer?.cancel();
      return true;
    });
    final wait =
        _recoveryMustWait ||
        _activeRecovery != null ||
        _clearingBusinessCache ||
        _rebuildingBackend;
    for (final entry in _recoveryRetries.entries.toList()) {
      final retry = entry.value;
      if (wait) {
        retry.timer?.cancel();
        retry.timer = null;
        continue;
      }
      if (_queuedRecoveries.containsKey(entry.key) || retry.queued) continue;
      if (retry.due) {
        retry.queued = true;
        scheduleMicrotask(() {
          retry.queued = false;
          if (!identical(_recoveryRetries[entry.key], retry) ||
              !_recoveryIsCurrent(retry.epoch) ||
              _recoveryMustWait ||
              _clearingBusinessCache ||
              _rebuildingBackend)
            return;
          retry.due = false;
          unawaited(_recoverSession(feature: entry.key));
        });
      } else {
        retry.timer ??= Timer(_recoveryRetryDelays[retry.attempt], () {
          retry.timer = null;
          retry.due = true;
          _syncRecoveryRetries();
        });
      }
    }
  }

  void _wakeNetworkRecovery() {
    if (_disposed ||
        _isSigningOut ||
        !_appForeground ||
        !_usesLocalRecovery ||
        !_homeFrameReported ||
        _phase != AppPhase.home ||
        _automaticCredentialBlocked ||
        _sessionRecoveryStatus == SessionRecoveryStatus.needsLogin ||
        _networkWakeCooldown != null)
      return;
    // 接口变化不代表认证成功；只唤醒临时失败的恢复和读取。
    for (final snapshot in [..._homeDefaults.values, ..._snapshots.values]) {
      if (_temporaryRecoveryFailure(snapshot.error)) {
        _recoveryRetries.putIfAbsent(
          snapshot.feature,
          () => _RecoveryRetry(
            _lifecycleEpoch,
            0,
            _snapshots[snapshot.feature]!.readContext?.query,
          ),
        );
      }
    }
    if (_recoveryRetries.isEmpty) return;
    _networkWakeCooldown = Timer(const Duration(seconds: 30), () {
      _networkWakeCooldown = null;
    });
    for (final retry in _recoveryRetries.values) {
      retry.timer?.cancel();
      retry.timer = null;
      retry.due = true;
    }
    _syncRecoveryRetries();
  }
}

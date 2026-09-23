part of '../../app_controller.dart';

/// 默认首页与显式查询各自绑定请求修订，不重试写后回读或学校提交。
final class _BusinessRetry {
  _BusinessRetry(this.epoch, this.revision, this.query, this.attempt);
  final int epoch;
  int revision;
  final FeatureQuery? query;
  final int attempt;
  Timer? timer;
  bool due = false;
  bool running = false;
}

extension _AppControllerBusinessRetry on AppController {
  void _clearBusinessRetries() {
    for (final retry in _businessRetries.values) {
      retry.timer?.cancel();
    }
    _businessRetries.clear();
  }

  void _beginBusinessAttempt(
    FeatureId feature,
    FeatureQuery? query,
    int revision,
  ) {
    final key = (feature, query == null);
    final retry = _businessRetries[key];
    if (retry == null) return;
    if (retry.running &&
        retry.epoch == _lifecycleEpoch &&
        FeatureReadContext(
          query: retry.query,
          requestRevision: 0,
        ).hasSameQuery(query)) {
      retry.revision = revision;
    } else {
      retry.timer?.cancel();
      _businessRetries.remove(key);
    }
  }

  void _finishBusinessAttempt(
    FeatureId feature,
    FeatureQuery? query,
    int revision,
    int epoch,
    UiError? error,
  ) {
    final key = (feature, query == null);
    final previous = _businessRetries.remove(key);
    previous?.timer?.cancel();
    if (!_temporaryRecoveryFailure(error) ||
        epoch != _lifecycleEpoch ||
        _disposed ||
        _isSigningOut ||
        _phase != AppPhase.home)
      return;
    // 认证失败交给恢复队列，避免两个退避器同时启动同一个失败范围。
    if (!_businessRetrySessionReady(feature)) return;
    _businessRetries[key] = _BusinessRetry(
      epoch,
      revision,
      query,
      previous == null ? 0 : (previous.attempt + 1).clamp(0, 2),
    );
  }

  bool _businessRetryCurrent((FeatureId, bool) key, _BusinessRetry retry) {
    final snapshot = key.$2 ? _homeDefaults[key.$1] : _snapshots[key.$1];
    return retry.epoch == _lifecycleEpoch &&
        snapshot?.readContext?.requestRevision == retry.revision &&
        (snapshot?.readContext?.hasSameQuery(retry.query) ?? false);
  }

  bool _businessRetrySessionReady(FeatureId feature) =>
      !_usesLocalRecovery ||
      (_backend is RequiredSessionBackend
          ? recoveryStatusFor(feature) == SessionRecoveryStatus.ready
          : _sessionRecoveryStatus == SessionRecoveryStatus.ready);

  bool _businessRetryMustWait(FeatureId feature) =>
      _recoveryMustWait ||
      _activeRecovery != null ||
      _queuedRecoveries.isNotEmpty ||
      _clearingBusinessCache ||
      _rebuildingBackend ||
      !_businessRetrySessionReady(feature);

  void _syncBusinessRetries() {
    _businessRetries.removeWhere((key, retry) {
      if (_businessRetryCurrent(key, retry)) return false;
      retry.timer?.cancel();
      return true;
    });
    for (final entry in _businessRetries.entries.toList()) {
      final retry = entry.value;
      if (retry.running) continue;
      if (_businessRetryMustWait(entry.key.$1)) {
        retry.timer?.cancel();
        retry.timer = null;
        continue;
      }
      if (retry.due) {
        retry.running = true;
        scheduleMicrotask(() async {
          if (!identical(_businessRetries[entry.key], retry)) return;
          if (!_businessRetryCurrent(entry.key, retry) ||
              _businessRetryMustWait(entry.key.$1) ||
              _disposed ||
              _isSigningOut) {
            retry.running = false;
            return;
          }
          retry.due = false;
          try {
            if (retry.query case final query?) {
              await _refreshFeatureQuery(entry.key.$1, query);
            } else {
              await _refreshHome(only: [entry.key.$1]);
            }
          } finally {
            retry.running = false;
            if (!_disposed) _syncBusinessRetries();
          }
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
}

part of '../../app_controller.dart';

final class _ProgressiveScope {
  _ProgressiveScope(this.feature, this.query, this.current);
  final FeatureId feature;
  final FeatureQuery? query;
  final bool Function() current;
  FeatureReadTask? task;
  final completion = Completer<void>();
  bool cancelled = false;
  bool get valid => !cancelled && current();
  void cancel() {
    if (cancelled) return;
    cancelled = true;
    task?.cancel();
  }
}

extension _AppControllerProgressive on AppController {
  Future<void>? _pendingFeatureRead(FeatureId feature, FeatureQuery? query) {
    if (_backend is! ProgressiveReadBackend) return null;
    for (final scope in _readScopes) {
      if (scope.feature == feature &&
          scope.valid &&
          FeatureReadContext(
            query: scope.query,
            requestRevision: 0,
          ).hasSameQuery(query))
        return scope.completion.future;
    }
    return null;
  }

  Future<FeatureResult> _scheduleAuxiliaryRead(
    UbaaBackend backend,
    ReadPriority priority,
    bool Function() current,
    Future<FeatureResult> Function() operation,
  ) => backend is ProgressiveReadBackend
      ? _readScheduler.run(priority, current, operation)
      : Future<FeatureResult>.sync(operation);

  bool _canRunScheduledRead(ReadPriority priority) {
    if (_disposed ||
        _isSigningOut ||
        (_phase != AppPhase.home &&
            !(!_initialized && _phase == AppPhase.splash)) ||
        isLoggingIn ||
        _rebuildingBackend ||
        _writeTransitions != 0)
      return false;
    if (priority == ReadPriority.writeReadback) return true;
    return _appForeground &&
        !_writeCoordinator.hasPendingOperation &&
        _activeRecovery == null &&
        _queuedRecoveries.isEmpty;
  }

  void _pumpReadTasks() {
    for (final scope in _readScopes.toList()) {
      if (!scope.current()) scope.cancel();
    }
    _readScheduler.pump();
  }

  void _cancelJudgeReadScopes(FeatureId feature) {
    if (_backend is! ProgressiveReadBackend || feature != FeatureId.judge)
      return;
    for (final scope
        in _readScopes.where((value) => value.feature == feature).toList()) {
      scope.cancel();
      if (scope.query == null) {
        final previous = _homeDefaults[feature]!;
        _homeDefaults[feature] = previous.copyWith(
          status: previous.details.isEmpty && previous.evidence == null
              ? FeatureLoadStatus.idle
              : FeatureLoadStatus.stale,
        );
      }
    }
  }

  Future<FeatureResult> _readScheduledFeature(
    FeatureId feature,
    FeatureQuery? query,
    _ProgressiveScope scope, {
    required bool writeReadback,
    required void Function(FeatureReadBatch) onBatch,
  }) async {
    final backend = _backend;
    Future<FeatureResult> ordinary() => switch ((backend, query)) {
      (FeatureQueryBackend queries, final FeatureQuery value) =>
        queries.loadFeatureQuery(feature, value),
      _ => backend.loadFeature(feature),
    };
    if (backend is! ProgressiveReadBackend) return ordinary();
    final priority = writeReadback
        ? ReadPriority.writeReadback
        : query == null
        ? ReadPriority.home
        : feature == FeatureId.signin
        ? ReadPriority.urgent
        : ReadPriority.interactive;
    final task = writeReadback
        ? null
        : await _readScheduler.run(
            priority,
            () => scope.valid,
            () => (backend as ProgressiveReadBackend).beginFeatureRead(
              feature,
              query,
            ),
            discard: (task) => task?.cancel(),
          );
    if (task == null)
      return _readScheduler.run(priority, () => scope.valid, ordinary);
    scope.task = task;
    try {
      while (scope.valid) {
        final batch = await _readScheduler.run(
          query == null ? ReadPriority.background : priority,
          () => scope.valid,
          task.next,
        );
        if (batch.finished) return batch.result;
        if (batch.publish) onBatch(batch);
      }
      throw const ReadCancelled();
    } finally {
      task.cancel();
      scope.task = null;
    }
  }
}

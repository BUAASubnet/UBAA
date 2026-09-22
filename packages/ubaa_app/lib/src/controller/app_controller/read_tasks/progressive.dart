part of '../../app_controller.dart';

final class _ProgressiveScope {
  _ProgressiveScope(this.feature, this.query, this.current);
  final FeatureId feature;
  final FeatureQuery? query;
  final bool Function() current;
  FeatureReadTask? task;
  ConnectionMode? route;
  bool restartRequested = false;
  final completion = Completer<void>();
  bool cancelled = false;
  bool get valid => !cancelled && current();
  void cancel() {
    if (cancelled) return;
    cancelled = true;
    task?.cancel();
  }
}

final class _FeatureReadStart {
  const _FeatureReadStart({this.task, this.result});
  final FeatureReadTask? task;
  final FeatureResult? result;
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
    FeatureId feature,
    ReadPriority priority,
    bool Function() current,
    Future<FeatureResult> Function() operation,
  ) async {
    try {
      return await (backend is ProgressiveReadBackend
          ? _scheduledRead(feature, priority, current, operation)
          : Future<FeatureResult>.sync(operation));
    } on BackendException catch (error) {
      // 辅助读取同样绑定账号；普通认证失败可以保旧，明确串号必须关闭。
      if (error.accountMismatch && current()) await _rejectMismatchedAccount();
      rethrow;
    }
  }

  bool _canRunScheduledRead(ReadPriority priority) {
    if (_disposed ||
        _isSigningOut ||
        (_phase != AppPhase.home &&
            !(!_initialized && _phase == AppPhase.splash)) ||
        isLoggingIn ||
        _rebuildingBackend ||
        _writeTransitions != 0 ||
        (_usesLocalRecovery &&
            !_homeFrameReported &&
            _sessionRecoveryStatus == SessionRecoveryStatus.idle))
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
    Future<FeatureResult> ordinary() {
      if (writeReadback &&
          feature == FeatureId.libbook &&
          backend is LibbookReadbackBackend) {
        return (backend as LibbookReadbackBackend).readLibbookAfterWrite(
          query ?? const FeatureQuery(),
        );
      }
      if (writeReadback &&
          feature == FeatureId.cgyy &&
          backend is CgyyReservationReadbackBackend) {
        return (backend as CgyyReservationReadbackBackend).readCgyyAfterWrite(
          query ?? const FeatureQuery(),
        );
      }
      if (writeReadback &&
          feature == FeatureId.bykc &&
          backend is BykcReadbackBackend) {
        return (backend as BykcReadbackBackend).readBykcAfterWrite(
          query ?? const FeatureQuery(),
        );
      }
      if (writeReadback &&
          feature == FeatureId.signin &&
          backend is SigninReadbackBackend) {
        return (backend as SigninReadbackBackend).readSigninAfterWrite();
      }
      return switch ((backend, query)) {
        (FeatureQueryBackend queries, final FeatureQuery value) =>
          queries.loadFeatureQuery(feature, value),
        _ => backend.loadFeature(feature),
      };
    }

    if (backend is! ProgressiveReadBackend) return ordinary();
    final priority = writeReadback
        ? ReadPriority.writeReadback
        : query == null
        ? ReadPriority.home
        : feature == FeatureId.signin
        ? ReadPriority.urgent
        : ReadPriority.interactive;
    if (writeReadback)
      return _scheduledRead(
        feature,
        priority,
        () => scope.valid,
        ordinary,
        writeReadback: true,
      );
    var restarted = false;
    while (scope.valid) {
      scope.restartRequested = false;
      final start = await _scheduledRead(
        feature,
        priority,
        () => scope.valid,
        () async {
          final task = await (backend as ProgressiveReadBackend)
              .beginFeatureRead(feature, query);
          return task == null
              ? _FeatureReadStart(result: await ordinary())
              : _FeatureReadStart(task: task);
        },
        discard: (start) => start.task?.cancel(),
      );
      final task = start.task;
      if (task == null) return start.result!;
      scope.task = task;
      try {
        while (scope.valid) {
          final batchPriority = query == null
              ? ReadPriority.background
              : priority;
          await _scheduleReadAuthentication(
            feature,
            batchPriority,
            () => scope.valid,
          );
          if (scope.restartRequested) throw const _ReadPlanRestart();
          FeatureReadBatch batch;
          try {
            batch = await _readScheduler.run(
              batchPriority,
              () => scope.valid,
              () {
                if (scope.restartRequested) throw const _ReadPlanRestart();
                return task.next();
              },
            );
          } on BackendException catch (error) {
            if (scope.restartRequested) throw const _ReadPlanRestart();
            if (restarted ||
                error.accountMismatch ||
                error.code != UbaaErrorCode.authenticationRequired ||
                !_hasScheduledTargetRecovery)
              rethrow;
            _featureRecoveryStates[feature] = SessionRecoveryStatus.needsLogin;
            await _scheduleReadAuthentication(
              feature,
              batchPriority,
              () => scope.valid,
              force: true,
            );
            throw const _ReadPlanRestart();
          }
          if (scope.restartRequested) throw const _ReadPlanRestart();
          scope.route = batch.result.resolvedRoute ?? scope.route;
          if (batch.finished) return batch.result;
          if (batch.publish) onBatch(batch);
        }
        throw const ReadCancelled();
      } on _ReadPlanRestart {
        if (restarted)
          throw const BackendException(
            UbaaErrorCode.operationConflict,
            retryable: true,
          );
        restarted = true;
      } finally {
        task.cancel();
        scope.task = null;
      }
    }
    throw const ReadCancelled();
  }
}

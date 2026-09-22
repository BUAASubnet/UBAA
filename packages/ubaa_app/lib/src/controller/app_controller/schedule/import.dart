part of '../../app_controller.dart';

final class _ScheduleImportScope {
  _ScheduleImportScope(this.ownerCurrent);
  final bool Function() ownerCurrent;
  final completion = Completer<void>();
  ScheduleImportTask? task;
  bool cancelled = false;
  bool get valid => !cancelled && ownerCurrent();
  void cancel() {
    cancelled = true;
    task?.cancel();
  }
}

extension _AppControllerScheduleImport on AppController {
  void _pruneScheduleImports() {
    if (_scheduleImportEpoch != _lifecycleEpoch) {
      _scheduleImportEpoch = _lifecycleEpoch;
      _scheduleImports.clear();
    }
    for (final entry in _scheduleImportScopes.entries.toList()) {
      if (entry.value.ownerCurrent()) continue;
      entry.value.cancel();
      _scheduleImportScopes.remove(entry.key);
      _scheduleImports.remove(entry.key);
    }
  }

  Future<void> _saveScheduleSemester(String term) {
    if (!canSaveScheduleSemester || term.trim().isEmpty) {
      return Future.error(
        const BackendException(UbaaErrorCode.operationConflict),
      );
    }
    _pruneScheduleImports();
    final previous = _scheduleImportScopes[term];
    if (previous != null && previous.valid) return previous.completion.future;
    final epoch = _lifecycleEpoch, backend = _backend;
    final account = _localAccount?.id;
    final scope = _ScheduleImportScope(
      () =>
          !_disposed &&
          !_isSigningOut &&
          !_clearingBusinessCache &&
          _phase == AppPhase.home &&
          epoch == _lifecycleEpoch &&
          identical(backend, _backend) &&
          account == _localAccount?.id,
    );
    _scheduleImportScopes[term] = scope;
    _scheduleImports[term] = const ScheduleImportState(
      status: ScheduleImportStatus.running,
    );
    _notify();
    unawaited(
      _runScheduleImport(term, scope, backend as ScheduleImportBackend),
    );
    return scope.completion.future;
  }

  void _cancelScheduleImport(String term) {
    final scope = _scheduleImportScopes[term];
    if (scope == null || !scope.valid) return;
    scope.cancel();
    _scheduleImports[term] = ScheduleImportState(
      status: ScheduleImportStatus.cancelled,
      progress: _scheduleImports[term]?.progress,
    );
    _notify();
  }

  Future<void> _runScheduleImport(
    String term,
    _ScheduleImportScope scope,
    ScheduleImportBackend backend,
  ) async {
    try {
      await _offlineOpenFuture;
      final task = await _scheduledRead(
        FeatureId.schedule,
        ReadPriority.background,
        () => scope.valid,
        () => backend.beginScheduleImport(term),
        discard: (task) => task.cancel(),
      );
      scope.task = task;
      while (scope.valid) {
        await _scheduleReadAuthentication(
          FeatureId.schedule,
          ReadPriority.background,
          () => scope.valid,
        );
        final progress = await _readScheduler.run(
          ReadPriority.background,
          () => scope.valid,
          task.next,
        );
        if (progress.term != term)
          throw const BackendException(UbaaErrorCode.upstreamChanged);
        _scheduleImports[term] = ScheduleImportState(
          status: !progress.finished
              ? ScheduleImportStatus.running
              : progress.saved
              ? ScheduleImportStatus.saved
              : ScheduleImportStatus.failed,
          progress: progress,
        );
        _notify();
        if (progress.finished) break;
      }
    } on ReadCancelled {
      // 用户取消或归属变化已清理界面；在途返回不能恢复旧状态。
    } on Object catch (error) {
      if (scope.valid && error is BackendException && error.accountMismatch) {
        await _rejectMismatchedAccount();
      } else if (scope.valid) {
        if (error is BackendException &&
            error.code == UbaaErrorCode.authenticationRequired) {
          _featureRecoveryStates[FeatureId.schedule] =
              SessionRecoveryStatus.needsLogin;
        }
        _scheduleImports[term] = ScheduleImportState(
          status: ScheduleImportStatus.failed,
          progress: _scheduleImports[term]?.progress,
          error: UbaaErrorMapper.fromObject(error),
        );
      }
    } finally {
      scope.task?.cancel();
      if (identical(_scheduleImportScopes[term], scope))
        _scheduleImportScopes.remove(term);
      scope.completion.complete();
      if (!_disposed) _notify();
    }
  }
}

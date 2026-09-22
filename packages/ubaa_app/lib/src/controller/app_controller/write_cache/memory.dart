part of '../../app_controller.dart';

final class _WriteRefreshRequest {
  _WriteRefreshRequest(this.current);
  final bool Function() current;
}

extension _AppControllerWriteCache on AppController {
  Future<WriteCommitResult> _commitWithAccountCache(
    CacheWriteBackend backend,
    String intentId,
    String accountId,
  ) async {
    final epoch = _lifecycleEpoch;
    final intent = _writeCoordinator.intent;
    bool current() =>
        !_disposed &&
        !_isSigningOut &&
        _phase == AppPhase.home &&
        identical(backend, _backend) &&
        epoch == _lifecycleEpoch &&
        _localAccount?.id == accountId;
    void warning(CacheMaintenanceFailure? failure) {
      if (failure != null && current())
        _localCacheError = UbaaErrorMapper.fromCode(
          UbaaErrorCode.internalError,
        );
    }

    try {
      final result = await backend.commitWriteWithCache(
        intentId,
        accountId: accountId,
      );
      warning(result.cacheFailure);
      final changed =
          result.success ||
          result.outcomeUnknown ||
          (result.evaluationResult?.items.any(
                (item) =>
                    item.outcome == EvaluationCourseOutcome.success ||
                    item.outcome == EvaluationCourseOutcome.outcomeUnknown,
              ) ??
              false);
      if (changed && current()) {
        _invalidateWriteProjections(
          result.operation,
          result.resolvedRoute ?? intent?.resolvedRoute,
          current,
        );
      }
      return result;
    } on BackendException catch (error) {
      warning(error.cacheFailure);
      if (current() &&
          error.code == UbaaErrorCode.outcomeUnknown &&
          intent?.intentId == intentId) {
        _invalidateWriteProjections(
          intent!.operation,
          error.resolvedRoute ?? intent.resolvedRoute,
          current,
        );
      }
      rethrow;
    }
  }

  void _invalidateWriteProjections(
    WriteOperation operation,
    ConnectionMode? route,
    bool Function() current,
  ) {
    final feature = switch (operation) {
      WriteOperation.bykcSelectCourse ||
      WriteOperation.bykcDeselectCourse ||
      WriteOperation.bykcSignCourse => FeatureId.bykc,
      WriteOperation.signinPerform => FeatureId.signin,
      WriteOperation.libbookReserve ||
      WriteOperation.libbookCancelBooking => FeatureId.libbook,
      WriteOperation.cgyySubmitReservation ||
      WriteOperation.cgyyCancelOrder => FeatureId.cgyy,
      WriteOperation.ygdkSubmit => FeatureId.ygdk,
      WriteOperation.evaluationSubmitCourses => FeatureId.evaluation,
    };
    // 只清返回帧的旧副本与关联领域的旧动作，业务数据不按全库清除。
    _readCacheEpoch++;
    final generation = ++_readRequestRevision;
    _featureRefreshGenerations[feature] = generation;
    if (feature == FeatureId.ygdk) _ygdkGeneration++;
    for (final scope
        in _readScopes.where((scope) => scope.feature == feature).toList()) {
      scope.cancel();
    }
    for (final values in [_snapshots, _homeDefaults]) {
      final old = values[feature]!;
      final context = FeatureReadContext(
        query: old.readContext?.query,
        requestRevision: generation,
      );
      if (route != null &&
          old.resolvedRoute != null &&
          old.resolvedRoute != route) {
        values[feature] = old.copyWith(readContext: context);
        continue;
      }
      final hasContent =
          old.details.isNotEmpty ||
          old.overview != null ||
          old.evidence != null;
      values[feature] = old.copyWith(
        status: hasContent ? FeatureLoadStatus.stale : FeatureLoadStatus.idle,
        details: readonlyFeatureDetails(old.details),
        overview: readonlyFeatureOverview(old.overview),
        readContext: context,
        error: hasContent
            ? const UiError(
                code: UbaaErrorCode.operationConflict,
                title: '相关内容待更新',
                message: '学校状态可能已变化，正在重新核对相关内容。',
                retryable: true,
                actionLabel: '刷新',
              )
            : null,
      );
    }
    _writeRefreshes[feature] = _WriteRefreshRequest(current);
  }

  bool get _canRefreshAfterWrite =>
      !_disposed &&
      !_isSigningOut &&
      _phase == AppPhase.home &&
      _appForeground &&
      !isLoggingIn &&
      !_clearingBusinessCache &&
      !_rebuildingBackend &&
      _writeTransitions == 0 &&
      !_writeCoordinator.hasPendingOperation &&
      _activeRecovery == null;

  void _drainWriteRefreshes() {
    _writeRefreshes.removeWhere((_, value) => !value.current());
    if (_writeRefreshes.isEmpty ||
        _writeRefreshScheduled ||
        !_canRefreshAfterWrite)
      return;
    _writeRefreshScheduled = true;
    scheduleMicrotask(() {
      _writeRefreshScheduled = false;
      if (!_canRefreshAfterWrite) return;
      final pending = Map.of(_writeRefreshes);
      _writeRefreshes.clear();
      for (final entry in pending.entries) {
        if (!entry.value.current()) continue;
        unawaited(_refreshWrittenFeature(entry.key, entry.value));
      }
    });
  }

  Future<void> _refreshWrittenFeature(
    FeatureId feature,
    _WriteRefreshRequest request,
  ) async {
    if (!request.current()) return;
    final query = _snapshots[feature]!.readContext?.query;
    if (query == null) {
      await _refreshHome(only: [feature]);
    } else {
      await _refreshFeatureQuery(feature, query);
    }
    if (!request.current()) return;
    final source = switch (feature) {
      FeatureId.bykc => HomeSupplement.bykcChosen,
      FeatureId.cgyy => HomeSupplement.cgyyOrders,
      _ => null,
    };
    if (source != null) await _loadHomeSupplement(source, forceRefresh: true);
  }
}

part of '../app_controller.dart';

// 仅预载首页直接展示的来源。博雅已选、研讨室订单、周次与成绩提醒
// 走各自专用读取；其他默认页由导航器在首次打开时加载。
// Bridge 共用会话锁，今日课表和签到先入队，避免被无关查询阻塞。
const _homeDefaultFeatures = <FeatureId>[
  FeatureId.schedule,
  FeatureId.signin,
  FeatureId.spoc,
  FeatureId.judge,
  FeatureId.ygdk,
];

extension _AppControllerRefresh on AppController {
  Future<void> _refreshHome({
    Iterable<FeatureId>? only,
    bool writeReadback = false,
  }) async {
    if (_disposed || _clearingBusinessCache) return;
    final joining = <Future<void>>[];
    final features = <FeatureId>[];
    for (final feature in (only ?? _homeDefaultFeatures).toSet()) {
      final pending = writeReadback ? null : _pendingFeatureRead(feature, null);
      if (pending != null) {
        joining.add(pending);
      } else {
        features.add(feature);
      }
    }
    if (features.isEmpty) {
      await Future.wait(joining);
      return;
    }
    _readCacheEpoch++;
    final lifecycleEpoch = _lifecycleEpoch;
    final generations = <FeatureId, int>{
      for (final feature in features) feature: ++_readRequestRevision,
    };
    final ygdkGeneration =
        features.contains(FeatureId.ygdk) &&
            _snapshots[FeatureId.ygdk]?.readContext?.query == null
        ? ++_ygdkGeneration
        : null;
    for (final feature in features) {
      final generation = generations[feature]!;
      _beginBusinessAttempt(feature, null, generation);
      if (_snapshots[feature]?.readContext?.query != null) {
        _beginHomeDefault(
          feature,
          FeatureReadContext(requestRevision: generation),
        );
      } else {
        _featureRefreshGenerations[feature] = generation;
        _beginFeatureRead(feature, generation, null);
      }
    }
    _notify();
    await Future.wait([
      ...joining,
      ...features.map(
        (feature) => _loadFeature(
          feature,
          generations[feature]!,
          lifecycleEpoch,
          writeReadback: writeReadback,
          ygdkGeneration: feature == FeatureId.ygdk ? ygdkGeneration : null,
        ),
      ),
    ]);
  }

  /// 对支持 [FeatureQueryBackend] 的生产实现执行单领域筛选读取。
  ///
  /// 不支持查询的 fake backend 明确报 unsupported，不会在 Dart 端拼接请求。
  Future<void> _refreshFeatureQuery(
    FeatureId feature,
    FeatureQuery query, {
    bool writeReadback = false,
  }) async {
    if (_disposed || _clearingBusinessCache) return;
    if (!writeReadback) {
      final pending = _pendingFeatureRead(feature, query);
      if (pending != null) {
        await pending;
        return;
      }
    }
    _cancelSegmentedReadScopes(feature);
    // 换学期/视图可复用完整集合；同查询表示明确刷新，继续执行原读取。
    final cachedGrades =
        feature == FeatureId.grades &&
            _snapshots[feature]!.readContext?.hasSameQuery(query) != true
        ? _cachedGradeQuery(query)
        : null;
    final generation = _nextFeatureGeneration(feature);
    _beginBusinessAttempt(feature, query, generation);
    final context = _beginFeatureRead(feature, generation, query);
    if (_backend is! FeatureQueryBackend) {
      _snapshots[feature] = _snapshots[feature]!.copyWith(
        status: FeatureLoadStatus.failure,
        error: UbaaErrorMapper.fromCode(UbaaErrorCode.unsupported),
      );
      _notify();
      return;
    }
    final lifecycleEpoch = _lifecycleEpoch;
    final ygdkGeneration = feature == FeatureId.ygdk ? ++_ygdkGeneration : null;
    _notify();
    await _loadFeature(
      feature,
      generation,
      lifecycleEpoch,
      query: context.query,
      writeReadback: writeReadback,
      cachedResult: cachedGrades,
      ygdkGeneration: ygdkGeneration,
    );
  }

  FeatureReadContext _beginFeatureRead(
    FeatureId feature,
    int generation,
    FeatureQuery? query,
  ) {
    final context = FeatureReadContext(
      query: query,
      requestRevision: generation,
    );
    final previous = _snapshots[feature]!;
    if (query == null) _beginHomeDefault(feature, context);
    _snapshots[feature] = previous.readContext?.hasSameQuery(query) == true
        ? previous.copyWith(
            status: FeatureLoadStatus.loading,
            clearError: true,
            readContext: context,
          )
        : FeatureSnapshot(
            feature: feature,
            status: FeatureLoadStatus.loading,
            readContext: context,
          );
    return context;
  }

  int _nextFeatureGeneration(FeatureId feature) {
    final next = ++_readRequestRevision;
    _featureRefreshGenerations[feature] = next;
    return next;
  }

  Future<void> _loadFeature(
    FeatureId feature,
    int generation,
    int lifecycleEpoch, {
    FeatureQuery? query,
    int? ygdkGeneration,
    FeatureResult? cachedResult,
    bool writeReadback = false,
  }) async {
    // loading 通知可能同步触发注销或切换路线，发请求前再次核对归属。
    if (!_isFeatureLoadCurrent(
          feature,
          generation,
          lifecycleEpoch,
          ygdkGeneration,
        ) &&
        !(query == null &&
            _isHomeDefaultCurrent(feature, generation, lifecycleEpoch))) {
      return;
    }
    final scope = _ProgressiveScope(
      feature,
      query,
      () =>
          _isFeatureLoadCurrent(
            feature,
            generation,
            lifecycleEpoch,
            ygdkGeneration,
          ) ||
          (query == null &&
              _isHomeDefaultCurrent(feature, generation, lifecycleEpoch)),
    );
    _readScopes.add(scope);
    if (query != null && !writeReadback) {
      unawaited(
        _restoreCachedQuery(
          feature,
          query,
          generation,
          lifecycleEpoch,
          ygdkGeneration,
        ),
      );
    }
    final started = DateTime.now();
    var completed = false;
    UiError? outcome;
    final previous = _snapshots[feature]!;
    final hadPreviousData =
        previous.updatedAt != null &&
        (previous.overview != null ||
            previous.details.isNotEmpty ||
            previous.summary?.trim().isNotEmpty == true ||
            previous.evidence != null);
    try {
      if (_usesLocalRecovery &&
          !writeReadback &&
          _backend is! ProgressiveReadBackend) {
        if (query != null && _backend is RequiredSessionBackend) {
          await _recoverSession(feature: feature, refreshHomeAfter: false);
          if (_disposed || lifecycleEpoch != _lifecycleEpoch) return;
          final status = recoveryStatusFor(feature);
          if (status != SessionRecoveryStatus.ready) {
            if (_featureRecoveryErrors[feature] case final error?)
              throw BackendException.fromUi(error);
            throw BackendException(
              status == SessionRecoveryStatus.unavailable
                  ? UbaaErrorCode.networkError
                  : UbaaErrorCode.authenticationRequired,
            );
          }
        } else {
          await _requireReadSession(feature: feature);
        }
        if (_disposed || lifecycleEpoch != _lifecycleEpoch) return;
      }
      final result =
          cachedResult ??
          await _readScheduledFeature(
            feature,
            query,
            scope,
            writeReadback: writeReadback,
            onBatch: (batch) {
              if (!scope.valid) return;
              if (query == null &&
                  _isHomeDefaultCurrent(feature, generation, lifecycleEpoch)) {
                _acceptHomeDefault(
                  feature,
                  batch.result,
                  FeatureReadContext(requestRevision: generation),
                );
                _homeDefaults[feature] = _homeDefaults[feature]!.copyWith(
                  status: FeatureLoadStatus.loading,
                );
              }
              if (_applyFeatureResultIfCurrent(
                feature,
                batch.result,
                generation,
                lifecycleEpoch,
                ygdkGeneration: ygdkGeneration,
                preservePreviousOnFailure: hadPreviousData,
              )) {
                _snapshots[feature] = _snapshots[feature]!.copyWith(
                  status: FeatureLoadStatus.loading,
                );
              }
              _notify();
            },
          );
      completed = true;
      outcome = result.error;
      if (query == null &&
          _isHomeDefaultCurrent(feature, generation, lifecycleEpoch)) {
        _acceptHomeDefault(
          feature,
          result,
          FeatureReadContext(requestRevision: generation),
        );
      }
      if (!_applyFeatureResultIfCurrent(
        feature,
        result,
        generation,
        lifecycleEpoch,
        ygdkGeneration: ygdkGeneration,
        preservePreviousOnFailure: hadPreviousData,
      )) {
        _notify();
        return;
      }
      if (feature == FeatureId.grades) {
        _rememberGradeResult(result, query, fresh: cachedResult == null);
      }
      await _recordFeature(
        feature,
        success:
            result.error == null &&
            !result.isEmpty &&
            result.evidence?.complete != false,
        empty: result.isEmpty && result.evidence?.complete != false,
        error: _snapshots[feature]!.error,
        latency: DateTime.now().difference(started),
      );
    } on Object catch (error, stackTrace) {
      if (error is ReadCancelled) return;
      final featureCurrent = _isFeatureLoadCurrent(
        feature,
        generation,
        lifecycleEpoch,
        ygdkGeneration,
      );
      final homeCurrent =
          query == null &&
          _isHomeDefaultCurrent(feature, generation, lifecycleEpoch);
      if (!featureCurrent && !homeCurrent) return;
      if (error is BackendException && error.accountMismatch) {
        await _rejectMismatchedAccount();
        return;
      }
      final uiError = _recordFailure(
        error,
        DiagnosticOperation.read,
        stackTrace: stackTrace,
        feature: feature,
        latency: DateTime.now().difference(started),
      );
      completed = true;
      outcome = uiError;
      if (homeCurrent)
        _acceptHomeDefault(
          feature,
          FeatureResult.failure(uiError),
          FeatureReadContext(requestRevision: generation),
        );
      if (featureCurrent)
        _snapshots[feature] = _snapshots[feature]!.copyWith(
          status: (hadPreviousData || _snapshots[feature]!.evidence != null)
              ? FeatureLoadStatus.stale
              : FeatureLoadStatus.failure,
          error: uiError,
        );
      if (featureCurrent && feature == FeatureId.grades) {
        _rememberGradeResult(FeatureResult.failure(uiError), query);
      }
      await _recordFeature(
        feature,
        error: uiError,
        latency: DateTime.now().difference(started),
      );
    } finally {
      if (completed && scope.valid && !writeReadback) {
        _finishBusinessAttempt(
          feature,
          query,
          generation,
          lifecycleEpoch,
          outcome,
        );
      }
      scope.cancel();
      _readScopes.remove(scope);
      if (!scope.completion.isCompleted) scope.completion.complete();
      _syncRecoveryRetries();
    }
    _notify();
  }

  bool _applyFeatureResultIfCurrent(
    FeatureId feature,
    FeatureResult result,
    int generation,
    int lifecycleEpoch, {
    int? ygdkGeneration,
    FeatureReadContext? readContext,
    bool preservePreviousOnFailure = false,
  }) {
    if (!_isFeatureLoadCurrent(
      feature,
      generation,
      lifecycleEpoch,
      ygdkGeneration,
    )) {
      return false;
    }
    // 已保存的只读内容不因读取失败消失；身份不符由独立边界清空。
    if (result.error != null &&
        result.evidence == null &&
        result.details.isEmpty &&
        result.overview == null &&
        ((_snapshots[feature]!.evidence != null) ||
            (preservePreviousOnFailure &&
                (result.error?.code == UbaaErrorCode.networkError ||
                    result.error?.code == UbaaErrorCode.timeout ||
                    result.error?.code ==
                        UbaaErrorCode.upstreamUnavailable)))) {
      _snapshots[feature] = _snapshots[feature]!.copyWith(
        status: FeatureLoadStatus.stale,
        error: _recordFailure(
          result.error!,
          DiagnosticOperation.read,
          feature: feature,
        ),
      );
      return true;
    }
    final status = result.error != null
        ? (result.evidence != null ||
                  result.details.isNotEmpty ||
                  result.overview != null
              ? FeatureLoadStatus.stale
              : FeatureLoadStatus.failure)
        : result.evidence?.complete == false
        ? FeatureLoadStatus.stale
        : result.isEmpty
        ? FeatureLoadStatus.empty
        : FeatureLoadStatus.success;
    _snapshots[feature] = _snapshots[feature]!.copyWith(
      status: status,
      readContext:
          readContext ??
          _snapshots[feature]!.readContext ??
          FeatureReadContext(requestRevision: generation),
      overview: result.overview,
      clearOverview: result.overview == null,
      summary: result.summary,
      details: result.details,
      error: result.error == null
          ? null
          : _recordFailure(
              result.error!,
              DiagnosticOperation.read,
              feature: feature,
            ),
      resolvedRoute: result.resolvedRoute,
      pagination: result.pagination,
      updatedAt: result.evidence?.fetchedAt ?? DateTime.now(),
      evidence: result.evidence,
      clearEvidence: result.evidence == null,
      clearError: result.error == null,
      clearSummary: result.summary == null,
      clearDetails: result.details.isEmpty,
      clearResolvedRoute: result.resolvedRoute == null,
      clearPagination: result.pagination == null,
    );
    return true;
  }

  bool _isFeatureLoadCurrent(
    FeatureId feature,
    int generation,
    int lifecycleEpoch,
    int? ygdkGeneration,
  ) =>
      !_disposed &&
      lifecycleEpoch == _lifecycleEpoch &&
      generation == _featureRefreshGenerations[feature] &&
      (feature != FeatureId.ygdk || ygdkGeneration == _ygdkGeneration);
}

part of '../app_controller.dart';

extension _AppControllerRefresh on AppController {
  Future<void> _refreshHome({Iterable<FeatureId>? only}) async {
    if (_disposed) return;
    _readCacheEpoch++;
    final lifecycleEpoch = _lifecycleEpoch;
    final features = (only ?? FeatureId.values).toList(growable: false);
    final generations = <FeatureId, int>{
      for (final feature in features) feature: _nextFeatureGeneration(feature),
    };
    final ygdkGeneration = features.contains(FeatureId.ygdk)
        ? ++_ygdkGeneration
        : null;
    for (final feature in features) {
      _beginFeatureRead(feature, generations[feature]!, null);
    }
    _notify();
    await Future.wait(
      features.map(
        (feature) => _loadFeature(
          feature,
          generations[feature]!,
          lifecycleEpoch,
          ygdkGeneration: feature == FeatureId.ygdk ? ygdkGeneration : null,
        ),
      ),
    );
  }

  /// 对支持 [FeatureQueryBackend] 的生产实现执行单领域筛选读取。
  ///
  /// 不支持查询的 fake backend 明确报 unsupported，不会在 Dart 端拼接请求。
  Future<void> _refreshFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    if (_disposed) return;
    final generation = _nextFeatureGeneration(feature);
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
    final next = (_featureRefreshGenerations[feature] ?? 0) + 1;
    _featureRefreshGenerations[feature] = next;
    return next;
  }

  Future<void> _loadFeature(
    FeatureId feature,
    int generation,
    int lifecycleEpoch, {
    FeatureQuery? query,
    int? ygdkGeneration,
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
    final started = DateTime.now();
    final previous = _snapshots[feature]!;
    final hadPreviousData =
        previous.updatedAt != null &&
        (previous.overview != null ||
            previous.details.isNotEmpty ||
            previous.summary?.trim().isNotEmpty == true);
    try {
      final result = switch ((_backend, query)) {
        (FeatureQueryBackend queryBackend, final FeatureQuery value) =>
          await queryBackend.loadFeatureQuery(feature, value),
        _ => await _backend.loadFeature(feature),
      };
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
      await _recordFeature(
        feature,
        success: result.error == null && !result.isEmpty,
        empty: result.isEmpty,
        error: _snapshots[feature]!.error,
        latency: DateTime.now().difference(started),
      );
    } on Object catch (error, stackTrace) {
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
      final uiError = _recordFailure(
        error,
        DiagnosticOperation.read,
        stackTrace: stackTrace,
        feature: feature,
        latency: DateTime.now().difference(started),
      );
      if (homeCurrent)
        _acceptHomeDefault(
          feature,
          FeatureResult.failure(uiError),
          FeatureReadContext(requestRevision: generation),
        );
      if (featureCurrent)
        _snapshots[feature] = _snapshots[feature]!.copyWith(
          status: hadPreviousData
              ? FeatureLoadStatus.stale
              : FeatureLoadStatus.failure,
          error: uiError,
          updatedAt: DateTime.now(),
        );
      await _recordFeature(
        feature,
        error: uiError,
        latency: DateTime.now().difference(started),
      );
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
    // 普通同查询的瞬时失败保留数据；鉴权/权限及专用回读保持失败清空。
    if (preservePreviousOnFailure &&
        (result.error?.code == UbaaErrorCode.networkError ||
            result.error?.code == UbaaErrorCode.timeout ||
            result.error?.code == UbaaErrorCode.upstreamUnavailable)) {
      _snapshots[feature] = _snapshots[feature]!.copyWith(
        status: FeatureLoadStatus.stale,
        error: _recordFailure(
          result.error!,
          DiagnosticOperation.read,
          feature: feature,
        ),
        updatedAt: DateTime.now(),
      );
      return true;
    }
    final status = result.error != null
        ? FeatureLoadStatus.failure
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
      updatedAt: DateTime.now(),
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

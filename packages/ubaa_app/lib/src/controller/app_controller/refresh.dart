part of '../app_controller.dart';

extension _AppControllerRefresh on AppController {
  Future<void> _refreshHome({Iterable<FeatureId>? only}) async {
    if (_disposed) return;
    final lifecycleEpoch = _lifecycleEpoch;
    final features = (only ?? FeatureId.values).toList(growable: false);
    final generations = <FeatureId, int>{
      for (final feature in features) feature: _nextFeatureGeneration(feature),
    };
    final ygdkGeneration = features.contains(FeatureId.ygdk)
        ? ++_ygdkGeneration
        : null;
    for (final feature in features) {
      _snapshots[feature] = _snapshots[feature]!.copyWith(
        status: FeatureLoadStatus.loading,
        clearError: true,
      );
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
    if (_backend is! FeatureQueryBackend) {
      _snapshots[feature] = _snapshots[feature]!.copyWith(
        status: FeatureLoadStatus.failure,
        error: UbaaErrorMapper.fromCode(UbaaErrorCode.unsupported),
      );
      _notify();
      return;
    }
    final lifecycleEpoch = _lifecycleEpoch;
    final generation = _nextFeatureGeneration(feature);
    final ygdkGeneration = feature == FeatureId.ygdk ? ++_ygdkGeneration : null;
    _snapshots[feature] = _snapshots[feature]!.copyWith(
      status: FeatureLoadStatus.loading,
      clearError: true,
    );
    _notify();
    await _loadFeature(
      feature,
      generation,
      lifecycleEpoch,
      query: query,
      ygdkGeneration: ygdkGeneration,
    );
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
    )) {
      return;
    }
    final started = DateTime.now();
    final previous = _snapshots[feature]!;
    final hadPreviousData =
        previous.updatedAt != null &&
        (previous.details.isNotEmpty ||
            previous.summary?.trim().isNotEmpty == true);
    try {
      final result = switch ((_backend, query)) {
        (FeatureQueryBackend queryBackend, final FeatureQuery value) =>
          await queryBackend.loadFeatureQuery(feature, value),
        _ => await _backend.loadFeature(feature),
      };
      if (!_applyFeatureResultIfCurrent(
        feature,
        result,
        generation,
        lifecycleEpoch,
        ygdkGeneration: ygdkGeneration,
      )) {
        return;
      }
      await _recordFeature(
        feature,
        success: result.error == null && !result.isEmpty,
        empty: result.isEmpty,
        error: result.error,
        latency: DateTime.now().difference(started),
      );
    } on BackendException catch (exception) {
      if (!_isFeatureLoadCurrent(
        feature,
        generation,
        lifecycleEpoch,
        ygdkGeneration,
      )) {
        return;
      }
      final uiError = UbaaErrorMapper.fromCode(exception.code);
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
    } catch (_) {
      if (!_isFeatureLoadCurrent(
        feature,
        generation,
        lifecycleEpoch,
        ygdkGeneration,
      )) {
        return;
      }
      _snapshots[feature] = _snapshots[feature]!.copyWith(
        status: hadPreviousData
            ? FeatureLoadStatus.stale
            : FeatureLoadStatus.failure,
        error: UbaaErrorMapper.fromCode(UbaaErrorCode.internalError),
        updatedAt: DateTime.now(),
      );
      await _recordFeature(
        feature,
        error: UbaaErrorMapper.fromCode(UbaaErrorCode.internalError),
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
  }) {
    if (!_isFeatureLoadCurrent(
      feature,
      generation,
      lifecycleEpoch,
      ygdkGeneration,
    )) {
      return false;
    }
    final status = result.error != null
        ? FeatureLoadStatus.failure
        : result.isEmpty
        ? FeatureLoadStatus.empty
        : FeatureLoadStatus.success;
    _snapshots[feature] = _snapshots[feature]!.copyWith(
      status: status,
      summary: result.summary,
      details: result.details,
      error: result.error,
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

part of '../../bridge_backend.dart';

bool _isEvaluationCacheQuery(FeatureId feature, FeatureQuery query) =>
    feature == FeatureId.evaluation &&
    {
      FeatureQueryView.summary,
      FeatureQueryView.evaluationPending,
    }.contains(query.view);

Future<CachedFeatureProjection?> _cachedEvaluationProjection(
  BridgeOfflineCache cache,
  LocalAccount account,
  FeatureQuery query,
  BridgeConnectionMode route,
) async {
  final value = await cache.readEvaluation(route: route);
  if (value == null) return null;
  final data = BridgeEvaluationCoursesResponse(
    courses: value.data.courses
        .map(
          (v) => BridgeEvaluationCourse(
            id: v.id,
            kcmc: v.kcmc,
            bpmc: v.bpmc,
            isEvaluated: v.isEvaluated,
            submitEligibility: BridgeActionEligibility.unknown,
            submitTarget: null,
          ),
        )
        .toList(),
    progress: value.data.progress,
  );
  final result = _mapEvaluationResult(
    data,
    _toConnectionMode(value.sourceRoute),
    pendingOnly: query.view == FeatureQueryView.evaluationPending,
  );
  return CachedFeatureProjection(
    feature: FeatureId.evaluation,
    query: query,
    accountId: account.id,
    route: _toConnectionMode(value.sourceRoute),
    fetchedAt: _cacheTime(value.fetchedAt.toInt()),
    complete: value.complete,
    details: result.details,
    overview: result.overview,
  );
}

Future<FeatureResult?> _loadCachedEvaluationFeature(
  BridgeBackend backend,
  FeatureQuery query,
) async {
  await _awaitOfflineScope(backend);
  final cache = backend._offlineCache, account = backend._offlineAccount;
  if (cache == null || account == null) return null;
  final value = await backend.client.evaluationCached(cache: cache);
  return _finishEvaluationRefresh(backend, cache, account, query, value);
}

Future<FeatureResult> _finishEvaluationRefresh(
  BridgeBackend backend,
  BridgeOfflineCache? cache,
  LocalAccount? account,
  FeatureQuery query,
  BridgeEvaluationRefresh value,
) async {
  final route = _toConnectionMode(value.route.resolvedRoute);
  var selected = _mapEvaluationResult(
    value.data,
    route,
    pendingOnly: query.view == FeatureQueryView.evaluationPending,
  );
  var origin = DataOrigin.online;
  var fetchedAt = _cacheTime(value.fetchedAt.toInt());
  if (!value.complete &&
      cache != null &&
      account != null &&
      (value.preservedPrevious || !value.savedForOffline)) {
    CachedFeatureProjection? old;
    try {
      old = await _cachedEvaluationProjection(
        cache,
        account,
        query,
        value.route.resolvedRoute,
      );
    } on BridgeError {
      /* 本地失败不抹去合法在线部分，控制器另有生命周期屏障。 */
    }
    if (old != null) {
      final ids = old.details
          .map(
            (row) =>
                (row.presentation as EvaluationCoursePresentation).courseId,
          )
          .toSet();
      final added = selected.details.where((row) {
        final id = (row.presentation as EvaluationCoursePresentation).courseId;
        return id.isNotEmpty && !ids.contains(id);
      }).toList();
      selected = FeatureResult.success(
        details: [...old.details, ...added],
        overview: old.overview,
        resolvedRoute: old.route,
      );
      origin = added.isEmpty ? DataOrigin.persisted : DataOrigin.mixed;
      fetchedAt = old.fetchedAt;
    }
  }
  if (cache != null &&
      account != null &&
      backend._offlineAccount?.id != account.id)
    throw const BackendException(UbaaErrorCode.operationConflict);
  final details = value.complete
      ? selected.details
      : selected.details
            .map(
              (row) => FeatureDetail(
                title: row.title,
                subtitle: row.subtitle,
                fields: row.fields,
                presentation: row.presentation,
                readNavigation: row.readNavigation,
              ),
            )
            .toList();
  return FeatureResult.success(
    summary: value.complete ? selected.summary : '评教任务尚未核对完整',
    details: details,
    overview: value.complete || account != null ? selected.overview : null,
    resolvedRoute: route,
    evidence: account == null
        ? null
        : DataEvidence(
            accountId: account.id,
            origin: origin,
            fetchedAt: fetchedAt,
            complete: value.complete,
            savedForOffline: value.savedForOffline,
          ),
  );
}

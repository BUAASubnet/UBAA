part of 'reader.dart';

Future<FeatureResult?> _loadCachedEvaluationFeature(
  BridgeContext backend,
  FeatureQuery query,
) async {
  await bridgeAwaitOfflineScope(backend);
  final cache = backend.cache.handle, account = backend.cache.account;
  if (cache == null || account == null) return null;
  final value = await backend.client.evaluationCached(cache: cache);
  return _finishEvaluationRefresh(backend, cache, account, query, value);
}

Future<FeatureResult> _finishEvaluationRefresh(
  BridgeContext backend,
  BridgeOfflineCache? cache,
  LocalAccount? account,
  FeatureQuery query,
  BridgeEvaluationRefresh value,
) async {
  final route = bridgeToConnectionMode(value.route.resolvedRoute);
  var selected = bridgeMapEvaluationResult(
    value.data,
    route,
    pendingOnly: query.view == FeatureQueryView.evaluationPending,
  );
  var origin = DataOrigin.online;
  var fetchedAt = bridgeCacheTime(value.fetchedAt.toInt());
  if (!value.complete &&
      cache != null &&
      account != null &&
      (value.preservedPrevious || !value.savedForOffline)) {
    CachedFeatureProjection? old;
    try {
      old = await bridgeCachedEvaluationProjection(
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
      backend.cache.account?.id != account.id)
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
    summary: selected.summary,
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

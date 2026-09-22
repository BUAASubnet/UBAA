part of '../../bridge_backend.dart';

Future<CachedFeatureProjection?> _cachedYgdkRecordsProjection(
  BridgeOfflineCache cache,
  LocalAccount account,
  FeatureQuery query,
  BridgeConnectionMode route, {
  int? classifyId,
}) async {
  if (classifyId == null) {
    final selection = await cache.readYgdkRecordsSelection(route: route);
    if (selection == null) return null;
    if (selection.sourceRoute != route)
      throw const BackendException(UbaaErrorCode.operationConflict);
    classifyId = selection.data.classifyId;
  }
  final page = query.page <= 0 ? 1 : query.page;
  final size = query.size.clamp(1, 100);
  final value = await cache.readYgdkRecords(
    route: route,
    classifyId: classifyId,
    page: page,
    size: size,
  );
  if (value == null) return null;
  if (value.sourceRoute != route ||
      value.classifyId != classifyId ||
      value.data.page != page ||
      value.data.size != size) {
    throw const BackendException(UbaaErrorCode.operationConflict);
  }
  final result = _mapYgdkRecordsResult(value.data, _toConnectionMode(route));
  return CachedFeatureProjection(
    feature: FeatureId.ygdk,
    accountId: account.id,
    route: _toConnectionMode(route),
    query: query,
    fetchedAt: _cacheTime(value.fetchedAt.toInt()),
    complete: value.complete,
    details: result.details,
    pagination: result.pagination,
  );
}

Future<FeatureResult?> _loadCachedYgdkRecords(
  BridgeBackend backend,
  FeatureQuery query, {
  BridgeConnectionMode? expectedRoute,
  int? expectedClassifyId,
}) async {
  await backend._offlineTail;
  final cache = backend._offlineCache, account = backend._offlineAccount;
  if (cache == null || account == null) return null;
  final page = query.page <= 0 ? 1 : query.page;
  final size = query.size.clamp(1, 100);
  final value = expectedRoute == null
      ? await backend.client.ygdkRecordsCached(
          cache: cache,
          page: page,
          size: size,
        )
      : await backend.client.ygdkRecordsForOverviewCached(
          cache: cache,
          route: expectedRoute,
          classifyId: expectedClassifyId!,
          page: page,
          size: size,
        );
  final source = value.route.resolvedRoute;
  final route = _toConnectionMode(source);
  if (value.data.page != page ||
      value.data.size != size ||
      value.selection.classifyId <= 0 ||
      (expectedRoute != null &&
          (source != expectedRoute ||
              value.selection.classifyId != expectedClassifyId))) {
    throw const BackendException(UbaaErrorCode.operationConflict);
  }
  var selected = _mapYgdkRecordsResult(value.data, route);
  var origin = DataOrigin.online;
  var fetchedAt = _cacheTime(value.fetchedAt.toInt());
  if (!value.complete && (value.preservedPrevious || !value.savedForOffline)) {
    CachedFeatureProjection? old;
    try {
      old = await _cachedYgdkRecordsProjection(
        cache,
        account,
        query,
        source,
        classifyId: value.selection.classifyId,
      );
    } on BridgeError {
      /* 本地读取失败不抹去合法线上部分。 */
    }
    if (old != null) {
      selected = FeatureResult.success(
        details: old.details,
        pagination: old.pagination,
        resolvedRoute: route,
      );
      origin = DataOrigin.persisted;
      fetchedAt = old.fetchedAt;
    }
  }
  if (backend._offlineAccount?.id != account.id)
    throw const BackendException(UbaaErrorCode.operationConflict);
  return FeatureResult.success(
    summary: value.complete ? selected.summary : '打卡记录尚未核对完整',
    details: selected.details,
    pagination: selected.pagination,
    resolvedRoute: route,
    evidence: DataEvidence(
      accountId: account.id,
      origin: origin,
      fetchedAt: fetchedAt,
      complete: value.complete,
      savedForOffline: value.savedForOffline,
    ),
  );
}

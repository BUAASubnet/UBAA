part of 'reader.dart';

Future<FeatureResult?> _loadCachedYgdkRecords(
  BridgeContext backend,
  FeatureQuery query, {
  BridgeConnectionMode? expectedRoute,
  int? expectedClassifyId,
}) async {
  await bridgeAwaitOfflineScope(backend);
  final cache = backend.cache.handle, account = backend.cache.account;
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
  final route = bridgeToConnectionMode(source);
  if (value.data.page != page ||
      value.data.size != size ||
      value.selection.classifyId <= 0 ||
      (expectedRoute != null &&
          (source != expectedRoute ||
              value.selection.classifyId != expectedClassifyId))) {
    throw const BackendException(UbaaErrorCode.operationConflict);
  }
  var selected = bridgeMapYgdkRecordsResult(value.data, route);
  var origin = DataOrigin.online;
  var fetchedAt = bridgeCacheTime(value.fetchedAt.toInt());
  if (!value.complete && (value.preservedPrevious || !value.savedForOffline)) {
    CachedFeatureProjection? old;
    try {
      old = await bridgeCachedYgdkRecordsProjection(
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
  if (backend.cache.account?.id != account.id)
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

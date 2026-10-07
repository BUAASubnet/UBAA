part of 'cache.dart';

Future<CachedFeatureProjection?> bridgeCachedYgdkRecordsProjection(
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
  final result = bridgeMapYgdkRecordsResult(
    value.data,
    bridgeToConnectionMode(route),
  );
  return CachedFeatureProjection(
    feature: FeatureId.ygdk,
    accountId: account.id,
    route: bridgeToConnectionMode(route),
    query: query,
    fetchedAt: bridgeCacheTime(value.fetchedAt.toInt()),
    complete: value.complete,
    details: result.details,
    pagination: result.pagination,
  );
}

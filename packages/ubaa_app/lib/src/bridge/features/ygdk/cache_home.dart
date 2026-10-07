part of 'cache.dart';

Future<YgdkHomeRecords?> bridgeLocalYgdkHomeRecords(
  BridgeOfflineCache cache,
  LocalAccount account,
  FeatureQuery query,
  BridgeConnectionMode route,
  int classifyId, {
  UbaaErrorCode? error,
}) async {
  CachedFeatureProjection? old;
  try {
    old = await bridgeCachedYgdkRecordsProjection(
      cache,
      account,
      query,
      route,
      classifyId: classifyId,
    );
  } on BridgeError catch (failure) {
    if (failure.kind == BridgeErrorKind.authentication) rethrow;
    return YgdkHomeRecords(
      page: query.page <= 0 ? 1 : query.page,
      size: query.size.clamp(1, 100),
      classifyId: classifyId,
      errorCode: error ?? bridgeTypedErrorCode(failure.code),
    );
  } on BackendException catch (failure) {
    return YgdkHomeRecords(
      page: query.page <= 0 ? 1 : query.page,
      size: query.size.clamp(1, 100),
      classifyId: classifyId,
      errorCode: error ?? failure.code,
    );
  }
  if (old == null) return null;
  return bridgeYgdkHomeRecords(
    FeatureResult.success(
      details: old.details,
      pagination: old.pagination,
      evidence: old.toSnapshot().evidence,
      resolvedRoute: old.route,
    ),
    classifyId,
    query.page <= 0 ? 1 : query.page,
    query.size.clamp(1, 100),
    error: error,
  );
}

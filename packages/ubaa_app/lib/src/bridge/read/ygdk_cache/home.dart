part of '../../bridge_backend.dart';

YgdkHomeRecords _ygdkHomeRecords(
  FeatureResult value,
  int classifyId,
  int page,
  int size, {
  UbaaErrorCode? error,
}) => YgdkHomeRecords(
  classifyId: classifyId,
  evidence: value.evidence,
  page: value.pagination?.page ?? page,
  size: value.pagination?.size ?? size,
  total: value.pagination?.total,
  hasMore: value.pagination?.hasMore,
  content: List.unmodifiable(
    value.details
        .map((v) => v.presentation)
        .whereType<YgdkRecordPresentation>(),
  ),
  errorCode: error,
);

Future<YgdkHomeRecords?> _localYgdkHomeRecords(
  BridgeOfflineCache cache,
  LocalAccount account,
  FeatureQuery query,
  BridgeConnectionMode route,
  int classifyId, {
  UbaaErrorCode? error,
}) async {
  CachedFeatureProjection? old;
  try {
    old = await _cachedYgdkRecordsProjection(
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
      errorCode: error ?? _typedErrorCode(failure.code),
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
  return _ygdkHomeRecords(
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

Future<YgdkHomeRecords> _readYgdkHomeRecords(
  BridgeBackend backend,
  _HomeYgdkRead home,
  FeatureQuery query,
) async {
  final page = query.page <= 0 ? 1 : query.page;
  final size = query.size.clamp(1, 100);
  final classifyId = home.data.classifyId;
  if (home.account != null && backend._offlineAccount?.id != home.account!.id) {
    throw const BackendException(UbaaErrorCode.operationConflict);
  }
  UbaaErrorCode? failure;
  try {
    final cached = await _loadCachedYgdkRecords(
      backend,
      query,
      expectedRoute: home.route,
      expectedClassifyId: classifyId,
    );
    if (cached != null) return _ygdkHomeRecords(cached, classifyId, page, size);
    final response = await backend.client.ygdkRecordsOnRoute(
      route: home.route,
      page: page,
      size: size,
    );
    if (response.pinnedRoute != home.route)
      throw const BackendException(UbaaErrorCode.operationConflict);
    return _ygdkHomeRecords(
      _mapYgdkRecordsResult(response.data, _toConnectionMode(home.route)),
      classifyId,
      page,
      size,
    );
  } on BridgeError catch (error) {
    if (error.kind == BridgeErrorKind.authentication) rethrow;
    failure = _typedErrorCode(error.code);
  } on BackendException catch (error) {
    failure = error.code;
  }
  final cache = home.cache, account = home.account;
  if (cache != null && account != null) {
    try {
      final old = await _localYgdkHomeRecords(
        cache,
        account,
        query,
        home.route,
        classifyId,
        error: failure,
      );
      if (backend._offlineAccount?.id != account.id)
        throw const BackendException(UbaaErrorCode.operationConflict);
      if (old != null) return old;
    } on BridgeError {
      /* 页面保留原错误，不替换为缓存读取错误。 */
    }
  }
  return YgdkHomeRecords(
    classifyId: classifyId,
    page: page,
    size: size,
    errorCode: failure,
  );
}

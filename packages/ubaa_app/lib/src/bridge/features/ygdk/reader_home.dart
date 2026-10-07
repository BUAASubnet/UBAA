part of 'reader.dart';

Future<YgdkHomeRecords> _readYgdkHomeRecords(
  BridgeContext backend,
  HomeYgdkRead home,
  FeatureQuery query,
) async {
  final page = query.page <= 0 ? 1 : query.page;
  final size = query.size.clamp(1, 100);
  final classifyId = home.data.classifyId;
  if (home.account != null && backend.cache.account?.id != home.account!.id) {
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
    if (cached != null)
      return bridgeYgdkHomeRecords(cached, classifyId, page, size);
    final response = await backend.client.ygdkRecordsOnRoute(
      route: home.route,
      page: page,
      size: size,
    );
    if (response.pinnedRoute != home.route)
      throw const BackendException(UbaaErrorCode.operationConflict);
    return bridgeYgdkHomeRecords(
      bridgeMapYgdkRecordsResult(
        response.data,
        bridgeToConnectionMode(home.route),
      ),
      classifyId,
      page,
      size,
    );
  } on BridgeError catch (error) {
    if (error.kind == BridgeErrorKind.authentication) rethrow;
    failure = bridgeTypedErrorCode(error.code);
  } on BackendException catch (error) {
    failure = error.code;
  }
  final cache = home.cache, account = home.account;
  if (cache != null && account != null) {
    try {
      final old = await bridgeLocalYgdkHomeRecords(
        cache,
        account,
        query,
        home.route,
        classifyId,
        error: failure,
      );
      if (backend.cache.account?.id != account.id)
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

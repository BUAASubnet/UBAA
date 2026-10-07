part of 'reader.dart';

Future<FeatureResult?> _loadCachedCgyyFeature(
  BridgeContext backend,
  FeatureQuery query,
  String today,
) async {
  await bridgeAwaitOfflineScope(backend);
  final cache = backend.cache.handle, account = backend.cache.account;
  if (cache == null || account == null) return null;
  switch (query.view) {
    case FeatureQueryView.summary:
      final value = await backend.client.cgyySitesCached(cache: cache);
      final route = bridgeToConnectionMode(value.route.resolvedRoute);
      return _finishCgyyRefresh(
        backend,
        cache,
        account,
        query,
        today,
        bridgeProjectCgyySites(value.data, route, today),
        value.state,
      );
    case FeatureQueryView.cgyyPurposeTypes:
      final value = await backend.client.cgyyPurposesCached(cache: cache);
      final route = bridgeToConnectionMode(value.route.resolvedRoute);
      return _finishCgyyRefresh(
        backend,
        cache,
        account,
        query,
        today,
        bridgeProjectCgyyPurposes(value.data, route),
        value.state,
      );
    case FeatureQueryView.cgyyDayInfo:
      final value = await backend.client.cgyyDayCached(
        cache: cache,
        siteId: bridgeRequiredPositiveInt(query.siteId, '站点 ID'),
        date: today,
      );
      final route = bridgeToConnectionMode(value.route.resolvedRoute);
      return _finishCgyyRefresh(
        backend,
        cache,
        account,
        query,
        today,
        value.data.venueSiteId == query.siteId &&
                value.data.reservationDate == today
            ? bridgeMapCgyyDayInfo(value.data, route)
            : FeatureResult.success(resolvedRoute: route),
        value.state,
      );
    case FeatureQueryView.cgyyOrders:
      final value = await backend.client.cgyyOrdersCached(
        cache: cache,
        page: query.page < 0 ? 0 : query.page,
        size: query.size.clamp(1, 100),
      );
      final route = bridgeToConnectionMode(value.route.resolvedRoute);
      return _finishCgyyRefresh(
        backend,
        cache,
        account,
        query,
        today,
        value.data.number == (query.page < 0 ? 0 : query.page) &&
                value.data.size == query.size.clamp(1, 100)
            ? bridgeMapCgyyOrdersResult(value.data, route)
            : FeatureResult.success(resolvedRoute: route),
        value.state,
      );
    case FeatureQueryView.cgyyOrderDetail:
      final value = await backend.client.cgyyDetailCached(
        cache: cache,
        orderId: bridgeRequiredPositiveInt(query.orderId, '订单 ID'),
      );
      final route = bridgeToConnectionMode(value.route.resolvedRoute);
      return _finishCgyyRefresh(
        backend,
        cache,
        account,
        query,
        today,
        value.data.id == query.orderId
            ? bridgeMapCgyyOrderDetailResult(value.data, route)
            : FeatureResult.success(resolvedRoute: route),
        value.state,
      );
    default:
      return null;
  }
}

Future<FeatureResult> _finishCgyyRefresh(
  BridgeContext backend,
  BridgeOfflineCache cache,
  LocalAccount account,
  FeatureQuery query,
  String today,
  FeatureResult online,
  BridgeCgyyRefreshState state,
) async {
  var selected = online;
  var origin = DataOrigin.online;
  var fetchedAt = bridgeCacheTime(state.fetchedAt.toInt());
  if (!state.complete &&
      (state.preservedPrevious || !state.savedForOffline) &&
      online.resolvedRoute != null) {
    CachedFeatureProjection? old;
    try {
      old = await bridgeCachedCgyyProjection(
        cache,
        account,
        query,
        bridgeToBridgeConnectionMode(online.resolvedRoute!),
        today,
      );
    } on BridgeError {
      /* 本地失败不抹去合法在线部分；控制器另有生命周期屏障。 */
    } on BackendException {
      /* 本地投影归属异常同样不生成写资格。 */
    }
    if (old != null) {
      selected = FeatureResult.success(
        details: old.details,
        overview: old.overview,
        pagination: old.pagination,
        resolvedRoute: old.route,
      );
      origin = DataOrigin.persisted;
      fetchedAt = old.fetchedAt;
    }
  }
  if (backend.cache.account?.id != account.id)
    throw const BackendException(UbaaErrorCode.operationConflict);
  final details = state.complete
      ? selected.details
      : CachedFeatureProjection(
          feature: FeatureId.cgyy,
          accountId: account.id,
          route: selected.resolvedRoute!,
          fetchedAt: fetchedAt,
          complete: false,
          details: selected.details,
        ).details;
  final evidence = DataEvidence(
    accountId: account.id,
    origin: origin,
    fetchedAt: fetchedAt,
    complete: state.complete,
    savedForOffline: state.savedForOffline,
    scopeDate: query.view == FeatureQueryView.cgyyDayInfo ? today : null,
  );
  return selected.isEmpty && state.complete
      ? FeatureResult.empty(
          resolvedRoute: selected.resolvedRoute,
          pagination: selected.pagination,
          overview: selected.overview,
          evidence: evidence,
        )
      : FeatureResult.success(
          summary: state.complete ? selected.summary : '查询范围尚未更新完整',
          details: details,
          overview: selected.overview,
          pagination: selected.pagination,
          resolvedRoute: selected.resolvedRoute,
          evidence: evidence,
        );
}

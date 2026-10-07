part of 'reader.dart';

Future<FeatureResult?> _loadCachedLibbookFeature(
  BridgeContext backend,
  FeatureQuery query,
  String today,
) async {
  await bridgeAwaitOfflineScope(backend);
  final cache = backend.cache.handle, account = backend.cache.account;
  if (cache == null || account == null) return null;
  switch (query.view) {
    case FeatureQueryView.summary:
      final value = await backend.client.libbookLibrariesCached(
        cache: cache,
        day: today,
      );
      final route = bridgeToConnectionMode(value.route.resolvedRoute);
      return _finishLibbookRefresh(
        backend,
        cache,
        account,
        query,
        today,
        bridgeProjectLibbookLibraries(
          value.data,
          route,
          today,
          query,
          persisted: !value.state.complete,
        ),
        value.state,
      );
    case FeatureQueryView.libbookAreas:
      final value = await backend.client.libbookAreasCached(
        cache: cache,
        premisesId: bridgeRequiredQueryValue(query.premisesId, '馆区 ID'),
        storeyId: query.storeyId,
        day: today,
      );
      final route = bridgeToConnectionMode(value.route.resolvedRoute);
      return _finishLibbookRefresh(
        backend,
        cache,
        account,
        query,
        today,
        bridgeProjectLibbookAreas(
          value.data,
          route,
          today,
          query,
          persisted: !value.state.complete,
        ),
        value.state,
      );
    case FeatureQueryView.libbookAreaDetail:
      final value = await backend.client.libbookAreaDetailCached(
        cache: cache,
        areaId: bridgeRequiredQueryValue(query.areaId, '分区 ID'),
      );
      final route = bridgeToConnectionMode(value.route.resolvedRoute);
      return _finishLibbookRefresh(
        backend,
        cache,
        account,
        query,
        today,
        value.data.id == query.areaId
            ? (value.schedule != null
                  ? bridgeProjectLibbookSchedule(value.schedule!, route)
                  : bridgeProjectLibbookAreaDetail(
                      value.data,
                      route,
                      today,
                      query,
                      persisted: !value.state.complete,
                    ))
            : FeatureResult.success(resolvedRoute: route),
        value.state,
      );
    case FeatureQueryView.libbookSeats:
      bridgeRequiredQueryValue(query.segment, '时段');
      final value = await backend.client.libbookSeatsCached(
        cache: cache,
        areaId: bridgeRequiredQueryValue(query.areaId, '分区 ID'),
        day: today,
        startTime: bridgeRequiredQueryValue(query.startTime, '开始时间'),
        endTime: bridgeRequiredQueryValue(query.endTime, '结束时间'),
      );
      final route = bridgeToConnectionMode(value.route.resolvedRoute);
      return _finishLibbookRefresh(
        backend,
        cache,
        account,
        query,
        today,
        bridgeProjectLibbookSeats(
          value.data,
          route,
          today,
          query,
          persisted: !value.state.complete,
        ),
        value.state,
      );
    case FeatureQueryView.libbookBookings:
      final value = await backend.client.libbookBookingsCached(
        cache: cache,
        page: query.page <= 0 ? 1 : query.page,
        limit: query.size.clamp(1, 100),
      );
      final route = bridgeToConnectionMode(value.route.resolvedRoute);
      return _finishLibbookRefresh(
        backend,
        cache,
        account,
        query,
        today,
        value.data.page == (query.page <= 0 ? 1 : query.page) &&
                value.data.limit == query.size.clamp(1, 100)
            ? bridgeProjectLibbookBookings(
                value.data,
                route,
                today,
                query,
                persisted: !value.state.complete,
              )
            : FeatureResult.success(resolvedRoute: route),
        value.state,
      );
    default:
      return null;
  }
}

Future<FeatureResult> _finishLibbookRefresh(
  BridgeContext backend,
  BridgeOfflineCache cache,
  LocalAccount account,
  FeatureQuery query,
  String today,
  FeatureResult online,
  BridgeLibBookRefreshState state,
) async {
  var selected = online;
  var origin = DataOrigin.online;
  var fetchedAt = bridgeCacheTime(state.fetchedAt.toInt());
  if (!state.complete &&
      (state.preservedPrevious || !state.savedForOffline) &&
      online.resolvedRoute != null) {
    CachedFeatureProjection? old;
    try {
      old = await bridgeCachedLibbookProjection(
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
          feature: FeatureId.libbook,
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
    scopeDate: bridgeLibbookDated(query) ? today : null,
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

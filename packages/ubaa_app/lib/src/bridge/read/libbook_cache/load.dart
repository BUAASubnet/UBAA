part of '../../bridge_backend.dart';

Future<FeatureResult?> _loadCachedLibbookFeature(
  BridgeBackend backend,
  FeatureQuery query,
  String today,
) async {
  await _awaitOfflineScope(backend);
  final cache = backend._offlineCache, account = backend._offlineAccount;
  if (cache == null || account == null) return null;
  switch (query.view) {
    case FeatureQueryView.summary:
      final value = await backend.client.libbookLibrariesCached(
        cache: cache,
        day: today,
      );
      final route = _toConnectionMode(value.route.resolvedRoute);
      return _finishLibbookRefresh(
        backend,
        cache,
        account,
        query,
        today,
        _projectLibbookLibraries(
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
        premisesId: _requiredQueryValue(query.premisesId, '馆区 ID'),
        storeyId: query.storeyId,
        day: today,
      );
      final route = _toConnectionMode(value.route.resolvedRoute);
      return _finishLibbookRefresh(
        backend,
        cache,
        account,
        query,
        today,
        _projectLibbookAreas(
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
        areaId: _requiredQueryValue(query.areaId, '分区 ID'),
      );
      final route = _toConnectionMode(value.route.resolvedRoute);
      return _finishLibbookRefresh(
        backend,
        cache,
        account,
        query,
        today,
        value.data.id == query.areaId
            ? (value.schedule != null
                  ? _projectLibbookSchedule(value.schedule!, route)
                  : _projectLibbookAreaDetail(
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
      _requiredQueryValue(query.segment, '时段');
      final value = await backend.client.libbookSeatsCached(
        cache: cache,
        areaId: _requiredQueryValue(query.areaId, '分区 ID'),
        day: today,
        startTime: _requiredQueryValue(query.startTime, '开始时间'),
        endTime: _requiredQueryValue(query.endTime, '结束时间'),
      );
      final route = _toConnectionMode(value.route.resolvedRoute);
      return _finishLibbookRefresh(
        backend,
        cache,
        account,
        query,
        today,
        _projectLibbookSeats(
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
      final route = _toConnectionMode(value.route.resolvedRoute);
      return _finishLibbookRefresh(
        backend,
        cache,
        account,
        query,
        today,
        value.data.page == (query.page <= 0 ? 1 : query.page) &&
                value.data.limit == query.size.clamp(1, 100)
            ? _projectLibbookBookings(
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
  BridgeBackend backend,
  BridgeOfflineCache cache,
  LocalAccount account,
  FeatureQuery query,
  String today,
  FeatureResult online,
  BridgeLibBookRefreshState state,
) async {
  var selected = online;
  var origin = DataOrigin.online;
  var fetchedAt = _cacheTime(state.fetchedAt.toInt());
  if (!state.complete &&
      (state.preservedPrevious || !state.savedForOffline) &&
      online.resolvedRoute != null) {
    CachedFeatureProjection? old;
    try {
      old = await _cachedLibbookProjection(
        cache,
        account,
        query,
        _toBridgeConnectionMode(online.resolvedRoute!),
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
  if (backend._offlineAccount?.id != account.id)
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
    scopeDate: _libbookDated(query) ? today : null,
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

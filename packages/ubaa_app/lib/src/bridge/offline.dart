part of 'bridge_backend.dart';

Future<void> _offlineSerial(
  BridgeBackend backend,
  Future<void> Function() action,
) {
  final next = backend._offlineTail.then((_) => action());
  backend._offlineTail = next.then<void>((_) {}, onError: (Object _) {});
  return next;
}

Future<void> _openOfflineAccount(
  BridgeBackend backend,
  LocalAccount account,
  List<int> key,
) => _offlineSerial(backend, () async {
  final directory = backend.configDirectory;
  if (directory == null)
    throw const BackendException(UbaaErrorCode.unsupported);
  try {
    if (backend._offlineAccount?.id != account.id) {
      await backend._offlineCache?.deactivate();
      backend._offlineCache = null;
      backend._offlineAccount = null;
    }
    final cache = await BridgeOfflineCache.open(
      configDir: directory,
      accountId: account.id,
      expectedIdentity: account.username,
      key: key,
    );
    await cache.activate();
    backend._offlineCache = cache;
    backend._offlineAccount = account;
  } on BridgeError catch (error) {
    throw _mapError(error);
  }
});

Future<List<CachedFeatureProjection>> _readCachedHome(
  BridgeBackend backend,
  RoutePolicy policy,
) async {
  await backend._offlineTail;
  final cache = backend._offlineCache;
  final account = backend._offlineAccount;
  if (cache == null || account == null) return const [];
  final routes = switch (policy) {
    RoutePolicy.direct => [BridgeConnectionMode.direct],
    RoutePolicy.webvpn => [BridgeConnectionMode.webVpn],
    RoutePolicy.auto => [
      BridgeConnectionMode.direct,
      BridgeConnectionMode.webVpn,
    ],
  };
  BridgeCachedToday? newest;
  try {
    for (final route in routes) {
      final record = await cache.readToday(route: route);
      if (record != null &&
          (newest == null ||
              record.fetchedAt.toInt() > newest.fetchedAt.toInt()))
        newest = record;
    }
  } on BridgeError catch (error) {
    throw _mapError(error);
  }
  if (newest == null) return const [];
  return [
    CachedFeatureProjection(
      feature: FeatureId.schedule,
      accountId: account.id,
      route: _toConnectionMode(newest.sourceRoute),
      fetchedAt: _cacheTime(newest.fetchedAt.toInt()),
      complete: newest.complete,
      scopeDate: newest.date,
      details: newest.data.map(_todayDetail),
    ),
  ];
}

DateTime _cacheTime(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

FeatureDetail _todayDetail(BridgeTodayClass item) => FeatureDetail(
  title: item.bizName,
  subtitle: item.shortName,
  presentation: TodayCoursePresentation(time: item.time, place: item.place),
  fields: _compactFields(<FeatureField?>[
    _field('时间', item.time),
    _field('地点', item.place),
  ]),
);

Future<FeatureResult> _loadTodayWithCache(BridgeBackend backend) async {
  await backend._offlineTail;
  final cache = backend._offlineCache;
  final account = backend._offlineAccount;
  final BridgeRoutedTodayClasses result;
  DataEvidence? evidence;
  if (cache != null && account != null) {
    final refreshed = await backend.client.scheduleTodayCached(cache: cache);
    result = refreshed.result;
    evidence = DataEvidence(
      accountId: account.id,
      origin: DataOrigin.online,
      fetchedAt: _cacheTime(refreshed.fetchedAt.toInt()),
      complete: true,
      savedForOffline: refreshed.saveError == null,
      scopeDate: refreshed.date,
    );
  } else {
    result = await backend.client.scheduleToday();
  }
  final route = _toConnectionMode(result.route.resolvedRoute);
  return result.data.isEmpty
      ? FeatureResult.empty(resolvedRoute: route, evidence: evidence)
      : FeatureResult.success(
          summary: '${result.data.length}今日课程',
          details: result.data.map(_todayDetail).toList(growable: false),
          resolvedRoute: route,
          evidence: evidence,
        );
}

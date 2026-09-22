part of '../bridge_backend.dart';

bool _isHomeCacheQuery(FeatureId feature, FeatureQuery query) =>
    switch (feature) {
      FeatureId.signin => {
        FeatureQueryView.summary,
        FeatureQueryView.signinPending,
        FeatureQueryView.signinCompleted,
      }.contains(query.view),
      FeatureId.spoc => {
        FeatureQueryView.summary,
        FeatureQueryView.spocDetail,
      }.contains(query.view),
      FeatureId.ygdk => query.view == FeatureQueryView.summary,
      _ => false,
    };
String _signinCacheDate(String value) {
  if (!RegExp(r'^\d{8}$').hasMatch(value))
    throw const BackendException(UbaaErrorCode.internalError);
  return '${value.substring(0, 4)}-${value.substring(4, 6)}-${value.substring(6)}';
}

Future<CachedFeatureProjection?> _cachedHomeProjection(
  BridgeOfflineCache cache,
  LocalAccount account,
  FeatureId feature,
  FeatureQuery query,
  BridgeConnectionMode route,
) async {
  FeatureResult result;
  int fetchedAt;
  bool complete;
  BridgeConnectionMode source;
  String? date;
  switch (feature) {
    case FeatureId.signin:
      final value = await cache.readHomeSignin(route: route);
      if (value == null) return null;
      result = _mapSigninHome(
        value.data
            .map(
              (item) => BridgeSigninClass(
                courseId: item.courseId,
                courseName: item.courseName,
                classBeginTime: item.classBeginTime,
                classEndTime: item.classEndTime,
                signStatus: item.signStatus,
                signinEligibility: BridgeActionEligibility.unknown,
              ),
            )
            .toList(),
        query,
        _toConnectionMode(value.sourceRoute),
        persisted: true,
      );
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;
      source = value.sourceRoute;
      date = _signinCacheDate(value.date);
    case FeatureId.spoc:
      if (query.view == FeatureQueryView.spocDetail) {
        final id = _requiredQueryValue(query.assignmentId, '作业编号');
        final value = await cache.readHomeSpocDetail(
          route: route,
          assignmentId: id,
        );
        if (value == null) return null;
        if (value.data.assignmentId != id)
          throw const BackendException(UbaaErrorCode.internalError);
        result = _mapSpocHomeDetail(
          value.data,
          _toConnectionMode(value.sourceRoute),
        );
        fetchedAt = value.fetchedAt.toInt();
        complete = value.complete;
        source = value.sourceRoute;
      } else {
        final value = await cache.readHomeSpoc(route: route);
        if (value == null) return null;
        result = _mapSpocHome(value.data, _toConnectionMode(value.sourceRoute));
        fetchedAt = value.fetchedAt.toInt();
        complete = value.complete;
        source = value.sourceRoute;
      }
    case FeatureId.ygdk:
      final value = await cache.readHomeYgdk(route: route);
      if (value == null) return null;
      final data = value.data;
      result = _mapYgdkOverviewResult(
        BridgeYgdkOverview(
          summary: data.summary,
          classifyId: data.classifyId,
          classifyName: data.classifyName,
          defaultItemId: data.defaultItemId,
          defaultItemName: data.defaultItemName,
          items: data.items
              .map(
                (item) => BridgeYgdkItem(
                  itemId: item.itemId,
                  name: item.name,
                  kind: item.kind,
                  sort: item.sort,
                  submitEligibility: BridgeActionEligibility.unknown,
                ),
              )
              .toList(),
        ),
        _toConnectionMode(value.sourceRoute),
        records: await _localYgdkHomeRecords(
          cache,
          account,
          query,
          value.sourceRoute,
          data.classifyId,
        ),
      );
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;
      source = value.sourceRoute;
    default:
      return null;
  }
  return CachedFeatureProjection(
    feature: feature,
    query: query,
    accountId: account.id,
    route: _toConnectionMode(source),
    fetchedAt: _cacheTime(fetchedAt),
    complete: complete,
    scopeDate: date,
    details: result.details,
    overview: result.overview,
  );
}

Future<FeatureResult> _loadSigninHome(
  BridgeBackend backend,
  FeatureQuery query, {
  bool useCache = true,
}) async {
  try {
    if (useCache) await _awaitOfflineScope(backend);
    final cache = useCache ? backend._offlineCache : null;
    final account = useCache ? backend._offlineAccount : null;
    if (cache != null && account != null) {
      final value = await backend.client.homeSigninCached(cache: cache);
      return _finishHomeRefresh(
        backend,
        cache,
        account,
        FeatureId.signin,
        query,
        _mapSigninHome(
          value.result.data,
          query,
          _toConnectionMode(value.result.route.resolvedRoute),
        ),
        value.state,
      );
    }
    final value = await backend.client.signinToday();
    return _mapSigninHome(
      value.data,
      query,
      _toConnectionMode(value.route.resolvedRoute),
    );
  } on BridgeError catch (error) {
    throw _mapError(error);
  }
}

Future<FeatureResult> _loadSpocHome(
  BridgeBackend backend,
  FeatureQuery query,
) async {
  if (!_isHomeCacheQuery(FeatureId.spoc, query))
    throw const BackendException(UbaaErrorCode.invalidInput);
  await _awaitOfflineScope(backend);
  final cache = backend._offlineCache, account = backend._offlineAccount;
  if (query.view == FeatureQueryView.spocDetail) {
    final id = _requiredQueryValue(query.assignmentId, '作业编号');
    if (cache != null && account != null) {
      final value = await backend.client.homeSpocDetailCached(
        cache: cache,
        assignmentId: id,
      );
      return _finishHomeRefresh(
        backend,
        cache,
        account,
        FeatureId.spoc,
        query,
        _mapSpocHomeDetail(
          value.result.data,
          _toConnectionMode(value.result.route.resolvedRoute),
        ),
        value.state,
      );
    }
    final value = await backend.client.spocAssignment(assignmentId: id);
    return _mapSpocHomeDetail(
      value.data,
      _toConnectionMode(value.route.resolvedRoute),
    );
  }
  if (cache != null && account != null) {
    final value = await backend.client.homeSpocCached(cache: cache);
    return _finishHomeRefresh(
      backend,
      cache,
      account,
      FeatureId.spoc,
      query,
      _mapSpocHome(
        value.result.data,
        _toConnectionMode(value.result.route.resolvedRoute),
      ),
      value.state,
    );
  }
  final value = await backend.client.spocAssignments();
  return _mapSpocHome(value.data, _toConnectionMode(value.route.resolvedRoute));
}

final class _HomeYgdkRead {
  const _HomeYgdkRead(
    this.data,
    this.route, {
    this.state,
    this.cache,
    this.account,
  });
  final BridgeYgdkOverview data;
  final BridgeConnectionMode route;
  final BridgeHomeRefreshState? state;
  final BridgeOfflineCache? cache;
  final LocalAccount? account;
}

Future<_HomeYgdkRead> _readYgdkHome(BridgeBackend backend) async {
  await _awaitOfflineScope(backend);
  final cache = backend._offlineCache, account = backend._offlineAccount;
  if (cache != null && account != null) {
    final value = await backend.client.homeYgdkCached(cache: cache);
    return _HomeYgdkRead(
      value.result.data,
      value.result.route.resolvedRoute,
      state: value.state,
      cache: cache,
      account: account,
    );
  }
  final value = await backend.client.ygdkOverview();
  return _HomeYgdkRead(value.data, value.route.resolvedRoute);
}

Future<FeatureResult> _finishHomeRefresh(
  BridgeBackend backend,
  BridgeOfflineCache? cache,
  LocalAccount? account,
  FeatureId feature,
  FeatureQuery query,
  FeatureResult online,
  BridgeHomeRefreshState? state,
) async {
  if (state == null || cache == null || account == null) return online;
  if (backend._offlineAccount?.id != account.id)
    throw const BackendException(UbaaErrorCode.operationConflict);
  var details = online.details;
  var overview = online.overview;
  var origin = DataOrigin.online;
  var fetched = _cacheTime(state.fetchedAt.toInt());
  if (!state.complete &&
      state.preservedPrevious &&
      online.resolvedRoute != null) {
    CachedFeatureProjection? old;
    try {
      old = await _cachedHomeProjection(
        cache,
        account,
        feature,
        query,
        _toBridgeConnectionMode(online.resolvedRoute!),
      );
    } on BridgeError {
      /* 本地损坏不能抹掉刚取得的合法在线部分。 */
    }
    if (old != null) {
      if (feature == FeatureId.ygdk &&
          old.complete &&
          old.overview is YgdkOverview &&
          online.overview is YgdkOverview &&
          (old.overview as YgdkOverview).classifyId ==
              (online.overview as YgdkOverview).classifyId &&
          (old.overview as YgdkOverview).termId ==
              (online.overview as YgdkOverview).termId) {
        // 只保留同分类且已观察学期一致的旧统计；动作与当前项目集合始终来自本次在线读取。
        final saved = old.overview as YgdkOverview;
        overview = YgdkOverview(
          termCount: saved.termCount,
          classifyId: saved.classifyId,
          classifyName: saved.classifyName,
          defaultItemId: saved.defaultItemId,
          defaultItemName: saved.defaultItemName,
          termId: saved.termId,
          termName: saved.termName,
          termTarget: saved.termTarget,
          weekCount: saved.weekCount,
          weekTarget: saved.weekTarget,
          monthCount: saved.monthCount,
          monthTarget: saved.monthTarget,
          dayCount: saved.dayCount,
          goodCount: saved.goodCount,
          records: (online.overview as YgdkOverview).records,
        );
        origin = DataOrigin.mixed;
        fetched = old.fetchedAt;
      } else if (feature == FeatureId.spoc) {
        details = old.details;
        overview = old.overview;
        origin = DataOrigin.persisted;
        fetched = old.fetchedAt;
        if (query.view == FeatureQueryView.summary &&
            old.overview is SpocTermOverview &&
            online.overview is SpocTermOverview &&
            (old.overview as SpocTermOverview).termCode ==
                (online.overview as SpocTermOverview).termCode) {
          final ids = old.details
              .map(
                (item) => (item.presentation as SpocAssignmentPresentation)
                    .assignmentId,
              )
              .toSet();
          final added = online.details
              .where(
                (item) => !ids.contains(
                  (item.presentation as SpocAssignmentPresentation)
                      .assignmentId,
                ),
              )
              .toList();
          if (added.isNotEmpty) {
            details = [...details, ...added];
            origin = DataOrigin.mixed;
          }
        }
      }
    }
  }
  final complete =
      state.complete &&
      !(online.overview is YgdkOverview &&
          (online.overview as YgdkOverview).records?.errorCode != null);
  final evidence = DataEvidence(
    accountId: account.id,
    origin: origin,
    fetchedAt: fetched,
    complete: complete,
    savedForOffline: state.savedForOffline,
    scopeDate: state.scopeDate == null
        ? null
        : _signinCacheDate(state.scopeDate!),
  );
  return online.isEmpty && complete
      ? FeatureResult.empty(
          overview: overview,
          resolvedRoute: online.resolvedRoute,
          evidence: evidence,
        )
      : FeatureResult.success(
          summary: complete ? online.summary : '部分内容尚未更新完成',
          details: details,
          overview: overview,
          resolvedRoute: online.resolvedRoute,
          evidence: evidence,
        );
}

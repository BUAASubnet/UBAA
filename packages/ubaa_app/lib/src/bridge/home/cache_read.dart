part of 'reader.dart';

Future<HomeYgdkRead> bridgeReadYgdkHome(BridgeContext backend) async {
  await bridgeAwaitOfflineScope(backend);
  final cache = backend.cache.handle, account = backend.cache.account;
  if (cache != null && account != null) {
    final value = await backend.client.homeYgdkCached(cache: cache);
    return HomeYgdkRead(
      value.result.data,
      value.result.route.resolvedRoute,
      state: value.state,
      cache: cache,
      account: account,
    );
  }
  final value = await backend.client.ygdkOverview();
  return HomeYgdkRead(value.data, value.route.resolvedRoute);
}

Future<FeatureResult> bridgeFinishHomeRefresh(
  BridgeContext backend,
  BridgeOfflineCache? cache,
  LocalAccount? account,
  FeatureId feature,
  FeatureQuery query,
  FeatureResult online,
  BridgeHomeRefreshState? state,
) async {
  if (state == null || cache == null || account == null) return online;
  if (backend.cache.account?.id != account.id)
    throw const BackendException(UbaaErrorCode.operationConflict);
  var details = online.details;
  var overview = online.overview;
  var origin = DataOrigin.online;
  var fetched = bridgeCacheTime(state.fetchedAt.toInt());
  if (!state.complete &&
      state.preservedPrevious &&
      online.resolvedRoute != null) {
    CachedFeatureProjection? old;
    try {
      old = await bridgeCachedHomeProjection(
        cache,
        account,
        feature,
        query,
        bridgeToBridgeConnectionMode(online.resolvedRoute!),
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
        : bridgeSigninCacheDate(state.scopeDate!),
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

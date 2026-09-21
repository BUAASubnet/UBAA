part of '../bridge_backend.dart';

Future<FeatureResult> _loadBykcFeature(
  BridgeBackend backend,
  FeatureId feature,
  FeatureQuery query, {
  bool useCache = true,
}) async {
  if (feature != FeatureId.bykc)
    throw const BackendException(UbaaErrorCode.invalidInput);
  if (useCache) await backend._offlineTail;
  final cache = useCache ? backend._offlineCache : null;
  final account = useCache ? backend._offlineAccount : null;
  switch (query.view) {
    case FeatureQueryView.summary:
      if (cache != null && account != null) {
        final value = await backend.client.bykcCoursesCached(
          cache: cache,
          page: query.page <= 0 ? 1 : query.page,
          size: query.size.clamp(1, 100),
          all: true,
        );
        return _finishBykcRefresh(
          backend,
          account,
          _projectBykcCourses(
            value.data,
            _toConnectionMode(value.route.resolvedRoute),
          ),
          value.state,
        );
      }
      final value = await backend.client.bykcCourses(
        page: query.page <= 0 ? 1 : query.page,
        size: query.size.clamp(1, 100),
        all: true,
      );
      return _projectBykcCourses(
        value.data,
        _toConnectionMode(value.route.resolvedRoute),
      );
    case FeatureQueryView.bykcDetail:
      if (cache != null && account != null) {
        final value = await backend.client.bykcDetailCached(
          cache: cache,
          courseId: _requiredPositiveQueryInt(query.courseId, '课程 ID'),
        );
        return _finishBykcRefresh(
          backend,
          account,
          _projectBykcDetail(
            value.data,
            _toConnectionMode(value.route.resolvedRoute),
          ),
          value.state,
        );
      }
      final value = await backend.client.bykcCourseDetail(
        id: _requiredPositiveQueryInt(query.courseId, '课程 ID'),
      );
      return _projectBykcDetail(
        value.data,
        _toConnectionMode(value.route.resolvedRoute),
      );
    case FeatureQueryView.bykcProfile:
      if (cache != null && account != null) {
        final value = await backend.client.bykcProfileCached(cache: cache);
        return _finishBykcRefresh(
          backend,
          account,
          _projectBykcProfile(
            value.data,
            _toConnectionMode(value.route.resolvedRoute),
          ),
          value.state,
        );
      }
      final value = await backend.client.bykcProfile();
      return _projectBykcProfile(
        value.data,
        _toConnectionMode(value.route.resolvedRoute),
      );
    case FeatureQueryView.bykcChosenCourses:
      if (cache != null && account != null) {
        final value = await backend.client.bykcChosenCached(cache: cache);
        return _finishBykcRefresh(
          backend,
          account,
          _projectBykcChosen(
            value.data,
            _toConnectionMode(value.route.resolvedRoute),
          ),
          value.state,
        );
      }
      final value = await backend.client.bykcChosenCourses();
      return _projectBykcChosen(
        value.data,
        _toConnectionMode(value.route.resolvedRoute),
      );
    case FeatureQueryView.bykcStatistics:
      if (cache != null && account != null) {
        final value = await backend.client.bykcStatisticsCached(cache: cache);
        return _finishBykcRefresh(
          backend,
          account,
          _projectBykcStatistics(
            value.data,
            _toConnectionMode(value.route.resolvedRoute),
          ),
          value.state,
        );
      }
      final value = await backend.client.bykcStatistics();
      return _projectBykcStatistics(
        value.data,
        _toConnectionMode(value.route.resolvedRoute),
      );
    default:
      throw const BackendException(UbaaErrorCode.invalidInput);
  }
}

FeatureResult _finishBykcRefresh(
  BridgeBackend backend,
  LocalAccount account,
  FeatureResult result,
  BridgeBykcRefreshState state,
) {
  if (backend._offlineAccount?.id != account.id)
    throw const BackendException(UbaaErrorCode.operationConflict);
  final overview = state.semesterStart != null && state.semesterEnd != null
      ? BykcChosenOverview(
          semesterStart: state.semesterStart!,
          semesterEnd: state.semesterEnd!,
        )
      : result.overview;
  final evidence = DataEvidence(
    accountId: account.id,
    origin: DataOrigin.online,
    fetchedAt: _cacheTime(state.fetchedAt.toInt()),
    complete: true,
    savedForOffline: state.saveError == null,
  );
  return result.isEmpty
      ? FeatureResult.empty(
          overview: overview,
          pagination: result.pagination,
          resolvedRoute: result.resolvedRoute,
          evidence: evidence,
        )
      : FeatureResult.success(
          summary: result.summary,
          details: result.details,
          overview: overview,
          pagination: result.pagination,
          resolvedRoute: result.resolvedRoute,
          evidence: evidence,
        );
}

part of '../bridge_backend.dart';

Future<FeatureResult> _loadBykcFeature(
  BridgeBackend backend,
  FeatureId feature,
  FeatureQuery query, {
  bool useCache = true,
}) async {
  if (feature != FeatureId.bykc)
    throw const BackendException(UbaaErrorCode.invalidInput);
  if (useCache) await _awaitOfflineScope(backend);
  final cache = useCache ? backend._offlineCache : null;
  final account = useCache ? backend._offlineAccount : null;
  switch (query.view) {
    case FeatureQueryView.summary:
      if (cache != null && account != null) {
        final value = await backend.client.bykcCatalogCached(
          cache: cache,
          page: query.page <= 0 ? 1 : query.page,
          size: query.size.clamp(1, 100),
          all: true,
        );
        return _finishBykcRefresh(
          backend,
          account,
          _projectBykcCatalog(
            value.data,
            _toConnectionMode(value.route.resolvedRoute),
            requestedPage: query.page <= 0 ? 1 : query.page,
            requestedSize: query.size.clamp(1, 100),
          ),
          value.state,
        );
      }
      final value = await backend.client.bykcCourseCatalog(
        page: query.page <= 0 ? 1 : query.page,
        size: query.size.clamp(1, 100),
        all: true,
      );
      return _projectBykcCatalog(
        value.data,
        _toConnectionMode(value.route.resolvedRoute),
        requestedPage: query.page <= 0 ? 1 : query.page,
        requestedSize: query.size.clamp(1, 100),
      );
    case FeatureQueryView.bykcDetail:
      if (cache != null && account != null) {
        final value = await backend.client.bykcFullDetailCached(
          cache: cache,
          courseId: _requiredPositiveQueryInt(query.courseId, '课程 ID'),
        );
        if (value.data.course.course.id !=
            _requiredPositiveQueryInt(query.courseId, '课程 ID')) {
          return _preserveBykcDetail(
            backend,
            cache,
            account,
            query,
            _toConnectionMode(value.route.resolvedRoute),
          );
        }
        return _finishBykcRefresh(
          backend,
          account,
          _projectBykcFullDetail(
            value.data,
            _toConnectionMode(value.route.resolvedRoute),
          ),
          value.state,
        );
      }
      final value = await backend.client.bykcCourseFullDetail(
        id: _requiredPositiveQueryInt(query.courseId, '课程 ID'),
      );
      return _projectBykcFullDetail(
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
      final detailId = query.courseId == null
          ? null
          : _requiredPositiveQueryInt(query.courseId, '课程 ID');
      Future<BykcCoursePresentation?> fullDetail(ConnectionMode route) async {
        if (detailId == null) return null;
        final full = await backend.client.bykcCourseFullDetail(id: detailId);
        if (full.data.course.course.id != detailId ||
            _toConnectionMode(full.route.resolvedRoute) != route) {
          throw const BackendException(UbaaErrorCode.operationConflict);
        }
        return _bykcCoursePresentation(
          full.data.course.course,
          isDetail: true,
          catalog: full.data.course,
          supplement: _bykcSupplement(full.data),
        );
      }
      if (cache != null && account != null) {
        final value = await backend.client.bykcChosenCached(cache: cache);
        return _finishBykcRefresh(
          backend,
          account,
          _projectBykcChosen(
            value.data,
            _toConnectionMode(value.route.resolvedRoute),
            fullDetail: await fullDetail(
              _toConnectionMode(value.route.resolvedRoute),
            ),
          ),
          value.state,
        );
      }
      final value = await backend.client.bykcChosenCourses();
      return _projectBykcChosen(
        value.data,
        _toConnectionMode(value.route.resolvedRoute),
        fullDetail: await fullDetail(
          _toConnectionMode(value.route.resolvedRoute),
        ),
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

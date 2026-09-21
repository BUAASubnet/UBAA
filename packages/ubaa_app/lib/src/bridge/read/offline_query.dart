part of '../bridge_backend.dart';

Future<OfflineQueryRead> _readCachedQuery(
  BridgeBackend backend,
  FeatureId feature,
  FeatureQuery query,
  RoutePolicy policy,
) async {
  await backend._offlineTail;
  final cache = backend._offlineCache;
  final account = backend._offlineAccount;
  if (cache == null || account == null) return const OfflineQueryRead(null);
  final today =
      feature == FeatureId.schedule &&
      (query.view == FeatureQueryView.scheduleToday ||
          (query.view == FeatureQueryView.summary &&
              !(query.term != null && query.week != null)));
  final summary =
      feature == FeatureId.judge && query.view == FeatureQueryView.summary;
  final detail =
      feature == FeatureId.judge && query.view == FeatureQueryView.judgeDetail;
  if (!today && !summary && !detail) return const OfflineQueryRead(null);
  final routes = switch (policy) {
    RoutePolicy.direct => [BridgeConnectionMode.direct],
    RoutePolicy.webvpn => [BridgeConnectionMode.webVpn],
    RoutePolicy.auto => [
      BridgeConnectionMode.direct,
      BridgeConnectionMode.webVpn,
    ],
  };
  CachedFeatureProjection? newest;
  BackendException? failure;
  for (final route in routes) {
    try {
      CachedFeatureProjection? value;
      if (today) {
        final record = await cache.readToday(route: route);
        if (record != null)
          value = CachedFeatureProjection(
            feature: feature,
            query: query,
            accountId: account.id,
            route: _toConnectionMode(record.sourceRoute),
            fetchedAt: _cacheTime(record.fetchedAt.toInt()),
            complete: record.complete,
            scopeDate: record.date,
            details: record.data.map(_todayDetail),
          );
      } else if (summary) {
        final record = await cache.readJudge(
          route: route,
          includeExpired: query.includeExpired,
        );
        if (record != null)
          value = CachedFeatureProjection(
            feature: feature,
            query: query,
            accountId: account.id,
            route: _toConnectionMode(record.sourceRoute),
            fetchedAt: _cacheTime(record.fetchedAt.toInt()),
            complete: record.complete,
            details: _judgeSummaryDetails(
              record.data,
              includeExpired: query.includeExpired,
            ),
          );
      } else {
        final courseId = _requiredQueryValue(query.courseId, '课程编号');
        final assignmentId = _requiredQueryValue(query.assignmentId, '作业编号');
        final record = await cache.readJudgeDetail(
          route: route,
          courseId: courseId,
          assignmentId: assignmentId,
        );
        if (record != null) {
          if (record.data.courseId != courseId ||
              record.data.assignmentId != assignmentId) {
            throw const BackendException(UbaaErrorCode.internalError);
          }
          value = CachedFeatureProjection(
            feature: feature,
            query: query,
            accountId: account.id,
            route: _toConnectionMode(record.sourceRoute),
            fetchedAt: _cacheTime(record.fetchedAt.toInt()),
            complete: record.complete,
            details: [_judgeDetailPresentation(record.data)],
          );
        }
      }
      if (value != null &&
          (newest == null || value.fetchedAt.isAfter(newest.fetchedAt)))
        newest = value;
    } on BridgeError catch (error) {
      failure ??= _mapError(error);
    } on BackendException catch (error) {
      failure ??= error;
    }
  }
  return OfflineQueryRead(newest, error: failure);
}

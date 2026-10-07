import 'dart:async';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/backend.dart';
import 'package:ubaa_app/src/bridge/context.dart';
import '../../cache/lifecycle.dart' show bridgeAwaitOfflineScope;
import 'cache.dart' show bridgeCachedBykcProjection;
import 'projection.dart'
    show
        bridgeBykcCoursePresentation,
        bridgeBykcSupplement,
        bridgeProjectBykcCatalog,
        bridgeProjectBykcChosen,
        bridgeProjectBykcFullDetail,
        bridgeProjectBykcProfile,
        bridgeProjectBykcStatistics;
import '../../support/mapping.dart'
    show
        bridgeCacheTime,
        bridgeRequiredPositiveQueryInt,
        bridgeToBridgeConnectionMode,
        bridgeToConnectionMode;
part 'cache_read.dart';

Future<FeatureResult> bridgeLoadBykcFeature(
  BridgeContext backend,
  FeatureId feature,
  FeatureQuery query, {
  bool useCache = true,
}) async {
  if (feature != FeatureId.bykc)
    throw const BackendException(UbaaErrorCode.invalidInput);
  if (useCache) await bridgeAwaitOfflineScope(backend);
  final cache = useCache ? backend.cache.handle : null;
  final account = useCache ? backend.cache.account : null;
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
          bridgeProjectBykcCatalog(
            value.data,
            bridgeToConnectionMode(value.route.resolvedRoute),
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
      return bridgeProjectBykcCatalog(
        value.data,
        bridgeToConnectionMode(value.route.resolvedRoute),
        requestedPage: query.page <= 0 ? 1 : query.page,
        requestedSize: query.size.clamp(1, 100),
      );
    case FeatureQueryView.bykcDetail:
      if (cache != null && account != null) {
        final value = await backend.client.bykcFullDetailCached(
          cache: cache,
          courseId: bridgeRequiredPositiveQueryInt(query.courseId, '课程 ID'),
        );
        if (value.data.course.course.id !=
            bridgeRequiredPositiveQueryInt(query.courseId, '课程 ID')) {
          return _preserveBykcDetail(
            backend,
            cache,
            account,
            query,
            bridgeToConnectionMode(value.route.resolvedRoute),
          );
        }
        return _finishBykcRefresh(
          backend,
          account,
          bridgeProjectBykcFullDetail(
            value.data,
            bridgeToConnectionMode(value.route.resolvedRoute),
          ),
          value.state,
        );
      }
      final value = await backend.client.bykcCourseFullDetail(
        id: bridgeRequiredPositiveQueryInt(query.courseId, '课程 ID'),
      );
      return bridgeProjectBykcFullDetail(
        value.data,
        bridgeToConnectionMode(value.route.resolvedRoute),
      );
    case FeatureQueryView.bykcProfile:
      if (cache != null && account != null) {
        final value = await backend.client.bykcProfileCached(cache: cache);
        return _finishBykcRefresh(
          backend,
          account,
          bridgeProjectBykcProfile(
            value.data,
            bridgeToConnectionMode(value.route.resolvedRoute),
          ),
          value.state,
        );
      }
      final value = await backend.client.bykcProfile();
      return bridgeProjectBykcProfile(
        value.data,
        bridgeToConnectionMode(value.route.resolvedRoute),
      );
    case FeatureQueryView.bykcChosenCourses:
      final detailId = query.courseId == null
          ? null
          : bridgeRequiredPositiveQueryInt(query.courseId, '课程 ID');
      Future<BykcCoursePresentation?> fullDetail(ConnectionMode route) async {
        if (detailId == null) return null;
        final full = await backend.client.bykcCourseFullDetail(id: detailId);
        if (full.data.course.course.id != detailId ||
            bridgeToConnectionMode(full.route.resolvedRoute) != route) {
          throw const BackendException(UbaaErrorCode.operationConflict);
        }
        return bridgeBykcCoursePresentation(
          full.data.course.course,
          isDetail: true,
          catalog: full.data.course,
          supplement: bridgeBykcSupplement(full.data),
        );
      }
      if (cache != null && account != null) {
        final value = await backend.client.bykcChosenCached(cache: cache);
        return _finishBykcRefresh(
          backend,
          account,
          bridgeProjectBykcChosen(
            value.data,
            bridgeToConnectionMode(value.route.resolvedRoute),
            fullDetail: await fullDetail(
              bridgeToConnectionMode(value.route.resolvedRoute),
            ),
          ),
          value.state,
        );
      }
      final value = await backend.client.bykcChosenCourses();
      return bridgeProjectBykcChosen(
        value.data,
        bridgeToConnectionMode(value.route.resolvedRoute),
        fullDetail: await fullDetail(
          bridgeToConnectionMode(value.route.resolvedRoute),
        ),
      );
    case FeatureQueryView.bykcStatistics:
      if (cache != null && account != null) {
        final value = await backend.client.bykcStatisticsCached(cache: cache);
        return _finishBykcRefresh(
          backend,
          account,
          bridgeProjectBykcStatistics(
            value.data,
            bridgeToConnectionMode(value.route.resolvedRoute),
          ),
          value.state,
        );
      }
      final value = await backend.client.bykcStatistics();
      return bridgeProjectBykcStatistics(
        value.data,
        bridgeToConnectionMode(value.route.resolvedRoute),
      );
    default:
      throw const BackendException(UbaaErrorCode.invalidInput);
  }
}

FeatureResult _finishBykcRefresh(
  BridgeContext backend,
  LocalAccount account,
  FeatureResult result,
  BridgeBykcRefreshState state,
) {
  if (backend.cache.account?.id != account.id)
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
    fetchedAt: bridgeCacheTime(state.fetchedAt.toInt()),
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

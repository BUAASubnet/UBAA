import 'dart:async';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/backend.dart';
import 'projection.dart'
    show
        bridgeBykcCatalogPageSize,
        bridgeCachedBykcCatalog,
        bridgeCachedBykcChosen,
        bridgeCachedBykcCourse,
        bridgeCachedBykcSupplement,
        bridgeBykcCoursePresentation,
        bridgeCachedBykcPage,
        bridgeProjectBykcChosen,
        bridgeProjectBykcCourses,
        bridgeProjectBykcDetail,
        bridgeProjectBykcProfile,
        bridgeProjectBykcStatistics;
import '../../support/mapping.dart'
    show
        bridgeCacheTime,
        bridgeRequiredPositiveQueryInt,
        bridgeToConnectionMode;

Future<CachedFeatureProjection?> bridgeCachedBykcProjection(
  BridgeOfflineCache cache,
  LocalAccount account,
  FeatureQuery query,
  BridgeConnectionMode route,
) async {
  FeatureResult result;
  late int fetchedAt;
  late bool complete;
  late BridgeConnectionMode source;
  FeatureOverview? overview;
  switch (query.view) {
    case FeatureQueryView.summary:
      final value = await cache.readBykcCourses(
        route: route,
        page: query.page <= 0 ? 1 : query.page,
        size: bridgeBykcCatalogPageSize,
        all: true,
      );
      if (value == null) return null;
      result = bridgeProjectBykcCourses(
        bridgeCachedBykcPage(value.data),
        bridgeToConnectionMode(value.sourceRoute),
        requestedPage: query.page <= 0 ? 1 : query.page,
        requestedSize: bridgeBykcCatalogPageSize,
        catalog: {
          for (final item in value.data.content)
            item.id: bridgeCachedBykcCatalog(item),
        },
      );
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;
      source = value.sourceRoute;
    case FeatureQueryView.bykcDetail:
      final value = await cache.readBykcDetail(
        route: route,
        courseId: bridgeRequiredPositiveQueryInt(query.courseId, '课程 ID'),
      );
      if (value == null) return null;
      if (value.data.id !=
          bridgeRequiredPositiveQueryInt(query.courseId, '课程 ID'))
        throw const BackendException(UbaaErrorCode.internalError);
      result = bridgeProjectBykcDetail(
        bridgeCachedBykcCourse(value.data),
        bridgeToConnectionMode(value.sourceRoute),
        catalog: bridgeCachedBykcCatalog(value.data),
        supplement: bridgeCachedBykcSupplement(value.data),
      );
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;
      source = value.sourceRoute;
    case FeatureQueryView.bykcProfile:
      final value = await cache.readBykcProfile(route: route);
      if (value == null) return null;
      result = bridgeProjectBykcProfile(
        value.data,
        bridgeToConnectionMode(value.sourceRoute),
      );
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;
      source = value.sourceRoute;
    case FeatureQueryView.bykcChosenCourses:
      final value = await cache.readBykcChosen(route: route);
      if (value == null) return null;
      BykcCoursePresentation? fullDetail;
      var chosenFetchedAt = value.fetchedAt.toInt();
      var chosenComplete = value.complete;
      if (query.courseId != null) {
        final id = bridgeRequiredPositiveQueryInt(query.courseId, '课程 ID');
        final detail = await cache.readBykcDetail(route: route, courseId: id);
        if (detail != null && detail.data.id == id) {
          if (detail.fetchedAt.toInt() < chosenFetchedAt)
            chosenFetchedAt = detail.fetchedAt.toInt();
          chosenComplete = chosenComplete && detail.complete;
          fullDetail = bridgeBykcCoursePresentation(
            bridgeCachedBykcCourse(detail.data),
            isDetail: true,
            catalog: bridgeCachedBykcCatalog(detail.data),
            supplement: bridgeCachedBykcSupplement(detail.data),
          );
        }
      }
      result = bridgeProjectBykcChosen(
        value.data.courses.map(bridgeCachedBykcChosen).toList(),
        bridgeToConnectionMode(value.sourceRoute),
        persisted: true,
        fullDetail: fullDetail,
        cachedSignPoints: {
          for (final item in value.data.courses)
            if (item.signWindow != null)
              (item.id, item.courseId): item.signWindow!.hasPoints,
        },
      );
      fetchedAt = chosenFetchedAt;
      complete = chosenComplete;
      source = value.sourceRoute;
      overview = BykcChosenOverview(
        semesterStart: value.data.semesterStart,
        semesterEnd: value.data.semesterEnd,
      );
    case FeatureQueryView.bykcStatistics:
      final value = await cache.readBykcStatistics(route: route);
      if (value == null) return null;
      result = bridgeProjectBykcStatistics(
        value.data,
        bridgeToConnectionMode(value.sourceRoute),
      );
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;
      source = value.sourceRoute;
    default:
      return null;
  }
  return CachedFeatureProjection(
    feature: FeatureId.bykc,
    query: query,
    accountId: account.id,
    route: bridgeToConnectionMode(source),
    fetchedAt: bridgeCacheTime(fetchedAt),
    complete: complete,
    details: result.details,
    overview: overview ?? result.overview,
    pagination: result.pagination,
  );
}

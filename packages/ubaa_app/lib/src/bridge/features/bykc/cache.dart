import 'dart:async';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'projection.dart'
    show
        bridgeCachedBykcCatalog,
        bridgeCachedBykcChosen,
        bridgeCachedBykcCourse,
        bridgeCachedBykcSupplement,
        bridgeBykcCoursePresentation,
        bridgeProjectBykcChosen,
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

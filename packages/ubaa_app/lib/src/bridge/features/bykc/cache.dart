import 'dart:async';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/backend.dart';
import 'projection.dart'
    show
        bridgeCachedBykcCatalog,
        bridgeCachedBykcChosen,
        bridgeCachedBykcCourse,
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
        size: query.size.clamp(1, 100),
        all: true,
      );
      if (value == null) return null;
      result = bridgeProjectBykcCourses(
        bridgeCachedBykcPage(value.data),
        bridgeToConnectionMode(value.sourceRoute),
        requestedPage: query.page <= 0 ? 1 : query.page,
        requestedSize: query.size.clamp(1, 100),
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
      result = bridgeProjectBykcChosen(
        value.data.courses.map(bridgeCachedBykcChosen).toList(),
        bridgeToConnectionMode(value.sourceRoute),
        persisted: true,
      );
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;
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

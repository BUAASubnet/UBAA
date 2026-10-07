import 'dart:async';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/src/backend.dart';
import 'package:ubaa_app/src/bridge/context.dart';
import '../assignments/projection.dart'
    show bridgeJudgeDetailPresentation, bridgeJudgeSummaryDetails;
import '../cache/lifecycle.dart' show bridgeAwaitOfflineScope;
import '../features/academic/projection.dart' show bridgeIsAcademicCacheQuery;
import '../features/academic/reader.dart' show bridgeCachedAcademicProjection;
import '../features/bykc/cache.dart' show bridgeCachedBykcProjection;
import '../features/bykc/projection.dart' show bridgeIsBykcCacheQuery;
import '../features/cgyy/cache.dart' show bridgeCachedCgyyProjection;
import '../features/cgyy/projection.dart' show bridgeIsCgyyCacheQuery;
import '../features/evaluation/cache.dart'
    show bridgeCachedEvaluationProjection;
import '../features/evaluation/projection.dart'
    show bridgeIsEvaluationCacheQuery;
import '../features/judge/cache.dart' show bridgeReadCachedJudgeBatch;
import '../features/libbook/cache.dart' show bridgeCachedLibbookProjection;
import '../features/libbook/projection.dart' show bridgeIsLibbookCacheQuery;
import '../features/schedule/projection.dart' show bridgeTodayDetail;
import '../features/ygdk/cache.dart' show bridgeCachedYgdkRecordsProjection;
import '../home/cache.dart' show bridgeCachedHomeProjection;
import '../home/projection.dart' show bridgeIsHomeCacheQuery;
import '../support/mapping.dart'
    show
        bridgeCacheTime,
        bridgeDateOnly,
        bridgeMapError,
        bridgeRequiredQueryValue,
        bridgeToConnectionMode;

Future<OfflineQueryRead> bridgeReadCachedQuery(
  BridgeContext backend,
  FeatureId feature,
  FeatureQuery query,
  RoutePolicy policy,
) async {
  await bridgeAwaitOfflineScope(backend);
  final cache = backend.cache.handle;
  final account = backend.cache.account;
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
  final batch =
      feature == FeatureId.judge &&
      query.view == FeatureQueryView.judgeBatchDetails;
  final academic = bridgeIsAcademicCacheQuery(feature, query);
  final ygdkRecords =
      feature == FeatureId.ygdk && query.view == FeatureQueryView.ygdkRecords;
  final evaluation = bridgeIsEvaluationCacheQuery(feature, query);
  final libbook = bridgeIsLibbookCacheQuery(feature, query);
  final cgyy = bridgeIsCgyyCacheQuery(feature, query);
  final bykc = bridgeIsBykcCacheQuery(feature, query);
  final home = bridgeIsHomeCacheQuery(feature, query);
  if (!today &&
      !summary &&
      !detail &&
      !batch &&
      !academic &&
      !home &&
      !bykc &&
      !cgyy &&
      !libbook &&
      !evaluation &&
      !ygdkRecords)
    return const OfflineQueryRead(null);
  final queryDate = bridgeDateOnly(query.date ?? DateTime.now());
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
      if (batch) {
        final read = await bridgeReadCachedJudgeBatch(
          cache,
          account,
          query,
          route,
        );
        value = read.projection;
        failure ??= read.error;
      } else if (ygdkRecords) {
        value = await bridgeCachedYgdkRecordsProjection(
          cache,
          account,
          query,
          route,
        );
      } else if (evaluation) {
        value = await bridgeCachedEvaluationProjection(
          cache,
          account,
          query,
          route,
        );
      } else if (libbook) {
        value = await bridgeCachedLibbookProjection(
          cache,
          account,
          query,
          route,
          queryDate,
        );
      } else if (cgyy) {
        value = await bridgeCachedCgyyProjection(
          cache,
          account,
          query,
          route,
          queryDate,
        );
      } else if (bykc) {
        value = await bridgeCachedBykcProjection(cache, account, query, route);
      } else if (home) {
        value = await bridgeCachedHomeProjection(
          cache,
          account,
          feature,
          query,
          route,
        );
      } else if (academic) {
        value = await bridgeCachedAcademicProjection(
          backend,
          feature,
          query,
          route,
          account,
          queryDate,
        );
      } else if (today) {
        final record = await cache.readToday(route: route);
        if (record != null)
          value = CachedFeatureProjection(
            feature: feature,
            query: query,
            accountId: account.id,
            route: bridgeToConnectionMode(record.sourceRoute),
            fetchedAt: bridgeCacheTime(record.fetchedAt.toInt()),
            complete: record.complete,
            scopeDate: record.date,
            details: record.data.map(bridgeTodayDetail),
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
            route: bridgeToConnectionMode(record.sourceRoute),
            fetchedAt: bridgeCacheTime(record.fetchedAt.toInt()),
            complete: record.complete,
            details: bridgeJudgeSummaryDetails(
              record.data,
              includeExpired: query.includeExpired,
            ),
          );
      } else {
        final courseId = bridgeRequiredQueryValue(query.courseId, '课程编号');
        final assignmentId = bridgeRequiredQueryValue(
          query.assignmentId,
          '作业编号',
        );
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
            route: bridgeToConnectionMode(record.sourceRoute),
            fetchedAt: bridgeCacheTime(record.fetchedAt.toInt()),
            complete: record.complete,
            details: [bridgeJudgeDetailPresentation(record.data)],
          );
        }
      }
      if (value != null &&
          (newest == null ||
              (batch && value.complete != newest.complete
                  ? value.complete
                  : value.fetchedAt.isAfter(newest.fetchedAt))))
        newest = value;
    } on BridgeError catch (error) {
      failure ??= bridgeMapError(error);
    } on BackendException catch (error) {
      failure ??= error;
    }
  }
  return OfflineQueryRead(newest, error: failure);
}

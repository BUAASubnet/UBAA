import 'dart:async';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/backend.dart';
import 'package:ubaa_app/src/bridge/context.dart';
import '../../cache/lifecycle.dart' show bridgeAwaitOfflineScope;
import 'cache.dart' show bridgeCachedLibbookProjection;
import 'projection.dart'
    show
        bridgeIsLibbookCacheQuery,
        bridgeLibbookDated,
        bridgeProjectLibbookAreaDetail,
        bridgeProjectLibbookAreas,
        bridgeProjectLibbookBookings,
        bridgeProjectLibbookLibraries,
        bridgeProjectLibbookSchedule,
        bridgeProjectLibbookSeats;
import '../../support/mapping.dart'
    show
        bridgeCacheTime,
        bridgeRequiredQueryValue,
        bridgeToBridgeConnectionMode,
        bridgeToConnectionMode;
part 'cache_read.dart';

Future<FeatureResult> bridgeLoadLibbookFeature(
  BridgeContext backend,
  FeatureId feature,
  FeatureQuery query,
  String today, {
  bool useCache = true,
}) async {
  if (useCache && bridgeIsLibbookCacheQuery(feature, query)) {
    final cached = await _loadCachedLibbookFeature(backend, query, today);
    if (cached != null) return cached;
  }
  final client = backend.client;
  switch (feature) {
    case FeatureId.libbook:
      switch (query.view) {
        case FeatureQueryView.summary:
          final result = await client.libbookLibraries(day: today);
          return bridgeProjectLibbookLibraries(
            result.data,
            bridgeToConnectionMode(result.route.resolvedRoute),
            today,
            query,
          );
        case FeatureQueryView.libbookAreas:
          final premisesId = bridgeRequiredQueryValue(
            query.premisesId,
            '馆区 ID',
          );
          final result = await client.libbookAreas(
            premisesId: premisesId,
            storeyId: query.storeyId,
            day: today,
          );
          return bridgeProjectLibbookAreas(
            result.data,
            bridgeToConnectionMode(result.route.resolvedRoute),
            today,
            query,
          );
        case FeatureQueryView.libbookAreaDetail:
          final areaId = bridgeRequiredQueryValue(query.areaId, '分区 ID');
          final result = await client.libbookAreaSchedule(areaId: areaId);
          return bridgeProjectLibbookSchedule(
            result.data,
            bridgeToConnectionMode(result.route.resolvedRoute),
          );
        case FeatureQueryView.libbookSeats:
          final areaId = bridgeRequiredQueryValue(query.areaId, '分区 ID');
          bridgeRequiredQueryValue(query.segment, '时段');
          final startTime = bridgeRequiredQueryValue(query.startTime, '开始时间');
          final endTime = bridgeRequiredQueryValue(query.endTime, '结束时间');
          final result = await client.libbookSeats(
            areaId: areaId,
            day: today,
            startTime: startTime,
            endTime: endTime,
          );
          return bridgeProjectLibbookSeats(
            result.data,
            bridgeToConnectionMode(result.route.resolvedRoute),
            today,
            query,
          );
        case FeatureQueryView.libbookBookings:
          final page = query.page <= 0 ? 1 : query.page;
          final limit = query.size.clamp(1, 100);
          final result = await client.libbookBookings(page: page, limit: limit);
          return bridgeProjectLibbookBookings(
            result.data,
            bridgeToConnectionMode(result.route.resolvedRoute),
            today,
            query,
          );
        case FeatureQueryView.ygdkRecords:
        case FeatureQueryView.bykcDetail:
        case FeatureQueryView.bykcProfile:
        case FeatureQueryView.bykcChosenCourses:
        case FeatureQueryView.bykcStatistics:
        case FeatureQueryView.scheduleToday:
        case FeatureQueryView.scheduleTerms:
        case FeatureQueryView.scheduleWeeks:
        case FeatureQueryView.scheduleWeek:
        case FeatureQueryView.examArranged:
        case FeatureQueryView.examNotArranged:
        case FeatureQueryView.gradesScored:
        case FeatureQueryView.gradesMissing:
        case FeatureQueryView.evaluationPending:
        case FeatureQueryView.cgyyPurposeTypes:
        case FeatureQueryView.cgyyDayInfo:
        case FeatureQueryView.cgyyOrders:
        case FeatureQueryView.cgyyOrderDetail:
        case FeatureQueryView.cgyyLockCode:
        case FeatureQueryView.spocDetail:
        case FeatureQueryView.judgeDetail:
        case FeatureQueryView.judgeBatchDetails:
        case FeatureQueryView.signinPending:
        case FeatureQueryView.signinCompleted:
          throw const BackendException(UbaaErrorCode.invalidInput);
      }
    default:
      throw StateError('unexpected feature: $feature');
  }
}

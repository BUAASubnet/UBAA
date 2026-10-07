import 'dart:async';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/src/backend.dart';
import 'package:ubaa_app/src/bridge/context.dart';
import '../../cache/lifecycle.dart' show bridgeAwaitOfflineScope;
import 'cache.dart'
    show
        HomeYgdkRead,
        bridgeCachedYgdkRecordsProjection,
        bridgeLocalYgdkHomeRecords;
import 'projection.dart'
    show
        bridgeMapYgdkOverviewResult,
        bridgeMapYgdkRecordsResult,
        bridgeYgdkHomeRecords;
import '../../home/reader.dart'
    show bridgeFinishHomeRefresh, bridgeReadYgdkHome;
import '../../support/mapping.dart'
    show
        bridgeCacheTime,
        bridgeMapError,
        bridgeToBridgeConnectionMode,
        bridgeToConnectionMode,
        bridgeTypedErrorCode;
part 'reader_records.dart';
part 'reader_home.dart';

Future<FeatureResult> bridgeLoadYgdkOverviewOnRoute(
  BridgeContext backend, {
  required ConnectionMode route,
}) async {
  try {
    final result = await backend.client.ygdkOverviewOnRoute(
      route: bridgeToBridgeConnectionMode(route),
    );
    return bridgeMapYgdkOverviewResult(
      result.data,
      bridgeToConnectionMode(result.pinnedRoute),
    );
  } on BridgeError catch (error) {
    throw bridgeMapError(error);
  }
}

Future<FeatureResult> bridgeLoadYgdkRecordsOnRoute(
  BridgeContext backend, {
  required ConnectionMode route,
  required int page,
  required int size,
}) async {
  if (page <= 0 || size <= 0) {
    throw const BackendException(UbaaErrorCode.invalidInput);
  }
  try {
    final result = await backend.client.ygdkRecordsOnRoute(
      route: bridgeToBridgeConnectionMode(route),
      page: page,
      size: size,
    );
    return bridgeMapYgdkRecordsResult(
      result.data,
      bridgeToConnectionMode(result.pinnedRoute),
    );
  } on BridgeError catch (error) {
    throw bridgeMapError(error);
  }
}

Future<FeatureResult> bridgeLoadYgdkFeature(
  BridgeContext backend,
  FeatureId feature,
  FeatureQuery query, {
  bool includeRecords = false,
}) async {
  final client = backend.client;
  switch (feature) {
    case FeatureId.ygdk:
      switch (query.view) {
        case FeatureQueryView.summary:
          final result = await bridgeReadYgdkHome(backend);
          YgdkHomeRecords? records;
          if (includeRecords) {
            records = await _readYgdkHomeRecords(backend, result, query);
          }
          final projection = bridgeMapYgdkOverviewResult(
            result.data,
            bridgeToConnectionMode(result.route),
            records: records,
          );
          return bridgeFinishHomeRefresh(
            backend,
            result.cache,
            result.account,
            feature,
            query,
            projection,
            result.state,
          );
        case FeatureQueryView.ygdkRecords:
          final cached = await _loadCachedYgdkRecords(backend, query);
          if (cached != null) return cached;
          final page = query.page <= 0 ? 1 : query.page;
          final size = query.size.clamp(1, 100);
          final result = await client.ygdkRecords(page: page, size: size);
          return bridgeMapYgdkRecordsResult(
            result.data,
            bridgeToConnectionMode(result.route.resolvedRoute),
          );
        case FeatureQueryView.libbookAreas:
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
        case FeatureQueryView.libbookAreaDetail:
        case FeatureQueryView.libbookSeats:
        case FeatureQueryView.libbookBookings:
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

import 'dart:async';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/backend.dart';
import 'package:ubaa_app/src/bridge/context.dart';
import '../../cache/lifecycle.dart' show bridgeAwaitOfflineScope;
import 'cache.dart' show bridgeCachedCgyyProjection;
import 'projection.dart'
    show
        bridgeIsCgyyCacheQuery,
        bridgeMapCgyyDayInfo,
        bridgeMapCgyyOrderDetailResult,
        bridgeMapCgyyOrdersResult,
        bridgeProjectCgyyPurposes,
        bridgeProjectCgyySites;
import '../../support/mapping.dart'
    show
        bridgeCacheTime,
        bridgeMapError,
        bridgeRequiredPositiveInt,
        bridgeToBridgeConnectionMode,
        bridgeToConnectionMode;
part 'cache_read.dart';

Future<FeatureResult> bridgeLoadCgyyOrdersOnRoute(
  BridgeContext backend, {
  required ConnectionMode route,
  required int page,
  required int size,
}) async {
  if (page < 0 || size <= 0) {
    throw const BackendException(UbaaErrorCode.invalidInput);
  }
  try {
    final result = await backend.client.cgyyOrdersOnRoute(
      route: bridgeToBridgeConnectionMode(route),
      page: page,
      size: size,
    );
    return bridgeMapCgyyOrdersResult(
      result.data,
      bridgeToConnectionMode(result.pinnedRoute),
    );
  } on BridgeError catch (error) {
    throw bridgeMapError(error);
  }
}

Future<FeatureResult> bridgeLoadCgyyOrderDetailOnRoute(
  BridgeContext backend, {
  required ConnectionMode route,
  required int orderId,
}) async {
  if (orderId <= 0) {
    throw const BackendException(UbaaErrorCode.invalidInput);
  }
  try {
    final result = await backend.client.cgyyOrderDetailOnRoute(
      route: bridgeToBridgeConnectionMode(route),
      id: orderId,
    );
    return bridgeMapCgyyOrderDetailResult(
      result.data,
      bridgeToConnectionMode(result.pinnedRoute),
    );
  } on BridgeError catch (error) {
    throw bridgeMapError(error);
  }
}

Future<FeatureResult> bridgeLoadCgyyFeature(
  BridgeContext backend,
  FeatureId feature,
  FeatureQuery query,
  String today, {
  bool useCache = true,
}) async {
  if (useCache &&
      feature == FeatureId.cgyy &&
      bridgeIsCgyyCacheQuery(feature, query)) {
    final result = await _loadCachedCgyyFeature(backend, query, today);
    if (result != null) return result;
  }
  final client = backend.client;
  switch (feature) {
    case FeatureId.cgyy:
      switch (query.view) {
        case FeatureQueryView.summary:
          final result = await client.cgyySites();
          return bridgeProjectCgyySites(
            result.data,
            bridgeToConnectionMode(result.route.resolvedRoute),
            today,
          );
        case FeatureQueryView.cgyyPurposeTypes:
          final result = await client.cgyyPurposeTypes();
          return bridgeProjectCgyyPurposes(
            result.data,
            bridgeToConnectionMode(result.route.resolvedRoute),
          );
        case FeatureQueryView.cgyyDayInfo:
          final siteId = bridgeRequiredPositiveInt(query.siteId, '站点 ID');
          final result = await client.cgyyDayInfo(siteId: siteId, date: today);
          return bridgeMapCgyyDayInfo(
            result.data,
            bridgeToConnectionMode(result.route.resolvedRoute),
          );
        case FeatureQueryView.cgyyOrders:
          // 订单接口与固定路线回读均采用零基页码。
          final page = query.page < 0 ? 0 : query.page;
          final size = query.size.clamp(1, 100);
          final result = await client.cgyyOrders(page: page, size: size);
          return bridgeMapCgyyOrdersResult(
            result.data,
            bridgeToConnectionMode(result.route.resolvedRoute),
          );
        case FeatureQueryView.cgyyOrderDetail:
          final orderId = bridgeRequiredPositiveInt(query.orderId, '订单 ID');
          final result = await client.cgyyOrderDetail(id: orderId);
          return bridgeMapCgyyOrderDetailResult(
            result.data,
            bridgeToConnectionMode(result.route.resolvedRoute),
          );
        case FeatureQueryView.cgyyLockCode:
          final result = await client.cgyyLockCode();
          return FeatureResult.success(
            summary: result.data.available ? '门锁可用' : '门锁不可用',
            details: <FeatureDetail>[
              FeatureDetail(
                title: '门锁状态',
                presentation: CgyyLockPresentation(
                  available: result.data.available,
                ),
                fields: <FeatureField>[
                  FeatureField(
                    label: '可用',
                    value: result.data.available ? '是' : '否',
                  ),
                ],
              ),
            ],
            resolvedRoute: bridgeToConnectionMode(result.route.resolvedRoute),
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
        case FeatureQueryView.ygdkRecords:
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

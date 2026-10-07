import 'dart:async';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/backend.dart';
import 'projection.dart'
    show
        bridgeCachedCgyyDayInfo,
        bridgeCachedCgyyOrder,
        bridgeCachedCgyyOrdersPage,
        bridgeMapCgyyDayInfo,
        bridgeMapCgyyOrderDetailResult,
        bridgeMapCgyyOrdersResult,
        bridgeProjectCgyyPurposes,
        bridgeProjectCgyySites;
import '../../support/mapping.dart'
    show bridgeCacheTime, bridgeRequiredPositiveInt, bridgeToConnectionMode;

Future<CachedFeatureProjection?> bridgeCachedCgyyProjection(
  BridgeOfflineCache cache,
  LocalAccount account,
  FeatureQuery query,
  BridgeConnectionMode sourceRoute,
  String today,
) async {
  FeatureResult result;
  late int fetchedAt;
  late bool complete;
  late ConnectionMode route;
  switch (query.view) {
    case FeatureQueryView.summary:
      final value = await cache.readCgyySites(route: sourceRoute);
      if (value == null) return null;
      route = bridgeToConnectionMode(value.sourceRoute);
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;
      result = bridgeProjectCgyySites(value.data, route, today);
    case FeatureQueryView.cgyyPurposeTypes:
      final value = await cache.readCgyyPurposes(route: sourceRoute);
      if (value == null) return null;
      route = bridgeToConnectionMode(value.sourceRoute);
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;
      result = bridgeProjectCgyyPurposes(value.data, route);
    case FeatureQueryView.cgyyDayInfo:
      final value = await cache.readCgyyDay(
        route: sourceRoute,
        siteId: bridgeRequiredPositiveInt(query.siteId, '站点 ID'),
        date: today,
      );
      if (value == null) return null;
      route = bridgeToConnectionMode(value.sourceRoute);
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;
      if (value.data.reservationDate != today ||
          value.data.venueSiteId != query.siteId)
        throw const BackendException(UbaaErrorCode.internalError);
      result = bridgeMapCgyyDayInfo(
        bridgeCachedCgyyDayInfo(value.data),
        route,
        persisted: true,
      );
    case FeatureQueryView.cgyyOrders:
      final value = await cache.readCgyyOrders(
        route: sourceRoute,
        page: query.page < 0 ? 0 : query.page,
        size: query.size.clamp(1, 100),
      );
      if (value == null) return null;
      route = bridgeToConnectionMode(value.sourceRoute);
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;
      if (value.data.number != (query.page < 0 ? 0 : query.page) ||
          value.data.size != query.size.clamp(1, 100))
        throw const BackendException(UbaaErrorCode.internalError);
      result = bridgeMapCgyyOrdersResult(
        bridgeCachedCgyyOrdersPage(value.data),
        route,
      );
    case FeatureQueryView.cgyyOrderDetail:
      final value = await cache.readCgyyDetail(
        route: sourceRoute,
        orderId: bridgeRequiredPositiveInt(query.orderId, '订单 ID'),
      );
      if (value == null) return null;
      route = bridgeToConnectionMode(value.sourceRoute);
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;
      if (value.data.id != query.orderId)
        throw const BackendException(UbaaErrorCode.internalError);
      result = bridgeMapCgyyOrderDetailResult(
        bridgeCachedCgyyOrder(value.data),
        route,
      );
    default:
      return null;
  }
  return CachedFeatureProjection(
    feature: FeatureId.cgyy,
    query: query,
    accountId: account.id,
    route: route,
    fetchedAt: bridgeCacheTime(fetchedAt),
    complete: complete,
    details: result.details,
    pagination: result.pagination,
    scopeDate: query.view == FeatureQueryView.cgyyDayInfo ? today : null,
  );
}

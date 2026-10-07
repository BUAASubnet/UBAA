import 'dart:async';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/backend.dart';
import 'projection.dart'
    show
        bridgeCachedLibbookBookingsPage,
        bridgeCachedLibbookSeat,
        bridgeLibbookDated,
        bridgeProjectLibbookAreaDetail,
        bridgeProjectLibbookAreas,
        bridgeProjectLibbookBookings,
        bridgeProjectLibbookLibraries,
        bridgeProjectLibbookSchedule,
        bridgeProjectLibbookSeats;
import '../../support/mapping.dart'
    show bridgeCacheTime, bridgeRequiredQueryValue, bridgeToConnectionMode;

Future<CachedFeatureProjection?> bridgeCachedLibbookProjection(
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
      final value = await cache.readLibbookLibraries(
        route: sourceRoute,
        day: today,
      );
      if (value == null) return null;
      route = bridgeToConnectionMode(value.sourceRoute);
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;

      result = bridgeProjectLibbookLibraries(
        value.data,
        route,
        today,
        query,
        persisted: true,
      );
    case FeatureQueryView.libbookAreas:
      final value = await cache.readLibbookAreas(
        route: sourceRoute,
        premisesId: bridgeRequiredQueryValue(query.premisesId, '馆区 ID'),
        storeyId: query.storeyId,
        day: today,
      );
      if (value == null) return null;
      route = bridgeToConnectionMode(value.sourceRoute);
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;

      result = bridgeProjectLibbookAreas(
        value.data,
        route,
        today,
        query,
        persisted: true,
      );
    case FeatureQueryView.libbookAreaDetail:
      final value = await cache.readLibbookAreaDetail(
        route: sourceRoute,
        areaId: bridgeRequiredQueryValue(query.areaId, '分区 ID'),
      );
      if (value == null) return null;
      route = bridgeToConnectionMode(value.sourceRoute);
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;
      if (value.data.id != query.areaId)
        throw const BackendException(UbaaErrorCode.internalError);
      result = value.schedule != null
          ? bridgeProjectLibbookSchedule(value.schedule!, route)
          : bridgeProjectLibbookAreaDetail(
              value.data,
              route,
              today,
              query,
              persisted: true,
            );
    case FeatureQueryView.libbookSeats:
      final value = await cache.readLibbookSeats(
        route: sourceRoute,
        areaId: bridgeRequiredQueryValue(query.areaId, '分区 ID'),
        day: today,
        startTime: bridgeRequiredQueryValue(query.startTime, '开始时间'),
        endTime: bridgeRequiredQueryValue(query.endTime, '结束时间'),
      );
      if (value == null) return null;
      route = bridgeToConnectionMode(value.sourceRoute);
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;

      result = bridgeProjectLibbookSeats(
        value.data.map(bridgeCachedLibbookSeat).toList(),
        route,
        today,
        query,
        persisted: true,
      );
    case FeatureQueryView.libbookBookings:
      final value = await cache.readLibbookBookings(
        route: sourceRoute,
        page: query.page <= 0 ? 1 : query.page,
        limit: query.size.clamp(1, 100),
      );
      if (value == null) return null;
      route = bridgeToConnectionMode(value.sourceRoute);
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;

      result = bridgeProjectLibbookBookings(
        bridgeCachedLibbookBookingsPage(value.data),
        route,
        today,
        query,
        persisted: true,
      );
    default:
      return null;
  }
  return CachedFeatureProjection(
    feature: FeatureId.libbook,
    query: query,
    accountId: account.id,
    route: route,
    fetchedAt: bridgeCacheTime(fetchedAt),
    complete: complete,
    details: result.details,
    pagination: result.pagination,
    scopeDate: bridgeLibbookDated(query) ? today : null,
  );
}

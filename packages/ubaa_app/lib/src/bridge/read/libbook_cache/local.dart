part of '../../bridge_backend.dart';

bool _isLibbookCacheQuery(FeatureId feature, FeatureQuery query) =>
    feature == FeatureId.libbook &&
    {
      FeatureQueryView.summary,
      FeatureQueryView.libbookAreas,
      FeatureQueryView.libbookAreaDetail,
      FeatureQueryView.libbookSeats,
      FeatureQueryView.libbookBookings,
    }.contains(query.view);
Future<CachedFeatureProjection?> _cachedLibbookProjection(
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
      route = _toConnectionMode(value.sourceRoute);
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;

      result = _projectLibbookLibraries(
        value.data,
        route,
        today,
        query,
        persisted: true,
      );
    case FeatureQueryView.libbookAreas:
      final value = await cache.readLibbookAreas(
        route: sourceRoute,
        premisesId: _requiredQueryValue(query.premisesId, '馆区 ID'),
        storeyId: query.storeyId,
        day: today,
      );
      if (value == null) return null;
      route = _toConnectionMode(value.sourceRoute);
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;

      result = _projectLibbookAreas(
        value.data,
        route,
        today,
        query,
        persisted: true,
      );
    case FeatureQueryView.libbookAreaDetail:
      final value = await cache.readLibbookAreaDetail(
        route: sourceRoute,
        areaId: _requiredQueryValue(query.areaId, '分区 ID'),
      );
      if (value == null) return null;
      route = _toConnectionMode(value.sourceRoute);
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;
      if (value.data.id != query.areaId)
        throw const BackendException(UbaaErrorCode.internalError);
      result = _projectLibbookAreaDetail(
        value.data,
        route,
        today,
        query,
        persisted: true,
      );
    case FeatureQueryView.libbookSeats:
      final value = await cache.readLibbookSeats(
        route: sourceRoute,
        areaId: _requiredQueryValue(query.areaId, '分区 ID'),
        day: today,
        startTime: _requiredQueryValue(query.startTime, '开始时间'),
        endTime: _requiredQueryValue(query.endTime, '结束时间'),
      );
      if (value == null) return null;
      route = _toConnectionMode(value.sourceRoute);
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;

      result = _projectLibbookSeats(
        value.data.map(_cachedLibbookSeat).toList(),
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
      route = _toConnectionMode(value.sourceRoute);
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;

      result = _projectLibbookBookings(
        _cachedLibbookBookingsPage(value.data),
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
    fetchedAt: _cacheTime(fetchedAt),
    complete: complete,
    details: result.details,
    pagination: result.pagination,
    scopeDate: _libbookDated(query) ? today : null,
  );
}

bool _libbookDated(FeatureQuery query) => {
  FeatureQueryView.summary,
  FeatureQueryView.libbookAreas,
  FeatureQueryView.libbookSeats,
}.contains(query.view);
BridgeLibBookSeat _cachedLibbookSeat(BridgeCachedLibBookSeat v) =>
    BridgeLibBookSeat(
      id: v.id,
      name: v.name,
      no: v.no,
      status: v.status,
      statusName: v.statusName,
      reserveEligibility: BridgeActionEligibility.unknown,
      reserveTarget: null,
    );
BridgeLibBookBooking _cachedLibbookBooking(BridgeCachedLibBookBooking v) =>
    BridgeLibBookBooking(
      id: v.id,
      nameMerge: v.nameMerge,
      areaName: v.areaName,
      seatNo: v.seatNo,
      day: v.day,
      beginTime: v.beginTime,
      endTime: v.endTime,
      status: v.status,
      statusName: v.statusName,
      cancelEligibility: BridgeActionEligibility.unknown,
      cancelTarget: null,
    );
BridgeLibBookBookingsPage _cachedLibbookBookingsPage(
  BridgeCachedLibBookBookingsPage v,
) => BridgeLibBookBookingsPage(
  bookings: v.bookings.map(_cachedLibbookBooking).toList(),
  page: v.page,
  limit: v.limit,
  total: v.total,
);

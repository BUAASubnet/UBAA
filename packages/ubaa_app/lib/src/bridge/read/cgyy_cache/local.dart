part of '../../bridge_backend.dart';

bool _isCgyyCacheQuery(FeatureId feature, FeatureQuery query) =>
    feature == FeatureId.cgyy &&
    {
      FeatureQueryView.summary,
      FeatureQueryView.cgyyPurposeTypes,
      FeatureQueryView.cgyyDayInfo,
      FeatureQueryView.cgyyOrders,
      FeatureQueryView.cgyyOrderDetail,
    }.contains(query.view);
Future<CachedFeatureProjection?> _cachedCgyyProjection(
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
      route = _toConnectionMode(value.sourceRoute);
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;
      result = _projectCgyySites(value.data, route, today);
    case FeatureQueryView.cgyyPurposeTypes:
      final value = await cache.readCgyyPurposes(route: sourceRoute);
      if (value == null) return null;
      route = _toConnectionMode(value.sourceRoute);
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;
      result = _projectCgyyPurposes(value.data, route);
    case FeatureQueryView.cgyyDayInfo:
      final value = await cache.readCgyyDay(
        route: sourceRoute,
        siteId: _requiredPositiveInt(query.siteId, '站点 ID'),
        date: today,
      );
      if (value == null) return null;
      route = _toConnectionMode(value.sourceRoute);
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;
      if (value.data.reservationDate != today ||
          value.data.venueSiteId != query.siteId)
        throw const BackendException(UbaaErrorCode.internalError);
      result = _mapCgyyDayInfo(
        _cachedCgyyDayInfo(value.data),
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
      route = _toConnectionMode(value.sourceRoute);
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;
      result = _mapCgyyOrdersResult(_cachedCgyyOrdersPage(value.data), route);
    case FeatureQueryView.cgyyOrderDetail:
      final value = await cache.readCgyyDetail(
        route: sourceRoute,
        orderId: _requiredPositiveInt(query.orderId, '订单 ID'),
      );
      if (value == null) return null;
      route = _toConnectionMode(value.sourceRoute);
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;
      if (value.data.id != query.orderId)
        throw const BackendException(UbaaErrorCode.internalError);
      result = _mapCgyyOrderDetailResult(_cachedCgyyOrder(value.data), route);
    default:
      return null;
  }
  return CachedFeatureProjection(
    feature: FeatureId.cgyy,
    query: query,
    accountId: account.id,
    route: route,
    fetchedAt: _cacheTime(fetchedAt),
    complete: complete,
    details: result.details,
    pagination: result.pagination,
    scopeDate: query.view == FeatureQueryView.cgyyDayInfo ? today : null,
  );
}

BridgeCgyySlotStatus _cachedCgyySlotStatus(BridgeCachedCgyySlotStatus v) =>
    BridgeCgyySlotStatus(
      timeId: v.timeId,
      reservationStatus: v.reservationStatus,
      reservationEligibility: BridgeActionEligibility.unknown,
      reservationTarget: null,
      startDate: v.startDate,
      endDate: v.endDate,
    );
BridgeCgyySpaceAvailability _cachedCgyySpaceAvailability(
  BridgeCachedCgyySpaceAvailability v,
) => BridgeCgyySpaceAvailability(
  spaceId: v.spaceId,
  spaceName: v.spaceName,
  venueSiteId: v.venueSiteId,
  venueSpaceGroupId: v.venueSpaceGroupId,
  slots: v.slots.map(_cachedCgyySlotStatus).toList(),
);
BridgeCgyyDayInfo _cachedCgyyDayInfo(BridgeCachedCgyyDayInfo v) =>
    BridgeCgyyDayInfo(
      venueSiteId: v.venueSiteId,
      reservationDate: v.reservationDate,
      availableDates: v.availableDates,
      timeSlots: v.timeSlots,
      spaces: v.spaces.map(_cachedCgyySpaceAvailability).toList(),
      reservationTotalNum: v.reservationTotalNum,
    );
BridgeCgyyOrder _cachedCgyyOrder(BridgeCachedCgyyOrder v) => BridgeCgyyOrder(
  id: v.id,
  venueSiteId: v.venueSiteId,
  reservationDate: v.reservationDate,
  reservationDateDetail: v.reservationDateDetail,
  venueSpaceName: v.venueSpaceName,
  campusName: v.campusName,
  venueName: v.venueName,
  siteName: v.siteName,
  reservationStartDate: v.reservationStartDate,
  reservationEndDate: v.reservationEndDate,
  orderStatus: v.orderStatus,
  checkStatus: v.checkStatus,
  theme: v.theme,
  purposeTypeName: v.purposeTypeName,
  joinerNum: v.joinerNum,
  cancelEligibility: BridgeActionEligibility.unknown,
  cancelTarget: null,
  cancelledTarget: null,
);
BridgeCgyyOrdersPage _cachedCgyyOrdersPage(BridgeCachedCgyyOrdersPage v) =>
    BridgeCgyyOrdersPage(
      content: v.content.map(_cachedCgyyOrder).toList(),
      totalElements: v.totalElements,
      totalPages: v.totalPages,
      size: v.size,
      number: v.number,
    );

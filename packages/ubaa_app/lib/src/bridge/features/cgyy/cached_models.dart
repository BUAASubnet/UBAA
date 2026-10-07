part of 'projection.dart';

bool bridgeIsCgyyCacheQuery(FeatureId feature, FeatureQuery query) =>
    feature == FeatureId.cgyy &&
    {
      FeatureQueryView.summary,
      FeatureQueryView.cgyyPurposeTypes,
      FeatureQueryView.cgyyDayInfo,
      FeatureQueryView.cgyyOrders,
      FeatureQueryView.cgyyOrderDetail,
    }.contains(query.view);

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

BridgeCgyyDayInfo bridgeCachedCgyyDayInfo(BridgeCachedCgyyDayInfo v) =>
    BridgeCgyyDayInfo(
      venueSiteId: v.venueSiteId,
      reservationDate: v.reservationDate,
      availableDates: v.availableDates,
      timeSlots: v.timeSlots,
      spaces: v.spaces.map(_cachedCgyySpaceAvailability).toList(),
      reservationTotalNum: v.reservationTotalNum,
    );

BridgeCgyyOrder bridgeCachedCgyyOrder(BridgeCachedCgyyOrder v) =>
    BridgeCgyyOrder(
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

BridgeCgyyOrdersPage bridgeCachedCgyyOrdersPage(BridgeCachedCgyyOrdersPage v) =>
    BridgeCgyyOrdersPage(
      content: v.content.map(bridgeCachedCgyyOrder).toList(),
      totalElements: v.totalElements,
      totalPages: v.totalPages,
      size: v.size,
      number: v.number,
    );

part of 'projection.dart';

bool bridgeIsLibbookCacheQuery(FeatureId feature, FeatureQuery query) =>
    feature == FeatureId.libbook &&
    {
      FeatureQueryView.summary,
      FeatureQueryView.libbookAreas,
      FeatureQueryView.libbookAreaDetail,
      FeatureQueryView.libbookSeats,
      FeatureQueryView.libbookBookings,
    }.contains(query.view);

bool bridgeLibbookDated(FeatureQuery query) => {
  FeatureQueryView.summary,
  FeatureQueryView.libbookAreas,
  FeatureQueryView.libbookSeats,
}.contains(query.view);

BridgeLibBookSeat bridgeCachedLibbookSeat(BridgeCachedLibBookSeat v) =>
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

BridgeLibBookBookingsPage bridgeCachedLibbookBookingsPage(
  BridgeCachedLibBookBookingsPage v,
) => BridgeLibBookBookingsPage(
  bookings: v.bookings.map(_cachedLibbookBooking).toList(),
  page: v.page,
  limit: v.limit,
  total: v.total,
);

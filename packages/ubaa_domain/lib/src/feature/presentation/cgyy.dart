part of '../presentation.dart';

final class CgyySitePresentation extends FeaturePresentation {
  const CgyySitePresentation({
    required this.id,
    required this.siteName,
    required this.venueName,
    required this.campusName,
    this.seatCount,
    this.reservationSpaceCount,
    this.openStartDate,
    this.openEndDate,
    this.queryDate,
  });
  final int id;
  final String siteName, venueName, campusName;
  final int? seatCount, reservationSpaceCount;
  final String? openStartDate, openEndDate;

  /// 读取站点时应用持有的查询日期，用于后续日期空间查询。
  final String? queryDate;
}

final class CgyyPurposePresentation extends FeaturePresentation {
  const CgyyPurposePresentation({
    required this.key,
    required this.name,
    required this.isStaticFallback,
  });
  final int key;
  final String name;
  final bool isStaticFallback;
}

final class CgyyDayPresentation extends FeaturePresentation {
  const CgyyDayPresentation({
    required this.venueSiteId,
    required this.reservationDate,
    required this.availableDates,
    required this.timeSlots,
    required this.spaces,
    this.reservationTotalNum,
  });
  final int venueSiteId;
  final String reservationDate;
  final List<String> availableDates;
  final List<CgyyTimePresentation> timeSlots;
  final List<CgyySpacePresentation> spaces;
  final int? reservationTotalNum;
}

final class CgyyTimePresentation {
  const CgyyTimePresentation({
    required this.id,
    required this.beginTime,
    required this.endTime,
    required this.label,
  });
  final int id;
  final String beginTime, endTime, label;
}

final class CgyySpacePresentation {
  const CgyySpacePresentation({
    required this.spaceId,
    required this.spaceName,
    required this.venueSiteId,
    this.venueSpaceGroupId,
  });
  final int spaceId, venueSiteId;
  final String spaceName;
  final int? venueSpaceGroupId;
}

/// 仅描述读取到的时段；可点击预约必须另取独立typed action。
final class CgyySlotPresentation extends FeaturePresentation {
  const CgyySlotPresentation({
    required this.venueSiteId,
    required this.reservationDate,
    required this.spaceId,
    required this.spaceName,
    required this.timeId,
    this.venueSpaceGroupId,
    this.reservationStatus,
    this.beginTime,
    this.endTime,
    this.timeLabel,
    this.startDate,
    this.endDate,
  });
  final int venueSiteId, spaceId, timeId;
  final String reservationDate, spaceName;
  final int? venueSpaceGroupId, reservationStatus;
  final String? beginTime, endTime, timeLabel, startDate, endDate;
}

final class CgyyOrderPresentation extends FeaturePresentation {
  const CgyyOrderPresentation({
    required this.id,
    this.venueSiteId,
    this.reservationDate,
    this.reservationDateDetail,
    this.venueSpaceName,
    this.campusName,
    this.venueName,
    this.siteName,
    this.reservationStartDate,
    this.reservationEndDate,
    this.orderStatus,
    this.checkStatus,
    this.theme,
    this.purposeTypeName,
    this.joinerNum,
    required this.statusText,
    this.checkStatusText,
  });
  final int id;
  final int? venueSiteId, orderStatus, checkStatus, joinerNum;
  final String? reservationDate,
      reservationDateDetail,
      venueSpaceName,
      campusName,
      venueName,
      siteName,
      reservationStartDate,
      reservationEndDate,
      theme,
      purposeTypeName,
      checkStatusText;
  final String statusText;
}

final class CgyyLockPresentation extends FeaturePresentation {
  const CgyyLockPresentation({required this.available});
  final bool available;
}

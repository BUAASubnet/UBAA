part of '../presentation.dart';

// 原始公开值与读取归属；写入资格和目标始终位于独立action。

final class LibbookLibraryPresentation extends FeaturePresentation {
  const LibbookLibraryPresentation({
    required this.id,
    required this.name,
    required this.freeNum,
    required this.totalNum,
    required this.queryDate,
    required this.storeys,
  });
  final String id;
  final String name;
  final int freeNum;
  final int totalNum;
  final String queryDate;
  final List<LibbookStoreyPresentation> storeys;
}

final class LibbookStoreyPresentation {
  const LibbookStoreyPresentation({
    required this.id,
    required this.name,
    required this.freeNum,
    required this.totalNum,
  });
  final String id;
  final String name;
  final int freeNum;
  final int totalNum;
}

final class LibbookAreaPresentation extends FeaturePresentation {
  const LibbookAreaPresentation({
    required this.id,
    required this.name,
    required this.areaName,
    required this.premisesId,
    required this.storeyId,
    required this.freeNum,
    required this.totalNum,
    required this.queryDate,
  });
  final String id;
  final String name;
  final String areaName;
  final String premisesId;
  final String storeyId;
  final int freeNum;
  final int totalNum;
  final String queryDate;
}

final class LibbookAreaDetailPresentation extends FeaturePresentation {
  const LibbookAreaDetailPresentation({
    required this.id,
    required this.name,
    required this.availableDates,
    required this.timeSlots,
  });
  final String id;
  final String name;
  final List<String> availableDates;

  /// 公开合同没有日期与时段关联，不得据此自动给某个日期配对。
  final List<LibbookTimeSlotPresentation> timeSlots;
}

final class LibbookTimeSlotPresentation {
  const LibbookTimeSlotPresentation({
    required this.id,
    required this.start,
    required this.end,
    required this.label,
  });
  final String id;
  final String start;
  final String end;
  final String label;
}

final class LibbookSeatPresentation extends FeaturePresentation {
  const LibbookSeatPresentation({
    required this.id,
    required this.name,
    required this.number,
    required this.status,
    required this.statusName,
    required this.areaId,
    required this.queryDate,
    required this.segment,
    required this.startTime,
    required this.endTime,
  });
  final String id;
  final String name;
  final String number;
  final int? status;
  final String statusName;
  final String areaId;
  final String queryDate;
  final String segment;
  final String startTime;
  final String endTime;
}

final class LibbookBookingPresentation extends FeaturePresentation {
  const LibbookBookingPresentation({
    required this.id,
    required this.name,
    required this.areaName,
    required this.seatNumber,
    required this.day,
    required this.beginTime,
    required this.endTime,
    required this.status,
    required this.statusName,
  });
  final String id;
  final String name;
  final String areaName;
  final String seatNumber;
  final String day;
  final String beginTime;
  final String endTime;
  final int? status;
  final String statusName;
}

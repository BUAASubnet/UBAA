part of '../presentation.dart';

final class YgdkItemPresentation extends FeaturePresentation {
  const YgdkItemPresentation({
    required this.itemId,
    required this.name,
    this.kind,
    this.sort,
  });
  final int itemId;
  final String name;
  final int? kind, sort;
}

final class YgdkRecordPresentation extends FeaturePresentation {
  const YgdkRecordPresentation({
    required this.recordId,
    required this.imageCount,
    required this.isOpen,
    this.itemId,
    this.itemName,
    this.startTime,
    this.endTime,
    this.place,
    this.state,
    this.createdAt,
    this.createdAtLabel,
  });
  final int recordId, imageCount;
  final int? itemId, state;
  final bool isOpen;
  final String? itemName, startTime, endTime, place, createdAt, createdAtLabel;
}

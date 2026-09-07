part of '../presentation.dart';

final class ClassroomPresentation extends FeaturePresentation {
  const ClassroomPresentation({
    required this.roomId,
    required this.floorId,
    required this.floorName,
    required this.availableSections,
    this.queryDate,
    this.campus,
  });

  final String roomId;
  final String floorId;
  final String floorName;
  final String availableSections;

  /// 本次只读请求的日期与校区，缺失时不能假定属于当前筛选。
  final String? queryDate;
  final int? campus;

  /// 冻结节次为逗号分隔令牌；保持顺序，不把缺失/非法文本转换为数字。
  List<String> get sectionTokens => List<String>.unmodifiable(
    availableSections
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty),
  );
}

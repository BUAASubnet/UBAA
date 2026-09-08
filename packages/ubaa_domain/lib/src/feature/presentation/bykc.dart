part of '../presentation.dart';

enum BykcCourseStatus { preview, available, full, selected, ended, expired }

/// 课程列表与详情的公开投影；显示状态、人数不承担写资格判断。
final class BykcCoursePresentation extends FeaturePresentation {
  const BykcCoursePresentation({
    required this.id,
    required this.courseName,
    required this.status,
    this.courseTeacher,
    this.coursePosition,
    this.courseStartDate,
    this.courseEndDate,
    this.courseSelectStartDate,
    this.courseSelectEndDate,
    this.courseCancelEndDate,
    this.courseCurrentCount,
    this.courseMaxCount,
    this.selected,
    this.isDetail = false,
  });
  final int id;
  final String courseName;
  final BykcCourseStatus status;
  final String? courseTeacher, coursePosition, courseStartDate, courseEndDate;
  final String? courseSelectStartDate, courseSelectEndDate, courseCancelEndDate;
  final int? courseCurrentCount, courseMaxCount;
  final bool? selected;
  final bool isDetail;
}

final class BykcChosenPresentation extends FeaturePresentation {
  const BykcChosenPresentation({
    required this.recordId,
    required this.courseId,
    required this.courseName,
    this.courseTeacher,
    this.coursePosition,
    this.courseStartDate,
    this.courseEndDate,
    this.courseCancelEndDate,
    this.selectDate,
    this.category,
    this.subCategory,
    this.checkin,
    this.pass,
    this.score,
    this.signStartDate,
    this.signEndDate,
    this.signOutStartDate,
    this.signOutEndDate,
    this.signPointCount,
    this.courseSignType,
  });
  final int recordId, courseId;
  final String courseName;
  final String? courseTeacher, coursePosition, courseStartDate, courseEndDate;
  final String? courseCancelEndDate, selectDate, category, subCategory;
  final int? checkin, pass, score;
  final String? signStartDate, signEndDate, signOutStartDate, signOutEndDate;
  final int? signPointCount, courseSignType;
}

final class BykcStatisticsPresentation extends FeaturePresentation {
  const BykcStatisticsPresentation({this.totalValidCount});
  final int? totalValidCount;
}

final class BykcCategoryPresentation extends FeaturePresentation {
  const BykcCategoryPresentation({
    this.categoryName,
    this.subCategoryName,
    this.requiredCount,
    this.passedCount,
    this.qualified,
  });
  final String? categoryName, subCategoryName;
  final int? requiredCount, passedCount;
  final bool? qualified;
}

final class BykcProfilePresentation extends FeaturePresentation {
  const BykcProfilePresentation({
    required this.id,
    this.realName,
    this.studentNo,
    this.collegeName,
  });
  final int id;
  final String? realName, studentNo, collegeName;
}

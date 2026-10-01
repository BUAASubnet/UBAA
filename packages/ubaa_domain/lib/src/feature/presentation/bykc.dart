part of '../presentation.dart';

enum BykcCourseStatus { preview, available, full, selected, ended, expired }

enum BykcCourseCategory {
  boya('博雅课程'),
  unknown('未知分类');

  const BykcCourseCategory(this.displayName);
  final String displayName;
}

enum BykcCourseSubCategory {
  moral('德育'),
  aesthetic('美育'),
  labor('劳动教育'),
  safetyHealth('安全健康'),
  other('其他方面'),
  unknown('未知类型');

  const BykcCourseSubCategory(this.displayName);
  final String displayName;
}

/// 只读详情补充，与已选快照中的动作资格分开。
final class BykcCourseSupplement {
  const BykcCourseSupplement({
    this.courseContact,
    this.courseContactMobile,
    this.organizerCollegeName,
    this.descriptionPlainText,
    this.audienceColleges = const [],
    this.audienceTerms = const [],
    this.audienceGroups = const [],
    this.signConfig,
    this.attendance,
  });
  final String? courseContact,
      courseContactMobile,
      organizerCollegeName,
      descriptionPlainText;
  final List<String> audienceColleges, audienceTerms, audienceGroups;
  final BykcSignDisplayConfig? signConfig;
  final BykcAttendanceDisplay? attendance;
}

final class BykcSignDisplayConfig {
  const BykcSignDisplayConfig({
    this.signStartDate,
    this.signEndDate,
    this.signOutStartDate,
    this.signOutEndDate,
    required this.signPointCount,
  });
  final String? signStartDate, signEndDate, signOutStartDate, signOutEndDate;
  final int signPointCount;
}

/// 补查身份只用于展示，不能转换为 FeatureAction。
final class BykcAttendanceDisplay {
  const BykcAttendanceDisplay({
    required this.recordId,
    required this.courseId,
    this.checkin,
    this.pass,
  });
  final int recordId, courseId;
  final int? checkin, pass;
}

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
    this.category,
    this.subCategory,
    this.audienceCampuses = const [],
    this.hasSignPoints = false,
    this.supplement,
  });
  final int id;
  final String courseName;
  final BykcCourseStatus status;
  final String? courseTeacher, coursePosition, courseStartDate, courseEndDate;
  final String? courseSelectStartDate, courseSelectEndDate, courseCancelEndDate;
  final int? courseCurrentCount, courseMaxCount;
  final bool? selected;
  final bool isDetail;
  final BykcCourseCategory? category;
  final BykcCourseSubCategory? subCategory;
  final List<String> audienceCampuses;
  final bool hasSignPoints;
  final BykcCourseSupplement? supplement;
  String? get categoryDisplayName =>
      subCategory?.displayName ?? category?.displayName;
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
    this.fullDetail,
  });
  final int recordId, courseId;
  final String courseName;
  final String? courseTeacher, coursePosition, courseStartDate, courseEndDate;
  final String? courseCancelEndDate, selectDate, category, subCategory;
  final int? checkin, pass, score;
  final String? signStartDate, signEndDate, signOutStartDate, signOutEndDate;
  final int? signPointCount, courseSignType;
  final BykcCoursePresentation? fullDetail;

  BykcChosenPresentation withFullDetail(BykcCoursePresentation detail) =>
      BykcChosenPresentation(
        recordId: recordId,
        courseId: courseId,
        courseName: courseName,
        courseTeacher: courseTeacher,
        coursePosition: coursePosition,
        courseStartDate: courseStartDate,
        courseEndDate: courseEndDate,
        courseCancelEndDate: courseCancelEndDate,
        selectDate: selectDate,
        category: category,
        subCategory: subCategory,
        checkin: checkin,
        pass: pass,
        score: score,
        signStartDate: signStartDate,
        signEndDate: signEndDate,
        signOutStartDate: signOutStartDate,
        signOutEndDate: signOutEndDate,
        signPointCount: signPointCount,
        courseSignType: courseSignType,
        fullDetail: detail,
      );
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

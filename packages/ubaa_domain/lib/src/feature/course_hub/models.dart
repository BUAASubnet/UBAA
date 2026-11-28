import '../../models.dart';
import '../spoc_files.dart';

enum CourseHubSource {
  schedule,
  spocCourses,
  spocAssignments,
  judgeAssignments,
  exams,
  grades,
}

enum CourseHubSourceState {
  ready,
  partial,
  loading,
  failed,
  notLoaded,
  notApplicable,
}

final class CourseHubSourceStatus {
  const CourseHubSourceStatus(this.state, [this.error]);
  final CourseHubSourceState state;
  final UiError? error;
}

final class CourseHubWeek {
  const CourseHubWeek({
    required this.startDate,
    required this.endDate,
    required this.slots,
  });
  final String startDate, endDate;
  final List<FeatureDetail> slots;
}

final class CourseHubSnapshot {
  const CourseHubSnapshot({
    this.termCode,
    this.termName,
    this.graduate,
    this.courses = const [],
    this.sources = const {},
    this.allAssignments = const [],
  });
  final String? termCode, termName;
  final bool? graduate;
  final List<CourseHubCourse> courses;
  final Map<CourseHubSource, CourseHubSourceStatus> sources;
  final List<CourseHubAssignment> allAssignments;
}

typedef CourseHubNextClass = ({
  DateTime start,
  DateTime? end,
  String? place,
  int? beginSection,
  int? endSection,
});
typedef CourseHubJudgeLink = ({String judgeCourseId, String name, bool linked});

final class CourseHubCourse {
  const CourseHubCourse({
    required this.key,
    required this.name,
    required this.courseCode,
    required this.credit,
    required this.teachers,
    required this.slots,
    required this.nextClass,
    required this.spocCourses,
    required this.judgeLinks,
    required this.assignments,
    required this.exams,
    required this.grades,
  });
  final String key, name;
  final String? courseCode, credit;
  final List<String> teachers;
  bool get scheduleLinked => slots.isNotEmpty;
  final List<FeatureDetail> slots, exams, grades;
  final CourseHubNextClass? nextClass;
  final List<SpocCourse> spocCourses;
  final List<CourseHubJudgeLink> judgeLinks;
  final List<CourseHubAssignment> assignments;
}

final class CourseHubAssignment {
  const CourseHubAssignment({
    required this.feature,
    required this.detail,
    this.courseKey,
    this.courseName,
  });
  final FeatureId feature;
  final FeatureDetail detail;
  final String? courseKey, courseName;
  FeatureReadNavigation? get navigation => detail.readNavigation;
}

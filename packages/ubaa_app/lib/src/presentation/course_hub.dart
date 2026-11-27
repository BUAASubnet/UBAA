import 'package:ubaa_domain/ubaa_domain.dart';

String _name(String name) => name
    .replaceAll('（', '(')
    .replaceAll('）', ')')
    .replaceAll(RegExp(r'\s+', unicode: true), '');

DateTime? _instant(String? text) {
  if (text == null ||
      text.length < 10 ||
      homeParseDate(text.substring(0, 10)) == null)
    return null;
  final value = text.length == 10 ? '${text}T00:00:00' : text;
  return DateTime.tryParse(
    RegExp(r'(Z|[+-]\d\d:?\d\d)$').hasMatch(value) ? value : '$value+08:00',
  )?.toUtc();
}

typedef _SlotKey = (int?, int?, int?, String?);

final class _Course {
  _Course(this.key, this.name, this.code);
  final String key, name;
  final String? code;
  String? credit;
  final teachers = <String>{};
  final slots = <_SlotKey, FeatureDetail>{};
  final spoc = <SpocCourse>[];
  final links = <CourseHubJudgeLink>[];
  final assignments = <CourseHubAssignment>[];
  final exams = <FeatureDetail>[], grades = <FeatureDetail>[];
  CourseHubNextClass? next;
  (int, int) first = (9, 999);
  CourseHubCourse freeze() => CourseHubCourse(
    key: key,
    name: name,
    courseCode: code,
    credit: credit,
    teachers: List.unmodifiable(teachers),
    slots: List.unmodifiable(slots.values),
    nextClass: next,
    spocCourses: List.unmodifiable(spoc),
    judgeLinks: List.unmodifiable(links),
    assignments: List.unmodifiable(assignments),
    exams: List.unmodifiable(exams),
    grades: List.unmodifiable(grades),
  );
}

CourseHubSnapshot buildCourseHub({
  String? termCode,
  String? termName,
  required bool? graduate,
  required DateTime now,
  List<SpocCourse> spocCourses = const [],
  List<CourseHubWeek> weeks = const [],
  List<FeatureDetail> spocAssignments = const [],
  List<FeatureDetail> judgeAssignments = const [],
  List<FeatureDetail> exams = const [],
  List<FeatureDetail> grades = const [],
  Set<String> overrides = const {},
  bool judgeLinksAvailable = true,
  Map<CourseHubSource, CourseHubSourceStatus> sources = const {},
}) {
  final courses = <String, _Course>{};
  final kcid = <String, _Course>{};
  DateTime? start, end;
  var completeDates = true;
  if (graduate == false && termCode != null && termCode.isNotEmpty) {
    for (final week in weeks) {
      final begin = _instant(week.startDate),
          finish = _instant(week.endDate)?.add(const Duration(days: 1));
      if (begin == null || finish == null || !finish.isAfter(begin)) {
        completeDates = false;
        continue;
      }
      if (start == null || begin.isBefore(start)) start = begin;
      if (end == null || finish.isAfter(end)) end = finish;
      for (final detail in week.slots) {
        final slot = detail.presentation;
        if (slot is! ScheduleCoursePresentation || slot.courseCode.isEmpty)
          continue;
        final key = 'code:${slot.courseCode}';
        final course = courses.putIfAbsent(
          key,
          () => _Course(key, detail.title, slot.courseCode),
        );
        course.credit ??= slot.credit;
        course.slots.putIfAbsent((
          slot.dayOfWeek,
          slot.beginSection,
          slot.endSection,
          slot.place,
        ), () => detail);
        final day = slot.dayOfWeek, section = slot.beginSection ?? 999;
        if (day == null || day < 1 || day > 7) continue;
        if (day < course.first.$1 ||
            (day == course.first.$1 && section < course.first.$2))
          course.first = (day, section);
        final date = agendaDate(campusDate(begin.add(Duration(days: day - 1))));
        final opening = _instant('$date ${slot.beginTime}');
        if (opening != null &&
            opening.isAfter(now) &&
            (course.next == null || opening.isBefore(course.next!.start))) {
          course.next = (
            start: opening,
            end: _instant('$date ${slot.endTime}'),
            place: slot.place,
            beginSection: slot.beginSection,
            endSection: slot.endSection,
          );
        }
      }
    }
  }
  for (final entry in spocCourses) {
    final code = entry.courseCode;
    final key = (code == null || code.isEmpty)
        ? 'kcid:${entry.courseId}'
        : 'code:$code';
    final course = courses.putIfAbsent(
      key,
      () => _Course(key, entry.name, code),
    );
    course.spoc.add(entry);
    if (entry.teacher case final teacher? when teacher.isNotEmpty)
      course.teachers.add(teacher);
    kcid[entry.courseId] = course;
  }
  final all = <CourseHubAssignment>[];
  void add(FeatureId feature, FeatureDetail detail, _Course? course) {
    final item = CourseHubAssignment(
      feature: feature,
      detail: detail,
      courseKey: course?.key,
      courseName: course?.name,
    );
    all.add(item);
    course?.assignments.add(item);
  }

  for (final detail in spocAssignments) {
    final item = detail.presentation;
    if (item is SpocAssignmentPresentation && !item.isDetail)
      add(FeatureId.spoc, detail, kcid[item.courseId]);
  }
  final matches = <String, _Course>{};
  final eligible = <String, String>{};
  bool inTerm(String? raw) {
    if (!completeDates || !judgeLinksAvailable) return false;
    final instant = _instant(raw);
    return instant != null &&
        start != null &&
        end != null &&
        !instant.isBefore(start) &&
        instant.isBefore(end);
  }

  for (final detail in judgeAssignments) {
    final item = detail.presentation;
    if (item is JudgeAssignmentPresentation &&
        !item.isDetail &&
        item.courseId.isNotEmpty &&
        (inTerm(item.startTime) || inTerm(item.dueTime)))
      eligible[item.courseId] = item.courseName;
  }
  for (final entry in eligible.entries) {
    final name = _name(entry.value);
    if (name.isEmpty) continue;
    final course = courses.values
        .where((course) => _name(course.name) == name)
        .singleOrNull;
    if (course == null) continue;
    final linked = !overrides.contains(entry.key);
    course.links.add((
      judgeCourseId: entry.key,
      name: entry.value,
      linked: linked,
    ));
    if (linked) matches[entry.key] = course;
  }
  for (final detail in judgeAssignments) {
    final item = detail.presentation;
    if (item is JudgeAssignmentPresentation && !item.isDetail)
      add(FeatureId.judge, detail, matches[item.courseId]);
  }
  if (termCode != null) {
    for (final detail in exams) {
      final exam = detail.presentation;
      if (exam is ExamPresentation &&
          exam.requestTerm == termCode &&
          exam.courseNo != null)
        courses['code:${exam.courseNo}']?.exams.add(detail);
    }
    for (final detail in grades) {
      final grade = detail.presentation;
      if (grade is GradePresentation &&
          grade.termCode == termCode &&
          grade.courseCode != null)
        courses['code:${grade.courseCode}']?.grades.add(detail);
    }
  }
  final ordered = courses.values.toList()
    ..sort((left, right) {
      for (final delta in [
        right.slots.isNotEmpty.index - left.slots.isNotEmpty.index,
        left.first.$1 - right.first.$1,
        left.first.$2 - right.first.$2,
        left.name.compareTo(right.name),
      ]) {
        if (delta != 0) return delta;
      }
      return left.key.compareTo(right.key);
    });
  return CourseHubSnapshot(
    termCode: termCode,
    termName: termName,
    graduate: graduate,
    courses: List.unmodifiable(ordered.map((course) => course.freeze())),
    allAssignments: List.unmodifiable(all),
    sources: Map.unmodifiable({
      for (final source in CourseHubSource.values)
        source:
            sources[source] ??
            const CourseHubSourceStatus(CourseHubSourceState.notLoaded),
    }),
  );
}

extension on bool {
  int get index => this ? 1 : 0;
}

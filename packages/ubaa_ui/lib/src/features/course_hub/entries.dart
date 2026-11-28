import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

class CourseHubEntries extends InheritedWidget {
  const CourseHubEntries({
    required this.snapshot,
    required this.open,
    required this.term,
    required super.child,
  });
  final CourseHubSnapshot snapshot;
  final ValueChanged<String> open;
  final String? term;
  static Widget wrap(
    ValueListenable<CourseHubSnapshot>? source,
    String? term,
    Widget child,
    ValueChanged<String> open,
  ) {
    if (source == null) return child;
    return ValueListenableBuilder(
      valueListenable: source,
      child: child,
      builder: (_, snapshot, child) => CourseHubEntries(
        snapshot: snapshot,
        term: term,
        open: (key) {
          if (source.value.termCode == snapshot.termCode) open(key);
        },
        child: child!,
      ),
    );
  }

  static CourseHubEntries? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CourseHubEntries>();
  VoidCallback? schedule(String code, String? weekTerm) {
    if (snapshot.termCode == null || (weekTerm ?? term) != snapshot.termCode)
      return null;
    final course = snapshot.courses
        .where((item) => item.courseCode == code)
        .singleOrNull;
    return course == null ? null : () => open(course.key);
  }

  VoidCallback? group(List<FeatureDetail> details) {
    String? key;
    for (final detail in details) {
      final item = detail.presentation;
      final course = snapshot.courses
          .where(
            (course) => switch (item) {
              SpocAssignmentPresentation p => course.spocCourses.any(
                (entry) => entry.courseId == p.courseId,
              ),
              JudgeAssignmentPresentation p => course.judgeLinks.any(
                (entry) => entry.linked && entry.judgeCourseId == p.courseId,
              ),
              _ => false,
            },
          )
          .singleOrNull;
      if (course == null || (key != null && key != course.key)) return null;
      key = course.key;
    }
    return key == null ? null : () => open(key!);
  }

  @override
  bool updateShouldNotify(CourseHubEntries old) =>
      old.snapshot != snapshot || old.term != term || old.open != open;
}

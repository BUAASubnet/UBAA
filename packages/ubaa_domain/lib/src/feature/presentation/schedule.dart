part of '../presentation.dart';

final class TodayCoursePresentation extends FeaturePresentation {
  const TodayCoursePresentation({this.time, this.place});

  final String? time;
  final String? place;
}

final class TermPresentation extends FeaturePresentation {
  const TermPresentation({
    required this.code,
    required this.selected,
    required this.index,
  });

  final String code;
  final bool selected;
  final int index;
}

final class WeekPresentation extends FeaturePresentation {
  const WeekPresentation({
    required this.requestTerm,
    required this.responseTerm,
    required this.number,
    required this.current,
    required this.startDate,
    required this.endDate,
  });

  final String requestTerm;
  final String responseTerm;
  final int number;
  final bool current;
  final String startDate;
  final String endDate;
}

final class ScheduleCoursePresentation extends FeaturePresentation {
  const ScheduleCoursePresentation({
    required this.courseCode,
    this.courseSerialNo,
    this.credit,
    this.beginTime,
    this.endTime,
    this.beginSection,
    this.endSection,
    this.dayOfWeek,
    this.place,
    this.weeksAndTeachers,
    this.teachingTarget,
  });

  final String courseCode;
  final String? courseSerialNo;
  final String? credit;
  final String? beginTime;
  final String? endTime;
  final int? beginSection;
  final int? endSection;
  final int? dayOfWeek;
  final String? place;
  final String? weeksAndTeachers;
  final String? teachingTarget;
}

import '../../shared/schedule_values.dart' show uiWeekdays;
import '../../shared/academic_fields.dart' show AcademicInfo, AcademicMore;
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import '../../shared/schedule_values.dart' show uiScheduled;
import '../../shared/text.dart' show uiNonBlank, uiTimeRange;

List<Widget> uiCourseFields(ScheduleCoursePresentation course) => [
  if (uiScheduled(course))
    AcademicInfo(
      icon: Icons.calendar_view_week_outlined,
      text: uiWeekdays[course.dayOfWeek! - 1],
    ),
  if (uiScheduled(course))
    Chip(
      label: Text(
        course.beginSection == course.endSection
            ? '第${course.beginSection}节'
            : '第${course.beginSection}–${course.endSection}节',
      ),
    ),
  if (uiTimeRange(course.beginTime, course.endTime) case final time?)
    AcademicInfo(icon: Icons.schedule, text: time),
  AcademicInfo(
    icon: Icons.place_outlined,
    text: uiNonBlank(course.place) ?? '地点待公布',
  ),
  if (uiNonBlank(course.weeksAndTeachers) case final value?) Text(value),
  AcademicMore(
    fields: [
      if (uiNonBlank(course.credit) case final value?) ('学分', value),
      if (uiNonBlank(course.teachingTarget) case final value?) ('教学对象', value),
      if (!uiScheduled(course))
        if (_partialTime(course) case final value?) ('上课时间', value),
    ],
  ),
];

/// 课表无法排入周视图时，仍把能看懂的部分合成一行；越界数值不显示。
String? _partialTime(ScheduleCoursePresentation course) {
  final day = course.dayOfWeek, begin = course.beginSection;
  final end = course.endSection;
  final parts = [
    if (day != null && day >= 1 && day <= 7) uiWeekdays[day - 1],
    if (begin != null && begin > 0)
      end != null && end > begin ? '第$begin–$end节' : '第$begin节',
  ];
  return parts.isEmpty ? null : parts.join(' ');
}

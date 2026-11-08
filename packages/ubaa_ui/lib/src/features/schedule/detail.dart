import '../../shared/schedule_values.dart' show uiWeekdays;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../shared/dialogs/sheet.dart';

import '../../shared/text.dart'
    show uiHiddenAcademicField, uiNonBlank, uiTimeRange;

Future<void> uiShowScheduleGroup(
  BuildContext context,
  List<FeatureDetail> details,
) => showUiSheet<void>(
  context,
  builder: (context) => UiSheetBody(
    title: '同一时段的课程',
    subtitle: '${details.length}门课程',
    children: [
      for (final detail in details)
        if (detail.presentation case final ScheduleCoursePresentation p)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(detail.title),
            subtitle: Text(
              '第${p.beginSection}–${p.endSection}节 · ${uiNonBlank(p.place) ?? '地点待公布'}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => uiShowScheduleDetails(context, detail),
          ),
    ],
  ),
);

Future<void> uiShowScheduleDetails(BuildContext context, FeatureDetail detail) {
  final p = detail.presentation! as ScheduleCoursePresentation;
  // 「1周,4-6周[理论]/谭火彬[主讲]」拆成副标题里的周次和单独的教师行。
  final combined = uiNonBlank(p.weeksAndTeachers);
  final parts = combined?.split('/');
  final split =
      parts != null &&
      parts.length == 2 &&
      parts.first.contains('周') &&
      parts.every((part) => part.trim().isNotEmpty);
  final weeks = split ? parts.first.trim() : null;
  final teacher = split ? parts.last.trim() : combined;
  final place = uiNonBlank(p.place);
  // 上方已经显示的内容不再在附加字段里重复。
  final shown = {?place, ?combined, ?weeks, ?teacher};
  const shownLabels = {'时间', '地点', '周次', '教师', '周次/教师', '学分', '教学对象'};
  return showUiSheet<void>(
    context,
    builder: (context) => UiSheetBody(
      title: detail.title,
      subtitle: weeks,
      children: [
        // 星期、节次和时间合成一行，便于一眼看懂何时上课。
        if (_when(p) case final slot?)
          UiInfoRow(icon: Icons.schedule_outlined, text: slot),
        UiInfoRow(icon: Icons.place_outlined, text: place ?? '地点待公布'),
        if (teacher != null)
          UiInfoRow(icon: Icons.person_outline, text: teacher),
        if (uiNonBlank(p.credit) case final credit?)
          UiInfoRow(icon: Icons.school_outlined, text: '$credit 学分'),
        if (uiNonBlank(p.teachingTarget) case final target?)
          UiInfoRow(icon: Icons.groups_outlined, text: target, label: '教学对象'),
        for (final field in detail.fields)
          if (!uiHiddenAcademicField(field.label) &&
              !shownLabels.contains(field.label.trim()) &&
              field.value.trim().isNotEmpty &&
              !shown.contains(field.value.trim()))
            UiInfoRow(
              icon: Icons.info_outline,
              text: field.value,
              label: field.label,
            ),
      ],
    ),
  );
}

String? _when(ScheduleCoursePresentation p) {
  final day = p.dayOfWeek;
  final parts = [
    if (day != null && day >= 1 && day <= 7) uiWeekdays[day - 1],
    if (p.beginSection case final start?)
      p.endSection == null || p.endSection == start
          ? '第$start节'
          : '第$start–${p.endSection}节',
    ?uiTimeRange(p.beginTime, p.endTime),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

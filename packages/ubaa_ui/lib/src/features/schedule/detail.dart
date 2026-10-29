import '../../shared/schedule_values.dart' show uiWeekdays;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../common/detail_fields.dart' show DetailField;

import '../../shared/text.dart'
    show uiHiddenAcademicField, uiNonBlank, uiTimeRange;

Future<void> uiShowScheduleGroup(
  BuildContext context,
  List<FeatureDetail> details,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('同一时段的课程'),
    content: SizedBox(
      width: 560,
      height: MediaQuery.sizeOf(context).height * .6,
      child: ListView.builder(
        itemCount: details.length,
        itemBuilder: (context, index) {
          final detail = details[index];
          final p = detail.presentation! as ScheduleCoursePresentation;
          return ListTile(
            title: Text(detail.title),
            subtitle: Text(
              '第${p.beginSection}–${p.endSection}节 · ${uiNonBlank(p.place) ?? '地点待公布'}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => uiShowScheduleDetails(context, detail),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('关闭'),
      ),
    ],
  ),
);

Future<void> uiShowScheduleDetails(BuildContext context, FeatureDetail detail) {
  final p = detail.presentation! as ScheduleCoursePresentation;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(detail.title),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * .65,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final field in <(String, String)>[
                // 星期、节次和时间合成一行，便于一眼看懂何时上课。
                if (_when(p) case final slot?) ('时间', slot),
                ('地点', uiNonBlank(p.place) ?? '地点待公布'),
                if (uiNonBlank(p.credit) case final credit?) ('学分', credit),
                if (p.weeksAndTeachers != null) ('周次/教师', p.weeksAndTeachers!),
                if (p.teachingTarget != null) ('教学对象', p.teachingTarget!),
                for (final field in detail.fields)
                  if (!uiHiddenAcademicField(field.label))
                    (field.label, field.value),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DetailField(label: field.$1, value: field.$2),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
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

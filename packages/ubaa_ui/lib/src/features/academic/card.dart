import '../../shared/academic_fields.dart' show AcademicInfo, AcademicMore;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../common/detail_fields.dart' show DetailField;
import 'fields.dart' show uiCourseFields;
import '../../shared/text.dart' show uiNonBlank, uiTimeRange;

class AcademicCard extends StatelessWidget {
  const AcademicCard({required this.detail, this.onNavigate});
  final FeatureDetail detail;
  final Future<void> Function(FeatureReadNavigation)? onNavigate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final presentation = detail.presentation;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(detail.title, style: theme.textTheme.titleMedium),
            if (detail.subtitle case final subtitle?
                when subtitle.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(subtitle, style: theme.textTheme.bodySmall),
              ),
            const SizedBox(height: 12),
            ...switch (presentation) {
              TodayCoursePresentation p => [
                AcademicInfo(
                  icon: Icons.schedule,
                  text: uiNonBlank(p.time) ?? '时间待确认',
                ),
                AcademicInfo(
                  icon: Icons.place_outlined,
                  text: uiNonBlank(p.place) ?? '地点待公布',
                ),
              ],
              TermPresentation p => [
                if (p.selected) const Chip(label: Text('当前学期')),
                Text('学期编码 ${p.code}'),
              ],
              WeekPresentation p => [
                if (p.current) const Chip(label: Text('当前周')),
                Text('${p.startDate}–${p.endDate}'),
                Text('第${p.number}周'),
              ],
              ScheduleCoursePresentation p => uiCourseFields(p),
              ExamPresentation p => [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Chip(label: Text(p.arranged ? '已安排考试' : '未安排考试')),
                    if (uiNonBlank(p.type) case final type?)
                      Chip(label: Text(type)),
                  ],
                ),
                AcademicInfo(
                  icon: Icons.event_outlined,
                  text:
                      uiNonBlank(p.date) ??
                      uiNonBlank(p.description) ??
                      '时间待公布',
                ),
                if (uiTimeRange(p.startTime, p.endTime) case final time?)
                  AcademicInfo(icon: Icons.schedule, text: time),
                AcademicInfo(
                  icon: Icons.place_outlined,
                  text: uiNonBlank(p.place) ?? '地点待公布',
                ),
                if (uiNonBlank(p.seat) case final seat?)
                  AcademicInfo(
                    icon: Icons.event_seat_outlined,
                    text: '座位 $seat',
                  ),
                AcademicMore(
                  fields: [
                    if (uiNonBlank(p.description) case final value?)
                      ('考试说明', value),
                    if (uiNonBlank(p.courseNo) case final value?)
                      ('课程编号', value),
                    if (p.week case final value?) ('周次', '$value'),
                    if (p.status case final value?) ('上游状态', '$value'),
                    if (uiNonBlank(p.type) case final value?) ('考试类型', value),
                    if (uiNonBlank(p.taskId) case final value?) ('任务编号', value),
                    for (final field in detail.fields)
                      (field.label, field.value),
                  ],
                ),
              ],
              GradePresentation p => [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        uiNonBlank(p.score) ?? '待出成绩',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    if (p.credit case final value?)
                      Chip(label: Text('$value 学分')),
                  ],
                ),
                if (uiNonBlank(p.gradePoint) case final value?)
                  DetailField(label: '绩点', value: value),
                if (uiNonBlank(p.courseType) case final value?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(value),
                  ),
                AcademicMore(
                  fields: [
                    if (uiNonBlank(p.courseCode) case final value?)
                      ('课程编号', value),
                    if (uiNonBlank(p.termCode) case final value?) ('学期', value),
                    if (uiNonBlank(p.scoreType) case final value?)
                      ('成绩类型', value),
                    for (final field in detail.fields)
                      (field.label, field.value),
                  ],
                ),
              ],
              ClassroomPresentation p => [
                AcademicInfo(icon: Icons.layers_outlined, text: p.floorName),
                const SizedBox(height: 8),
                Text('可用节次', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                if (p.sectionTokens.isEmpty)
                  const Text('暂无可用节次信息')
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final section in p.sectionTokens)
                        Chip(label: Text('第$section节')),
                    ],
                  ),
              ],
              _ => [
                for (final field in detail.fields)
                  DetailField(label: field.label, value: field.value),
              ],
            },
            if (detail.readNavigation case final target?
                when onNavigate != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: FilledButton.tonalIcon(
                  onPressed: () => onNavigate!(target),
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(
                    presentation is TermPresentation ? '查看周次' : '查看周课表',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> uiShowAcademicDetails(
  BuildContext context,
  FeatureDetail detail,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('详细信息'),
    content: SizedBox(
      width: 560,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .65,
        ),
        child: SingleChildScrollView(child: AcademicCard(detail: detail)),
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

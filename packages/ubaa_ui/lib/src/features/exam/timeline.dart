import '../../shared/academic_fields.dart' show AcademicInfo;
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/theme.dart';
import '../academic/card.dart' show uiShowAcademicDetails;
import '../classroom/content.dart' show uiClassroomCampusName;
import '../../shared/text.dart' show uiNonBlank, uiTimeRange;

class ExamTimeline extends StatefulWidget {
  const ExamTimeline({required this.details});
  final List<FeatureDetail> details;
  @override
  State<ExamTimeline> createState() => _ExamTimelineState();
}

class _ExamTimelineState extends State<ExamTimeline> {
  bool _showFinished = false;
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final finished = <FeatureDetail>[];
    final upcoming = <FeatureDetail>[];
    final other = <FeatureDetail>[];
    for (final detail in widget.details) {
      final p = detail.presentation! as ExamPresentation;
      (p.arranged ? (p.isFinishedAt(now) ? finished : upcoming) : other).add(
        detail,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (upcoming.isNotEmpty) ...[
          _heading(context, '即将到来'),
          ..._groups(upcoming),
        ],
        if (other.isNotEmpty) ...[
          _heading(context, '未安排/其他'),
          for (final detail in other)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ExamCompactCard(detail: detail),
            ),
        ],
        if (finished.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12, top: 4),
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _showFinished = !_showFinished),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text('已结束考试 (${finished.length})')),
                      Icon(
                        _showFinished ? Icons.expand_less : Icons.expand_more,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_showFinished) ..._groups(finished, finished: true),
        ],
      ],
    );
  }

  Widget _heading(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 16, top: 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );

  List<Widget> _groups(List<FeatureDetail> items, {bool finished = false}) {
    final groups = <DateTime?, List<FeatureDetail>>{};
    for (final item in items) {
      final date = (item.presentation! as ExamPresentation).calendarDate;
      groups.putIfAbsent(date, () => []).add(item);
    }
    final dates = groups.keys.toList()
      ..sort((a, b) {
        if (a == null) return b == null ? 0 : 1;
        if (b == null) return -1;
        return finished ? b.compareTo(a) : a.compareTo(b);
      });
    return [
      for (final date in dates)
        for (final (index, detail) in groups[date]!.indexed)
          _ExamTimelineRow(
            detail: detail,
            date: date,
            showDate: index == 0,
            finished: finished,
          ),
    ];
  }
}

class _ExamTimelineRow extends StatelessWidget {
  const _ExamTimelineRow({
    required this.detail,
    required this.date,
    required this.showDate,
    required this.finished,
  });
  final FeatureDetail detail;
  final DateTime? date;
  final bool showDate;
  final bool finished;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = finished ? colors.outline : colors.primary;
    final d = date;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 60,
            child: Column(
              children: [
                if (showDate) ...[
                  Text(
                    d == null
                        ? '待定'
                        : '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (d != null)
                    Text(
                      _examDayHint(d, finished),
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: color),
                    ),
                ],
                const SizedBox(height: 8),
                Icon(Icons.circle, size: 8, color: color),
                const SizedBox(height: 4),
                Expanded(
                  child: VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: color.withValues(alpha: .3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ExamCompactCard(detail: detail, finished: finished),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExamCompactCard extends StatelessWidget {
  const _ExamCompactCard({required this.detail, this.finished = false});
  final FeatureDetail detail;
  final bool finished;
  @override
  Widget build(BuildContext context) {
    final p = detail.presentation! as ExamPresentation;
    final theme = Theme.of(context);
    return Card.outlined(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UbaaTheme.cardRadius),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      color: finished ? theme.colorScheme.surface : null,
      child: InkWell(
        onTap: () => uiShowAcademicDetails(context, detail),
        borderRadius: BorderRadius.circular(UbaaTheme.cardRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      detail.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: finished
                            ? theme.colorScheme.onSurfaceVariant
                            : null,
                      ),
                    ),
                  ),
                  if (p.arranged && uiNonBlank(p.seat) != null) ...[
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: finished
                              ? theme.colorScheme.surfaceContainerHigh
                              : theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '座位 ${p.seat}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: finished
                                ? theme.colorScheme.onSurfaceVariant
                                : theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              // 时间与考场合为一行，卡片更紧凑。
              AcademicInfo(
                icon: Icons.schedule,
                text: [
                  uiTimeRange(p.startTime, p.endTime) ??
                      uiNonBlank(p.description) ??
                      '时间待公布',
                  ?uiNonBlank(p.place),
                ].join(' · '),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 低频公开投影移入详情后仍可检索，不读取上游原始响应。
Iterable<String> uiAcademicSearchValues(FeaturePresentation? p) => switch (p) {
  ScheduleCoursePresentation p => [
    p.courseCode,
    p.courseSerialNo,
    p.credit,
    p.beginTime,
    p.endTime,
    p.beginSection?.toString(),
    p.endSection?.toString(),
    p.dayOfWeek?.toString(),
    p.place,
    p.weeksAndTeachers,
    p.teachingTarget,
  ].whereType<String>(),
  ClassroomPresentation p => [
    p.roomId,
    p.floorId,
    p.floorName,
    p.availableSections,
    p.queryDate,
    p.campus?.toString(),
    if (p.campus case final campus?) uiClassroomCampusName(campus),
  ].whereType<String>(),
  GradePresentation p => [
    p.courseName,
    p.courseCode,
    p.score,
    p.gradePoint,
    p.credit?.toString(),
    p.courseType,
    p.scoreType,
    p.termCode,
  ].whereType<String>(),
  ExamPresentation p => [
    p.courseNo,
    p.date,
    p.description,
    p.startTime,
    p.endTime,
    p.place,
    p.seat,
    p.week?.toString(),
    p.status?.toString(),
    p.type,
    p.taskId,
  ].whereType<String>(),
  SigninPresentation p => [
    p.courseId,
    p.classBeginTime,
    p.classEndTime,
    p.signStatus?.toString(),
  ].whereType<String>(),
  _ => const [],
};

/// 日期下的星期与倒计时，分两行显示，例如“周五/明天”。
String _examDayHint(DateTime date, bool finished) {
  const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  final now = homeCampusTime(clock.now());
  final days = DateTime(
    date.year,
    date.month,
    date.day,
  ).difference(DateTime(now.year, now.month, now.day)).inDays;
  final relative = finished || days < 0
      ? null
      : switch (days) {
          0 => '今天',
          1 => '明天',
          2 => '后天',
          _ => '$days天后',
        };
  return [weekdays[date.weekday - 1], ?relative].join('\n');
}

import 'package:clock/clock.dart';
import '../../shared/academic_fields.dart' show AcademicInfo;
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/theme.dart';
import '../academic/card.dart' show uiShowAcademicDetails;
import '../classroom/content.dart' show uiClassroomCampusName;
import '../../shared/text.dart' show uiNonBlank, uiTimeRange;
import '../../common/section.dart' show UiSectionTitle;

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
    final now = clock.now();
    final finished = <FeatureDetail>[];
    final upcoming = <FeatureDetail>[];
    final other = <FeatureDetail>[];
    for (final detail in widget.details) {
      final p = detail.presentation! as ExamPresentation;
      (p.arranged ? (p.isFinishedAt(now) ? finished : upcoming) : other).add(
        detail,
      );
    }
    final rows = <WidgetBuilder>[
      if (upcoming.isNotEmpty) ...[
        (context) => _heading(context, '即将到来'),
        ..._groups(upcoming),
      ],
      if (other.isNotEmpty) ...[
        (context) => _heading(context, '未安排'),
        for (final detail in other)
          (context) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ExamCompactCard(detail: detail),
          ),
      ],
      if (finished.isNotEmpty) ...[
        if (upcoming.isEmpty)
          (context) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ExamOutlinedCard(
              child: ListTile(
                leading: const Icon(Icons.event_available_outlined),
                title: const Text('暂无即将进行的考试'),
              ),
            ),
          ),
        (context) => Padding(
          padding: const EdgeInsets.only(bottom: 12, top: 4),
          child: _ExamOutlinedCard(
            child: ListTile(
              onTap: () => setState(() => _showFinished = !_showFinished),
              leading: const Icon(Icons.history),
              title: Text('已结束考试 (${finished.length})'),
              trailing: Icon(
                _showFinished ? Icons.expand_less : Icons.expand_more,
              ),
            ),
          ),
        ),
        if (_showFinished) ..._groups(finished, finished: true),
      ],
    ];
    return ListView.builder(
      padding: UbaaTheme.pageInsets(context, top: 8),
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index](context),
    );
  }

  Widget _heading(BuildContext context, String text) => UiSectionTitle(text);

  List<WidgetBuilder> _groups(
    List<FeatureDetail> items, {
    bool finished = false,
  }) {
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
          (context) => _ExamTimelineRow(
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
                    d == null ? '待定' : '${d.month}月${d.day}日',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w500,
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

/// 与考试卡片一致的描边卡片，用于分组入口和提示行。
class _ExamOutlinedCard extends StatelessWidget {
  const _ExamOutlinedCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card.outlined(
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(UbaaTheme.cardRadius),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: child,
  );
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
                        fontWeight: FontWeight.w500,
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
                            fontWeight: FontWeight.w500,
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
                      '时间待定',
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

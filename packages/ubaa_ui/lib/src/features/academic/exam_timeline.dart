part of '../../widgets.dart';

class _ExamTimeline extends StatefulWidget {
  const _ExamTimeline({required this.details});
  final List<FeatureDetail> details;
  @override
  State<_ExamTimeline> createState() => _ExamTimelineState();
}

class _ExamTimelineState extends State<_ExamTimeline> {
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
        if (finished.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
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
                if (showDate)
                  Text(
                    d == null
                        ? '待定'
                        : '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: color),
                  ),
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
        onTap: () => _showAcademicDetails(context, detail),
        borderRadius: BorderRadius.circular(UbaaTheme.cardRadius),
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                  if (p.arranged && _nonBlank(p.seat) != null) ...[
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Text(
                        '座位 ${p.seat}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              _AcademicInfo(
                icon: Icons.schedule,
                text:
                    _timeRange(p.startTime, p.endTime) ??
                    _nonBlank(p.description) ??
                    '时间待公布',
              ),
              if (_nonBlank(p.place) case final place?) ...[
                const SizedBox(height: 6),
                _AcademicInfo(icon: Icons.place_outlined, text: place),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 低频公开投影移入详情后仍可检索，不读取上游原始响应。
Iterable<String> _academicSearchValues(FeaturePresentation? p) => switch (p) {
  ClassroomPresentation p => [
    p.roomId,
    p.floorId,
    p.floorName,
    p.availableSections,
    p.queryDate,
    p.campus?.toString(),
    if (p.campus case final campus?) _classroomCampusName(campus),
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

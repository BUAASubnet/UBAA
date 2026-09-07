part of '../widgets.dart';

/// 学业内容直接消费 typed 展示模型；本地展开不会发起业务读取。
class _AcademicResultContent extends StatelessWidget {
  const _AcademicResultContent({
    required this.feature,
    required this.details,
    this.onNavigate,
  });
  final FeatureId feature;
  final List<FeatureDetail> details;
  final Future<void> Function(FeatureReadNavigation)? onNavigate;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final weekly =
          feature == FeatureId.schedule &&
          details.every(
            (detail) => detail.presentation is ScheduleCoursePresentation,
          );
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (weekly)
            _ScheduleContent(
              details: details,
              wide: constraints.maxWidth >= 740,
            )
          else if (feature == FeatureId.grades && constraints.maxWidth >= 740)
            _GradeTable(details: details)
          else
            for (final detail in details)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _AcademicCard(detail: detail, onNavigate: onNavigate),
              ),
        ],
      );
    },
  );
}

class _AcademicCard extends StatelessWidget {
  const _AcademicCard({required this.detail, this.onNavigate});
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
                _AcademicInfo(
                  icon: Icons.schedule,
                  text: _nonBlank(p.time) ?? '时间待确认',
                ),
                _AcademicInfo(
                  icon: Icons.place_outlined,
                  text: _nonBlank(p.place) ?? '地点待公布',
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
              ScheduleCoursePresentation p => _courseFields(p),
              ExamPresentation p => [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Chip(label: Text(p.arranged ? '已安排考试' : '未安排考试')),
                    if (_nonBlank(p.type) case final type?)
                      Chip(label: Text(type)),
                  ],
                ),
                _AcademicInfo(
                  icon: Icons.event_outlined,
                  text:
                      _nonBlank(p.date) ?? _nonBlank(p.description) ?? '时间待公布',
                ),
                if (_timeRange(p.startTime, p.endTime) case final time?)
                  _AcademicInfo(icon: Icons.schedule, text: time),
                _AcademicInfo(
                  icon: Icons.place_outlined,
                  text: _nonBlank(p.place) ?? '地点待公布',
                ),
                if (_nonBlank(p.seat) case final seat?)
                  _AcademicInfo(
                    icon: Icons.event_seat_outlined,
                    text: '座位 $seat',
                  ),
                _AcademicMore(
                  fields: [
                    if (_nonBlank(p.description) case final value?)
                      ('考试说明', value),
                    if (_nonBlank(p.courseNo) case final value?)
                      ('课程编号', value),
                    if (p.week case final value?) ('周次', '$value'),
                    if (p.status case final value?) ('上游状态', '$value'),
                  ],
                ),
              ],
              GradePresentation p => [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        _nonBlank(p.score) ?? '待出成绩',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    if (p.credit case final value?)
                      Chip(label: Text('$value 学分')),
                  ],
                ),
                if (_nonBlank(p.gradePoint) case final value?)
                  _DetailField(label: '绩点', value: value),
                if (_nonBlank(p.courseType) case final value?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(value),
                  ),
                _AcademicMore(
                  fields: [
                    if (_nonBlank(p.courseCode) case final value?)
                      ('课程编号', value),
                    if (_nonBlank(p.termCode) case final value?) ('学期', value),
                    if (_nonBlank(p.scoreType) case final value?)
                      ('成绩类型', value),
                  ],
                ),
              ],
              ClassroomPresentation p => [
                _AcademicInfo(icon: Icons.layers_outlined, text: p.floorName),
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
                  _DetailField(label: field.label, value: field.value),
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

class _AcademicInfo extends StatelessWidget {
  const _AcademicInfo({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _AcademicMore extends StatelessWidget {
  const _AcademicMore({required this.fields});
  final List<(String, String)> fields;
  @override
  Widget build(BuildContext context) => fields.isEmpty
      ? const SizedBox.shrink()
      : ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('更多信息'),
          children: [
            for (final (label, value) in fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _DetailField(label: label, value: value),
              ),
          ],
        );
}

class _GradeTable extends StatelessWidget {
  const _GradeTable({required this.details});
  final List<FeatureDetail> details;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('课程成绩 · 按原查询顺序展示；横向滚动查看全部列'),
      const SizedBox(height: 8),
      Card(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            dataRowMinHeight: 56,
            dataRowMaxHeight: double.infinity,
            columns: [
              for (final label in [
                '课程',
                '成绩',
                '绩点',
                '学分',
                '课程类型',
                '成绩类型',
                '学期',
              ])
                DataColumn(label: Text(label)),
            ],
            rows: [
              for (final detail in details)
                if (detail.presentation case final GradePresentation grade)
                  DataRow(
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 220,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(detail.title),
                                if (_nonBlank(grade.courseCode) ??
                                        _nonBlank(detail.subtitle)
                                    case final code?)
                                  Text(
                                    code,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      DataCell(Text(_nonBlank(grade.score) ?? '待出成绩')),
                      DataCell(Text(_nonBlank(grade.gradePoint) ?? '—')),
                      DataCell(Text(grade.credit?.toString() ?? '—')),
                      DataCell(Text(_nonBlank(grade.courseType) ?? '—')),
                      DataCell(Text(_nonBlank(grade.scoreType) ?? '—')),
                      DataCell(Text(_nonBlank(grade.termCode) ?? '—')),
                    ],
                  ),
            ],
          ),
        ),
      ),
    ],
  );
}

String? _nonBlank(String? value) =>
    value == null || value.trim().isEmpty ? null : value;
String? _timeRange(String? start, String? end) {
  final first = _nonBlank(start);
  final last = _nonBlank(end);
  if (first != null && last != null) return '$first–$last';
  if (first != null) return '$first 开始';
  if (last != null) return '$last 结束';
  return null;
}

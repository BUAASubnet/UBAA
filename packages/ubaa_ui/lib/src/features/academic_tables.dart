part of '../widgets.dart';

class _AcademicGroupedResults extends StatelessWidget {
  const _AcademicGroupedResults({
    required this.feature,
    required this.details,
    required this.wide,
  });
  final FeatureId feature;
  final List<FeatureDetail> details;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    bool primary(FeatureDetail detail) => switch (detail.presentation) {
      ExamPresentation p => p.arranged,
      GradePresentation p => _nonBlank(p.score) != null,
      _ => false,
    };
    final groups = [
      (
        feature == FeatureId.exam ? '已安排考试' : '已出成绩',
        details.where(primary).toList(),
      ),
      (
        feature == FeatureId.exam ? '未安排考试' : '待出成绩',
        details.where((d) => !primary(d)).toList(),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (label, items) in groups)
          if (items.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '$label · 本页${items.length}门',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            if (wide)
              _AcademicTable(feature: feature, details: items)
            else
              for (final detail in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _AcademicCard(detail: detail),
                ),
            const SizedBox(height: 16),
          ],
      ],
    );
  }
}

/// 主要列始终在当前视口内，完整字段由本地详情打开；不让课程标识滚出屏幕。
class _AcademicTable extends StatelessWidget {
  const _AcademicTable({required this.feature, required this.details});
  final FeatureId feature;
  final List<FeatureDetail> details;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final exam = feature == FeatureId.exam;
      final available = constraints.maxWidth - 72;
      final weights = exam ? [.40, .28, .22, .10] : [.50, .18, .18, .14];
      final widths = [for (final weight in weights) available * weight];
      final labels = exam
          ? ['课程（详情）', '日期 / 时间', '地点', '座位']
          : ['课程（详情）', '成绩', '绩点', '学分'];
      Widget cell(int index, Widget child) => SizedBox(
        width: widths[index],
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: child,
        ),
      );
      return Card(
        margin: EdgeInsets.zero,
        child: DataTable(
          horizontalMargin: 12,
          columnSpacing: 16,
          showCheckboxColumn: false,
          dataRowMinHeight: 56,
          dataRowMaxHeight: double.infinity,
          columns: [for (final label in labels) DataColumn(label: Text(label))],
          rows: [
            for (final detail in details)
              DataRow(
                cells: [
                  DataCell(
                    cell(
                      0,
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            detail.title,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                          ),
                          if (_courseCode(detail) case final code?)
                            Text(
                              code,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    onTap: () => _showAcademicDetails(context, detail),
                  ),
                  ...switch (detail.presentation) {
                    GradePresentation p => [
                      DataCell(cell(1, Text(_nonBlank(p.score) ?? '待出成绩'))),
                      DataCell(cell(2, Text(_nonBlank(p.gradePoint) ?? '—'))),
                      DataCell(cell(3, Text(p.credit?.toString() ?? '—'))),
                    ],
                    ExamPresentation p => [
                      DataCell(
                        cell(
                          1,
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _nonBlank(p.date) ??
                                    _nonBlank(p.description) ??
                                    '时间待公布',
                              ),
                              if (_timeRange(p.startTime, p.endTime)
                                  case final time?)
                                Text(time),
                            ],
                          ),
                        ),
                      ),
                      DataCell(cell(2, Text(_nonBlank(p.place) ?? '地点待公布'))),
                      DataCell(cell(3, Text(_nonBlank(p.seat) ?? '—'))),
                    ],
                    _ => [
                      for (var i = 1; i < 4; i++)
                        DataCell(cell(i, const Text('—'))),
                    ],
                  },
                ],
              ),
          ],
        ),
      );
    },
  );
}

String? _courseCode(FeatureDetail detail) => switch (detail.presentation) {
  GradePresentation p => _nonBlank(p.courseCode) ?? _nonBlank(detail.subtitle),
  ExamPresentation p => _nonBlank(p.courseNo),
  _ => _nonBlank(detail.subtitle),
};

Future<void> _showAcademicDetails(BuildContext context, FeatureDetail detail) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('详细信息'),
        content: SizedBox(
          width: 560,
          height: MediaQuery.sizeOf(context).height * .6,
          child: SingleChildScrollView(child: _AcademicCard(detail: detail)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );

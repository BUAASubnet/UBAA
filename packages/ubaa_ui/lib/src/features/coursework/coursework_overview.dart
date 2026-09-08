part of '../../widgets.dart';

class _CourseworkOverview extends StatelessWidget {
  const _CourseworkOverview({required this.overview});
  final FeatureOverview overview;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: SizedBox(
      width: double.infinity,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: switch (overview) {
            YgdkOverview p => _YgdkSummary(p),
            EvaluationProgressOverview p => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('评教进度', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    Text('已评 ${p.evaluatedCourses} / ${p.totalCourses} 门'),
                    Text('待评 ${p.pendingCourses} 门'),
                  ],
                ),
                if (p.totalCourses > 0 &&
                    p.evaluatedCourses >= 0 &&
                    p.evaluatedCourses <= p.totalCourses)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(
                      value: p.evaluatedCourses / p.totalCourses,
                    ),
                  ),
              ],
            ),
            SpocTermOverview p => Text(
              '学期：${_nonBlank(p.termName) ?? _nonBlank(p.termCode) ?? '未提供'}${_nonBlank(p.termName) != null && _nonBlank(p.termCode) != null ? '（${p.termCode}）' : ''}',
            ),
          },
        ),
      ),
    ),
  );
}

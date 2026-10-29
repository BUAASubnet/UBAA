import 'package:ubaa_ui/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../ygdk/summary.dart' show YgdkSummary;
import '../../shared/text.dart' show uiNonBlank;

class CourseworkOverview extends StatelessWidget {
  const CourseworkOverview({required this.overview, this.complete = true});
  final bool complete;
  final FeatureOverview overview;
  @override
  Widget build(BuildContext context) => Padding(
    padding: UbaaTheme.pageInsets(context, top: 12, bottom: 0),
    child: SizedBox(
      width: double.infinity,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: switch (overview) {
            BykcChosenOverview p => Text(
              '已选查询范围 ${p.semesterStart} 至 ${p.semesterEnd}',
            ),
            YgdkOverview p => YgdkSummary(p),
            // 成绩概要由成绩页随列表滚动，不进入常驻概要卡。
            HomeScheduleOverview _ => const SizedBox.shrink(),
            ScheduleWeekOverview _ => const SizedBox.shrink(),
            GradesTermOverview _ => const SizedBox.shrink(),
            EvaluationProgressOverview p => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('评教进度', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                if (complete)
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      Text('已评 ${p.evaluatedCourses} / ${p.totalCourses} 门'),
                      Text('待评 ${p.pendingCourses} 门'),
                    ],
                  ),
                if (complete &&
                    p.totalCourses > 0 &&
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
              '学期：${uiNonBlank(p.termName) ?? uiNonBlank(p.termCode) ?? '未提供'}${uiNonBlank(p.termName) != null && uiNonBlank(p.termCode) != null ? '（${p.termCode}）' : ''}',
            ),
          },
        ),
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import '../../common/state_panel.dart' show UiInlineRetry;
import '../../shared/refresh.dart' show PullToRefresh;
import '../../shared/text.dart' show uiNonBlank;
import '../../shared/when.dart' show uiCampusNow;
import '../../theme.dart' show UbaaTheme;
import '../coursework/assignment_content.dart' show AssignmentCard;
import 'course_format.dart';

/// 全部作业：SPOC 与希冀跨课程平铺，按截止时间排；可按课程筛选。
/// 已截止未交、已提交两组折叠在后；来源不全时提示，不误报“没有作业”。
class CourseHubAssignmentsPage extends StatefulWidget {
  const CourseHubAssignmentsPage({
    super.key,
    required this.snapshot,
    required this.onOpenAssignment,
    this.onRefresh,
  });
  final CourseHubSnapshot snapshot;
  final ValueChanged<FeatureReadNavigation> onOpenAssignment;
  final Future<void> Function()? onRefresh;

  @override
  State<CourseHubAssignmentsPage> createState() =>
      _CourseHubAssignmentsPageState();
}

class _CourseHubAssignmentsPageState extends State<CourseHubAssignmentsPage> {
  String? _course; // null = 全部课程

  @override
  Widget build(BuildContext context) {
    final hub = widget.snapshot;
    final now = uiCampusNow();
    final theme = Theme.of(context);
    final all = [...hub.allAssignments]
      ..sort((a, b) => courseHubByDue(a.detail, b.detail));
    // 课程名优先用课程中心里的名字，对不上的沿用作业自带的课程名。
    String courseOf(CourseHubAssignment a) =>
        a.courseName ??
        (uiNonBlank(courseHubAssignmentCourse(a.detail)) ?? '其他');
    final courses = <String>{for (final a in all) courseOf(a)}.toList();
    final visible = [
      for (final a in all)
        if (_course == null || courseOf(a) == _course) a,
    ];
    final pending = <CourseHubAssignment>[];
    final overdue = <CourseHubAssignment>[];
    final other = <CourseHubAssignment>[];
    for (final a in visible) {
      switch (courseHubBucket(a.detail, now)) {
        case CourseHubBucket.pending:
          pending.add(a);
        case CourseHubBucket.overdue:
          overdue.add(a);
        case CourseHubBucket.other:
          other.add(a);
      }
    }
    bool complete(CourseHubSource source) =>
        switch (hub.sources[source]?.state) {
          CourseHubSourceState.ready ||
          CourseHubSourceState.notApplicable => true,
          _ => false,
        };
    final missing = [
      if (!complete(CourseHubSource.spocAssignments)) 'SPOC 作业',
      if (!complete(CourseHubSource.judgeAssignments)) '希冀作业',
    ];
    final wide = MediaQuery.sizeOf(context).width >= 740;
    Widget item(CourseHubAssignment a) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              '${courseOf(a)} · ${a.feature == FeatureId.spoc ? 'SPOC' : '希冀'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          AssignmentCard(
            detail: a.detail,
            wide: wide,
            onNavigate: (target) async => widget.onOpenAssignment(target),
          ),
        ],
      ),
    );
    return PullToRefresh(
      onRefresh: widget.onRefresh ?? () async {},
      child: ListView(
        key: const ValueKey('course-hub-all-assignments'),
        padding: UbaaTheme.pageInsets(context, top: 8, bottom: 24),
        children: [
          if (courses.length > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final name in [null, ...courses])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(name ?? '全部课程'),
                        selected: _course == name,
                        onSelected: (_) => setState(() => _course = name),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          if (missing.isNotEmpty) ...[
            UiInlineRetry(
              message: '${missing.join('、')}未加载完整',
              onRetry: widget.onRefresh == null
                  ? null
                  : () => widget.onRefresh!(),
            ),
            const SizedBox(height: 12),
          ],
          ...pending.map(item),
          if (pending.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                missing.isEmpty ? '没有待交作业' : '已加载的作业里没有待交项',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (overdue.isNotEmpty)
            _Collapsed(
              title: '已截止未交',
              count: overdue.length,
              children: overdue.map(item).toList(),
            ),
          if (other.isNotEmpty)
            _Collapsed(
              title: '已提交与其他',
              count: other.length,
              children: other.map(item).toList(),
            ),
        ],
      ),
    );
  }
}

class _Collapsed extends StatelessWidget {
  const _Collapsed({
    required this.title,
    required this.count,
    required this.children,
  });
  final String title;
  final int count;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      title: Text('$title（$count）'),
      children: children,
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import '../../common/section.dart'
    show UiEntryCard, UiEntryList, UiSectionHeader;
import '../../shared/feature_icons.dart' show uiFeatureIcon;
import '../../shared/loading.dart' show LoadingPlaceholder;
import '../../shared/refresh.dart' show PullToRefresh;
import '../../shared/when.dart' show uiCampusNow;
import '../../theme.dart' show UbaaTheme;
import '../schedule/colors.dart' show ScheduleCourseColors;
import 'course_format.dart';

/// 学习页：上面是四个跨课程入口，中间按课程列出本学期，下面是学业与来源兜底。
class CourseHubLanding extends StatelessWidget {
  const CourseHubLanding({
    super.key,
    required this.snapshot,
    required this.onOpenFeature,
    required this.onOpenCourse,
    required this.onOpenAssignments,
    required this.onOpenSources,
    required this.onRefresh,
  });
  final CourseHubSnapshot snapshot;
  final ValueChanged<FeatureId> onOpenFeature;
  final ValueChanged<String> onOpenCourse;
  final VoidCallback onOpenAssignments, onOpenSources;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final hub = snapshot;
    final now = uiCampusNow();
    return PullToRefresh(
      onRefresh: onRefresh,
      child: ListView(
        key: const ValueKey('course-hub-landing'),
        padding: UbaaTheme.pageInsets(context, top: 8, bottom: 24),
        children: [
          _QuickRow(
            onSchedule: () => onOpenFeature(FeatureId.schedule),
            onAssignments: onOpenAssignments,
            onExam: () => onOpenFeature(FeatureId.exam),
            onGrades: () => onOpenFeature(FeatureId.grades),
            pending: _pendingTotal(hub, now),
          ),
          const SizedBox(height: 20),
          UiSectionHeader(title: '本学期课程', subtitle: hub.termName),
          ..._warnings(context, hub),
          if (hub.courses.isEmpty && _loading(hub))
            const LoadingPlaceholder(compact: true)
          else if (hub.courses.isEmpty)
            const _EmptyCourses()
          else
            UiEntryList(
              // 课程行自己画分隔，固定单列分组，宽屏也不拆成无边框的网格。
              maxColumns: 1,
              children: [
                for (final course in _ordered(hub.courses))
                  _CourseRow(
                    course: course,
                    now: now,
                    complete: _assignmentsComplete(hub),
                    onTap: () => onOpenCourse(course.key),
                  ),
              ],
            ),
          const SizedBox(height: 24),
          const UiSectionHeader(title: '学业'),
          UiEntryList(
            children: [
              UiEntryCard(
                title: FeatureId.bykc.title,
                icon: uiFeatureIcon(FeatureId.bykc),
                subtitle: '选课、已选课程与修读统计',
                onTap: () => onOpenFeature(FeatureId.bykc),
              ),
              UiEntryCard(
                title: FeatureId.evaluation.title,
                icon: uiFeatureIcon(FeatureId.evaluation),
                subtitle: FeatureId.evaluation.description,
                onTap: () => onOpenFeature(FeatureId.evaluation),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 按学校系统找内容的兜底入口，不属于学业，单独一行放在最后。
          UiEntryList(
            children: [
              UiEntryCard(
                key: const ValueKey('course-hub-open-sources'),
                title: '按来源浏览',
                icon: Icons.folder_open_outlined,
                subtitle: 'SPOC 作业、希冀作业、每日课程',
                onTap: onOpenSources,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 还在上的课按每周顺序排在前面，已结课的其次，没有排课的放最后；
  /// 各段内保持课程中心给出的顺序，整周稳定。
  static List<CourseHubCourse> _ordered(List<CourseHubCourse> courses) => [
    for (final c in courses)
      if (c.nextClass != null) c,
    for (final c in courses)
      if (c.nextClass == null && c.scheduleLinked) c,
    for (final c in courses)
      if (!c.scheduleLinked) c,
  ];

  /// 还没读到任何来源（启动时）或仍在读取时显示占位，不先说“没有课程”。
  static bool _loading(CourseHubSnapshot hub) =>
      hub.sources.isEmpty ||
      hub.sources.values.any(
        (s) =>
            s.state == CourseHubSourceState.loading ||
            s.state == CourseHubSourceState.notLoaded,
      );

  static bool _assignmentsComplete(CourseHubSnapshot hub) =>
      [
        CourseHubSource.spocCourses,
        CourseHubSource.spocAssignments,
        CourseHubSource.judgeAssignments,
      ].every(
        (s) => switch (hub.sources[s]?.state) {
          CourseHubSourceState.ready ||
          CourseHubSourceState.notApplicable => true,
          _ => false,
        },
      );

  /// 跨课程的待交总数；来源不全时返回 null，入口上不显示数字。
  static int? _pendingTotal(CourseHubSnapshot hub, DateTime now) {
    if (!_assignmentsComplete(hub)) return null;
    var count = 0;
    for (final course in hub.courses) {
      count += course.assignments
          .where(
            (a) => courseHubBucket(a.detail, now) == CourseHubBucket.pending,
          )
          .length;
    }
    return count;
  }

  List<Widget> _warnings(BuildContext context, CourseHubSnapshot hub) {
    final failed = [
      for (final entry in hub.sources.entries)
        if (entry.value.state == CourseHubSourceState.failed) entry.key,
    ];
    if (failed.isEmpty) return const [];
    return [
      _SourceWarning(
        message: '${failed.map(_label).join('、')}暂未加载，课程信息可能不全',
        onRetry: onRefresh,
      ),
      const SizedBox(height: 12),
    ];
  }

  static String _label(CourseHubSource source) => switch (source) {
    CourseHubSource.schedule => '课表',
    CourseHubSource.spocCourses => 'SPOC 课程',
    CourseHubSource.spocAssignments => 'SPOC 作业',
    CourseHubSource.judgeAssignments => '希冀作业',
    CourseHubSource.exams => '考试',
    CourseHubSource.grades => '成绩',
  };
}

/// 四个跨课程入口，与首页快捷入口同一造型。
class _QuickRow extends StatelessWidget {
  const _QuickRow({
    required this.onSchedule,
    required this.onAssignments,
    required this.onExam,
    required this.onGrades,
    this.pending,
  });
  final VoidCallback onSchedule, onAssignments, onExam, onGrades;
  final int? pending;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _QuickTile(
        key: const ValueKey('course-hub-quick-schedule'),
        label: '课表',
        icon: uiFeatureIcon(FeatureId.schedule),
        onTap: onSchedule,
      ),
      _QuickTile(
        key: const ValueKey('course-hub-quick-assignments'),
        label: '作业',
        icon: Icons.edit_note,
        badge: pending == null || pending == 0 ? null : '$pending',
        onTap: onAssignments,
      ),
      _QuickTile(
        key: const ValueKey('course-hub-quick-exam'),
        label: '考试',
        icon: uiFeatureIcon(FeatureId.exam),
        onTap: onExam,
      ),
      _QuickTile(
        key: const ValueKey('course-hub-quick-grades'),
        label: '成绩',
        icon: uiFeatureIcon(FeatureId.grades),
        onTap: onGrades,
      ),
    ],
  );
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.badge,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Expanded(
      child: Semantics(
        button: true,
        label: badge == null ? label : '$label，$badge 项待交',
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(UbaaTheme.controlRadius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            child: Column(
              children: [
                Badge(
                  isLabelVisible: badge != null,
                  label: badge == null ? null : Text(badge!),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, size: 22, color: scheme.primary),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 一门课：课表同色的色条、课程名、下次上课；有待交时右侧显示数量。
class _CourseRow extends StatelessWidget {
  const _CourseRow({
    required this.course,
    required this.now,
    required this.complete,
    required this.onTap,
  });
  final CourseHubCourse course;
  final DateTime now;
  final bool complete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pending = course.assignments
        .where((a) => courseHubBucket(a.detail, now) == CourseHubBucket.pending)
        .length;
    final next = course.nextClass;
    final subtitle = next != null
        ? [courseHubWhen(next.start, now), ?next.place].join(' · ')
        : course.scheduleLinked
        ? '本学期没有后续排课'
        : '未关联课表';
    // 来源不全时数量只是已知部分，写成“已知 N 项”，不让 0 冒充“没有作业”。
    final badge = pending == 0
        ? null
        : complete
        ? '$pending 项待交'
        : '已知 $pending 项待交';
    final accent = course.scheduleLinked
        ? ScheduleCourseColors.accent(course.name, theme.brightness)
        : scheme.outlineVariant;
    return Card(
      color: Colors.transparent,
      shape: const RoundedRectangleBorder(),
      margin: EdgeInsets.zero,
      child: InkWell(
        key: ValueKey('course-hub-course-${course.key}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 36,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                Text(
                  badge,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.primary,
                  ),
                ),
              ],
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCourses extends StatelessWidget {
  const _EmptyCourses();

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        '还没有本学期课程。导入课表或刷新 SPOC 后会显示在这里',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    ),
  );
}

class _SourceWarning extends StatelessWidget {
  const _SourceWarning({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('course-hub-source-warning'),
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 4),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              onPressed: onRetry,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

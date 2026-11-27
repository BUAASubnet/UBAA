import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import '../../common/state_panel.dart' show UiInlineRetry, UiStatePanel;
import '../../write_callbacks.dart'
    show SigninCourseQrFetcher, SigninStatusChecker;
import '../coursework/signin_qr_sheet.dart' show SigninQrImageSaver;
import '../../shared/dialogs/sheet.dart' show UiInfoRow;
import '../../shared/text.dart' show uiNonBlank;
import '../../shared/when.dart' show uiCampusNow;
import '../../theme.dart' show UbaaTheme;
import '../coursework/assignment_content.dart' show AssignmentCard;
import '../coursework/spoc_classroom_access.dart' show SpocClassroomAccess;
import '../coursework/spoc_files_access.dart' show SpocFilesAccess;
import 'course_classroom_tab.dart' show CourseClassroomTab;
import 'course_files_tab.dart' show CourseFilesTab;
import 'course_format.dart';

typedef SetJudgeLink =
    Future<void> Function(String courseKey, String judgeCourseId, bool linked);

/// 课程主页：课头写清下次在哪上课，下面四个页签各自加载、互不拖累。
class CourseHubCoursePage extends StatelessWidget {
  const CourseHubCoursePage({
    super.key,
    required this.snapshot,
    required this.courseKey,
    required this.onOpenAssignment,
    required this.onOpenFeature,
    this.onRefresh,
    this.onSetJudgeLink,
    this.classroomAccess,
    this.filesAccess,
    this.onFetchSigninQr,
    this.onSaveSigninQr,
    this.onCheckSigninStatus,
  });
  final CourseHubSnapshot snapshot;
  final String courseKey;
  final ValueChanged<FeatureReadNavigation> onOpenAssignment;
  final ValueChanged<FeatureId> onOpenFeature;
  final Future<void> Function()? onRefresh;
  final SetJudgeLink? onSetJudgeLink;
  final SpocClassroomAccess? classroomAccess;
  final SpocFilesAccess? filesAccess;

  /// 签到能力暂不在课程主页使用：签到数据与课表没有共用编号，仍由首页和每日课程承担。
  final SigninCourseQrFetcher? onFetchSigninQr;
  final SigninQrImageSaver? onSaveSigninQr;
  final SigninStatusChecker? onCheckSigninStatus;

  CourseHubCourse? get _course {
    for (final c in snapshot.courses) {
      if (c.key == courseKey) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final course = _course;
    if (course == null) {
      return ListView(
        padding: UbaaTheme.pageInsets(context, top: 8),
        children: const [
          UiStatePanel(
            icon: Icons.school_outlined,
            title: '找不到这门课',
            detail: '课程列表已更新，请返回学习页重新选择',
          ),
        ],
      );
    }
    final now = uiCampusNow();
    final pending = course.assignments
        .where((a) => courseHubBucket(a.detail, now) == CourseHubBucket.pending)
        .length;
    final hasSpoc = course.spocCourses.isNotEmpty;
    final tabs = TabBar(
      key: const ValueKey('course-hub-tabs'),
      // 页签切换时收起键盘，避免输入法候选条留在新页签上。
      onTap: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      tabs: [
        Tab(text: pending == 0 ? '作业' : '作业 $pending'),
        const Tab(text: '课堂'),
        const Tab(text: '课件'),
        const Tab(text: '信息'),
      ],
    );
    return DefaultTabController(
      length: 4,
      // 课头随内容向上滚走，页签栏吸在顶部，手机上留出更多空间给列表。
      child: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverToBoxAdapter(
            child: Padding(
              padding: UbaaTheme.pageInsets(context, top: 4, bottom: 8),
              child: _CourseHeader(course: course, now: now),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _PinnedTabs(
              tabs: tabs,
              padding: UbaaTheme.pageInsets(context, top: 0, bottom: 0),
              color: Theme.of(context).scaffoldBackgroundColor,
            ),
          ),
        ],
        body: TabBarView(
          children: [
            _AssignmentsTab(
              snapshot: snapshot,
              course: course,
              now: now,
              onOpen: onOpenAssignment,
              onRetry: onRefresh,
            ),
            hasSpoc && classroomAccess != null
                ? CourseClassroomTab(
                    access: classroomAccess!,
                    courses: course.spocCourses,
                    courseName: course.name,
                  )
                : const _NoSpoc(what: '课堂'),
            hasSpoc && filesAccess?.canBrowseCourses == true
                ? CourseFilesTab(
                    access: filesAccess!,
                    courses: course.spocCourses,
                    courseName: course.name,
                  )
                : const _NoSpoc(what: '课件'),
            _InfoTab(
              snapshot: snapshot,
              course: course,
              onSetJudgeLink: onSetJudgeLink,
            ),
          ],
        ),
      ),
    );
  }
}

/// 吸顶的页签栏：底色与页面一致，滚动内容不会从页签下面透出来。
class _PinnedTabs extends SliverPersistentHeaderDelegate {
  const _PinnedTabs({
    required this.tabs,
    required this.padding,
    required this.color,
  });
  final TabBar tabs;
  final EdgeInsets padding;
  final Color color;

  @override
  double get minExtent => tabs.preferredSize.height;
  @override
  double get maxExtent => tabs.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      ColoredBox(
        color: color,
        child: Padding(padding: padding, child: tabs),
      );

  @override
  bool shouldRebuild(_PinnedTabs old) =>
      old.tabs != tabs || old.padding != padding || old.color != color;
}

class _CourseHeader extends StatelessWidget {
  const _CourseHeader({required this.course, required this.now});
  final CourseHubCourse course;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final meta = [
      ?courseHubTeachers(course.teachers),
      if (uiNonBlank(course.credit) case final c?) '$c 学分',
    ];
    final next = course.nextClass;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (meta.isNotEmpty)
          Text(
            meta.join(' · '),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 8),
        if (next != null)
          Card(
            key: const ValueKey('course-hub-next-class'),
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.schedule_outlined, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '下次上课 ${courseHubWhen(next.start, now)}'
                          '${next.end == null ? '' : '–${courseHubClock(next.end!)}'}',
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          [
                            uiNonBlank(next.place) ?? '地点待公布',
                            if (next.beginSection case final s?)
                              next.endSection == null || next.endSection == s
                                  ? '第 $s 节'
                                  : '第 $s–${next.endSection} 节',
                          ].join(' · '),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Text(
            course.scheduleLinked ? '本学期没有后续排课' : '这门课没有出现在课表里，只显示 SPOC 内容',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// 作业页签：待交按来源分组排前，已截止未交与其他两组折叠在后。
class _AssignmentsTab extends StatelessWidget {
  const _AssignmentsTab({
    required this.snapshot,
    required this.course,
    required this.now,
    required this.onOpen,
    required this.onRetry,
  });
  final CourseHubSnapshot snapshot;
  final CourseHubCourse course;
  final DateTime now;
  final ValueChanged<FeatureReadNavigation> onOpen;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final items = [...course.assignments]
      ..sort((a, b) => courseHubByDue(a.detail, b.detail));
    final pending = <FeatureId, List<CourseHubAssignment>>{};
    final overdue = <CourseHubAssignment>[];
    final other = <CourseHubAssignment>[];
    for (final item in items) {
      switch (courseHubBucket(item.detail, now)) {
        case CourseHubBucket.pending:
          pending.putIfAbsent(item.feature, () => []).add(item);
        case CourseHubBucket.overdue:
          overdue.add(item);
        case CourseHubBucket.other:
          other.add(item);
      }
    }
    final missing = [
      if (!_complete(snapshot, CourseHubSource.spocCourses)) 'SPOC 课程',
      if (!_complete(snapshot, CourseHubSource.spocAssignments)) 'SPOC 作业',
      if (!_complete(snapshot, CourseHubSource.judgeAssignments)) '希冀作业',
    ];
    final wide = MediaQuery.sizeOf(context).width >= 740;
    Widget card(CourseHubAssignment a) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AssignmentCard(
        detail: a.detail,
        wide: wide,
        onNavigate: (target) async => onOpen(target),
      ),
    );
    return ListView(
      key: const ValueKey('course-hub-assignments'),
      padding: UbaaTheme.pageInsets(context, top: 12, bottom: 24),
      children: [
        if (missing.isNotEmpty) ...[
          UiInlineRetry(
            message: '${missing.join('、')}未加载完整',
            onRetry: onRetry == null ? null : () => onRetry!(),
          ),
          const SizedBox(height: 12),
        ],
        for (final source in const [FeatureId.spoc, FeatureId.judge])
          if (pending[source] case final list?) ...[
            _GroupLabel(
              source == FeatureId.spoc ? 'SPOC 作业' : '希冀作业',
              count: list.length,
            ),
            ...list.map(card),
          ],
        if (pending.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              missing.isEmpty ? '没有待交作业' : '已加载的作业里没有待交项',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (overdue.isNotEmpty)
          _Collapsed(
            key: const ValueKey('course-hub-overdue'),
            title: '已截止未交',
            count: overdue.length,
            children: overdue.map(card).toList(),
          ),
        if (other.isNotEmpty)
          _Collapsed(
            key: const ValueKey('course-hub-done'),
            title:
                other.every(
                  (a) => switch (a.detail.presentation) {
                    SpocAssignmentPresentation p =>
                      p.status == AssignmentSubmissionStatus.submitted,
                    JudgeAssignmentPresentation p =>
                      p.status == AssignmentSubmissionStatus.submitted,
                    _ => false,
                  },
                )
                ? '已提交'
                : '已提交与其他',
            count: other.length,
            children: other.map(card).toList(),
          ),
      ],
    );
  }
}

bool _complete(CourseHubSnapshot hub, CourseHubSource source) =>
    switch (hub.sources[source]?.state) {
      CourseHubSourceState.ready || CourseHubSourceState.notApplicable => true,
      _ => false,
    };

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text, {required this.count});
  final String text;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      '$text · $count',
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w500,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// 折叠分组：标题行显示数量，展开后列出卡片。
class _Collapsed extends StatelessWidget {
  const _Collapsed({
    super.key,
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

class _NoSpoc extends StatelessWidget {
  const _NoSpoc({required this.what});
  final String what;

  @override
  Widget build(BuildContext context) => ListView(
    padding: UbaaTheme.pageInsets(context, top: 12),
    children: [
      UiStatePanel(
        icon: Icons.school_outlined,
        title: '这门课没有 SPOC $what',
        detail: '没有在 SPOC 课程列表里找到这门课',
      ),
    ],
  );
}

/// 信息页签：完整排课、考试、成绩，以及希冀关联开关；没读到的内容不写“无”。
class _InfoTab extends StatelessWidget {
  const _InfoTab({
    required this.snapshot,
    required this.course,
    required this.onSetJudgeLink,
  });
  final CourseHubSnapshot snapshot;
  final CourseHubCourse course;
  final SetJudgeLink? onSetJudgeLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slots =
        [
          for (final d in course.slots)
            if (d.presentation case final ScheduleCoursePresentation p) p,
        ]..sort((a, b) {
          final day = (a.dayOfWeek ?? 9).compareTo(b.dayOfWeek ?? 9);
          return day != 0
              ? day
              : (a.beginSection ?? 99).compareTo(b.beginSection ?? 99);
        });
    final exams = [
      for (final d in course.exams)
        if (d.presentation case final ExamPresentation p) p,
    ];
    final grades = [
      for (final d in course.grades)
        if (d.presentation case final GradePresentation p) p,
    ];
    return ListView(
      key: const ValueKey('course-hub-info'),
      padding: UbaaTheme.pageInsets(context, top: 12, bottom: 24),
      children: [
        if (slots.isNotEmpty) ...[
          _InfoTitle('上课安排'),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final p in slots)
                    UiInfoRow(
                      icon: Icons.schedule_outlined,
                      text: courseHubSlotWhen(p) ?? '时间待公布',
                      detail: [
                        uiNonBlank(p.place) ?? '地点待公布',
                        ?uiNonBlank(p.weeksAndTeachers),
                      ].join(' · '),
                    ),
                ],
              ),
            ),
          ),
        ],
        if (course.courseCode != null || uiNonBlank(course.credit) != null) ...[
          _InfoTitle('课程'),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  if (courseHubTeachers(course.teachers) case final t?)
                    UiInfoRow(icon: Icons.person_outline, label: '教师', text: t),
                  if (uiNonBlank(course.credit) case final c?)
                    UiInfoRow(
                      icon: Icons.school_outlined,
                      label: '学分',
                      text: c,
                    ),
                  if (course.courseCode case final code?)
                    UiInfoRow(icon: Icons.tag, label: '课程代码', text: code),
                ],
              ),
            ),
          ),
        ],
        if (exams.isNotEmpty) ...[
          _InfoTitle('考试'),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  for (final e in exams)
                    UiInfoRow(
                      icon: Icons.event_note_outlined,
                      text:
                          uiNonBlank(e.description) ??
                          [
                            ?uiNonBlank(e.date),
                            ?uiNonBlank(e.startTime),
                          ].join(' '),
                      detail: [
                        uiNonBlank(e.place) ?? '考场待公布',
                        if (uiNonBlank(e.seat) case final s?) '座位 $s',
                      ].join(' · '),
                    ),
                ],
              ),
            ),
          ),
        ],
        if (grades.isNotEmpty) ...[
          _InfoTitle('成绩'),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  for (final g in grades)
                    UiInfoRow(
                      icon: Icons.grade_outlined,
                      label: '成绩',
                      text: uiNonBlank(g.score) ?? '未公布',
                      detail: uiNonBlank(g.gradePoint) == null
                          ? null
                          : '绩点 ${g.gradePoint}',
                    ),
                ],
              ),
            ),
          ),
        ],
        if (course.judgeLinks.isNotEmpty) ...[
          _InfoTitle('希冀课程'),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (final link in course.judgeLinks)
                  SwitchListTile(
                    key: ValueKey('course-hub-judge-${link.judgeCourseId}'),
                    title: Text(link.name),
                    subtitle: Text(
                      link.linked ? '作业显示在这门课里' : '已取消关联，作业仍在“全部作业”和希冀作业中',
                    ),
                    value: link.linked,
                    onChanged: onSetJudgeLink == null
                        ? null
                        : (value) => onSetJudgeLink!(
                            course.key,
                            link.judgeCourseId,
                            value,
                          ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '按课程名自动关联；关联错了可以在这里关掉',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _InfoTitle extends StatelessWidget {
  const _InfoTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

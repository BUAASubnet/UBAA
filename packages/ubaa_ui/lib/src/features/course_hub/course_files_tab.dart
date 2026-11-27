import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import '../../common/state_panel.dart' show UiInlineRetry, UiStatePanel;
import '../../shared/text.dart' show uiNonBlank;
import '../../theme.dart' show UbaaTheme;
import '../coursework/course_files_view.dart' show CourseFilesView;
import '../coursework/spoc_files_access.dart' show SpocFilesAccess;

/// 课件页签：逐个读取本课各 SPOC 课程的根目录。空的和业务不可用的直接略过；
/// 有文件的只剩一个就直接显示，多个时分段切换；其他失败只在顶部提示一行并可重试。
class CourseFilesTab extends StatefulWidget {
  const CourseFilesTab({
    super.key,
    required this.access,
    required this.courses,
    required this.courseName,
  });
  final SpocFilesAccess access;
  final List<SpocCourse> courses;
  final String courseName;

  @override
  State<CourseFilesTab> createState() => _CourseFilesTabState();
}

typedef _Root = ({
  SpocCourse course,
  List<SpocCourseFile>? items,
  Object? error,
});

class _CourseFilesTabState extends State<CourseFilesTab>
    with AutomaticKeepAliveClientMixin {
  List<_Root>? _roots;
  var _selected = 0;
  int _generation = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = widget.access.service;
    if (service == null) return;
    final generation = ++_generation;
    setState(() => _roots = null);
    // 只有一个课程时不必预读，交给课件页自己加载。
    if (widget.courses.length == 1) {
      setState(
        () => _roots = [
          (course: widget.courses.single, items: null, error: null),
        ],
      );
      return;
    }
    final roots = await Future.wait([
      for (final course in widget.courses)
        service
            .courseFiles(course.courseId)
            .then<_Root>(
              (read) => (course: course, items: read.data, error: null),
            )
            .catchError((Object e) => (course: course, items: null, error: e)),
    ]);
    if (!mounted || generation != _generation) return;
    setState(() {
      _roots = roots;
      _selected = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final roots = _roots;
    if (roots == null) return const Center(child: CircularProgressIndicator());
    bool unavailable(Object? e) =>
        e is UiError && e.code == UbaaErrorCode.businessUnavailable;
    // 只有一个课程时不预读（items 与 error 都为空），交给课件页自己加载。
    final withFiles = [
      for (final r in roots)
        if (r.items == null && r.error == null ||
            (r.items?.isNotEmpty ?? false))
          r,
    ];
    // 业务不可用不算失败；其他失败只在顶部提示一行并可重试，不占分段。
    final failed = [
      for (final r in roots)
        if (r.error != null && !unavailable(r.error)) r,
    ];
    if (withFiles.isEmpty) {
      final error = failed.firstOrNull?.error;
      return ListView(
        padding: UbaaTheme.pageInsets(context, top: 12),
        children: [
          if (failed.isEmpty)
            const UiStatePanel(
              icon: Icons.folder_open,
              title: '这里还没有文件',
              detail: '老师上传课件后会显示在这里',
            )
          else
            UiStatePanel(
              icon: Icons.folder_open,
              title: '课件读取失败',
              detail: error is UiError ? error.message : '请稍后重试',
              error: error is UiError ? error : null,
              action: '重试',
              onAction: _load,
            ),
        ],
      );
    }
    final index = _selected.clamp(0, withFiles.length - 1);
    final current = withFiles[index];
    final teachers = [for (final r in withFiles) uiNonBlank(r.course.teacher)];
    final byTeacher =
        !teachers.contains(null) && teachers.toSet().length == teachers.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (failed.isNotEmpty)
          Padding(
            padding: UbaaTheme.pageInsets(context, top: 12, bottom: 0),
            child: UiInlineRetry(
              message: '另有 ${failed.length} 个课程的课件未能读取',
              error: failed.first.error is UiError
                  ? failed.first.error as UiError
                  : null,
              onRetry: _load,
            ),
          ),
        if (withFiles.length > 1)
          Padding(
            padding: UbaaTheme.pageInsets(context, top: 12, bottom: 0),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                for (final (i, t) in teachers.indexed)
                  ButtonSegment(
                    value: i,
                    label: Text(byTeacher ? t! : '课件 ${i + 1}'),
                  ),
              ],
              selected: {index},
              onSelectionChanged: (v) => setState(() => _selected = v.single),
            ),
          ),
        Expanded(
          child: CourseFilesView(
            key: ValueKey(current.course.courseId),
            access: widget.access,
            courseId: current.course.courseId,
            courseName: widget.courseName,
            embedded: true,
            initialItems: current.items,
          ),
        ),
      ],
    );
  }
}

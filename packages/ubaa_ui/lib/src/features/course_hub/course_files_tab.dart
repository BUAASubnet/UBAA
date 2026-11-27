import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import '../../common/state_panel.dart' show UiStatePanel;
import '../../shared/text.dart' show uiNonBlank;
import '../../theme.dart' show UbaaTheme;
import '../coursework/course_files_view.dart' show CourseFilesView;
import '../coursework/spoc_files_access.dart' show SpocFilesAccess;

/// 课件页签：逐个读取本课各 SPOC 课程的根目录，至少一个有文件时略过空的和
/// 业务不可用的；只剩一个就直接显示，多个时按教师分段切换。
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
    final withFiles = [
      for (final r in roots)
        if (r.items == null && r.error == null ||
            (r.items?.isNotEmpty ?? false))
          r,
    ];
    final failed = [
      for (final r in roots)
        if (r.error != null &&
            !(r.error is UiError &&
                (r.error as UiError).code == UbaaErrorCode.businessUnavailable))
          r,
    ];
    final shown = [...withFiles, ...failed];
    if (shown.isEmpty) {
      return ListView(
        padding: UbaaTheme.pageInsets(context, top: 12),
        children: const [
          UiStatePanel(
            icon: Icons.folder_open,
            title: '这里还没有文件',
            detail: '老师上传课件后会显示在这里',
          ),
        ],
      );
    }
    final index = _selected.clamp(0, shown.length - 1);
    final current = shown[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (shown.length > 1)
          Padding(
            padding: UbaaTheme.pageInsets(context, top: 12, bottom: 0),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                for (final (i, r) in shown.indexed)
                  ButtonSegment(
                    value: i,
                    label: Text(uiNonBlank(r.course.teacher) ?? '课件 ${i + 1}'),
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

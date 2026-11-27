import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import '../../common/state_panel.dart' show UiStatePanel;
import '../../shared/text.dart' show uiNonBlank;
import '../../theme.dart' show UbaaTheme;
import '../coursework/spoc_classroom_access.dart' show SpocClassroomAccess;
import '../spoc_classroom/classroom_view.dart' show ClassroomSessionList;

/// 课堂页签：一门课可能有多个 SPOC 课程（例如实验班）。逐个读取课堂目录，
/// 至少一个读到时略过“未开通课堂”等业务不可用的；只剩一个就直接显示，
/// 多个时按教师分段切换。网络等其他失败照常显示重试，不静默吞掉。
class CourseClassroomTab extends StatefulWidget {
  const CourseClassroomTab({
    super.key,
    required this.access,
    required this.courses,
    required this.courseName,
  });
  final SpocClassroomAccess access;
  final List<SpocCourse> courses;
  final String courseName;

  @override
  State<CourseClassroomTab> createState() => _CourseClassroomTabState();
}

typedef _Read = ({SpocCourse course, ClassroomCatalog? catalog, Object? error});

class _CourseClassroomTabState extends State<CourseClassroomTab>
    with AutomaticKeepAliveClientMixin {
  List<_Read>? _reads;
  var _loading = false;
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
    final generation = ++_generation;
    setState(() => _loading = true);
    final reads = await Future.wait([
      for (final course in widget.courses)
        widget.access.service
            .catalog(course.courseId)
            .then<_Read>(
              (read) => (course: course, catalog: read.data, error: null),
            )
            .catchError(
              (Object error) => (course: course, catalog: null, error: error),
            ),
    ]);
    if (!mounted || generation != _generation) return;
    setState(() {
      _reads = reads;
      _loading = false;
      _selected = 0;
    });
  }

  static bool _unavailable(Object? error) =>
      error is UiError && error.code == UbaaErrorCode.businessUnavailable;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final reads = _reads;
    if (reads == null) return const Center(child: CircularProgressIndicator());
    final ok = [
      for (final r in reads)
        if (r.catalog != null) r,
    ];
    // 有读到的就略过业务不可用的；其他失败仍要让人看见并能重试。
    final shown = [
      for (final r in reads)
        if (r.catalog != null || (ok.isEmpty || !_unavailable(r.error))) r,
    ];
    if (ok.isEmpty) {
      final error = reads.first.error;
      final ui = error is UiError ? error : null;
      return ListView(
        padding: UbaaTheme.pageInsets(context, top: 12),
        children: [
          UiStatePanel(
            icon: Icons.smart_display_outlined,
            title: _unavailable(error) ? '暂无课堂' : '课堂读取失败',
            detail: ui?.message ?? '请稍后重试',
            error: ui,
            action: _unavailable(error) ? null : '重试',
            onAction: _unavailable(error) || _loading ? null : _load,
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
                  ButtonSegment(value: i, label: Text(_label(r, i))),
              ],
              selected: {index},
              onSelectionChanged: (v) => setState(() => _selected = v.single),
            ),
          ),
        Expanded(
          child: current.catalog == null
              ? ListView(
                  padding: UbaaTheme.pageInsets(context, top: 12),
                  children: [
                    UiStatePanel(
                      icon: Icons.smart_display_outlined,
                      title: '课堂读取失败',
                      detail: current.error is UiError
                          ? (current.error as UiError).message
                          : '请稍后重试',
                      action: '重试',
                      onAction: _loading ? null : _load,
                    ),
                  ],
                )
              : ClassroomSessionList(
                  access: widget.access,
                  catalog: current.catalog!,
                  courseName: widget.courseName,
                  onRefresh: _load,
                ),
        ),
      ],
    );
  }

  static String _label(_Read r, int i) =>
      uiNonBlank(r.course.teacher) ?? '课堂 ${i + 1}';
}

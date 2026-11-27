import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import '../../common/state_panel.dart' show UiInlineRetry, UiStatePanel;
import '../../shared/text.dart' show uiNonBlank;
import '../../theme.dart' show UbaaTheme;
import '../coursework/spoc_classroom_access.dart' show SpocClassroomAccess;
import '../spoc_classroom/classroom_view.dart' show ClassroomSessionList;

/// 课堂页签：一门课可能有多个 SPOC 课程（例如实验班）。逐个读取课堂目录：
/// 未开通课堂等业务不可用的直接略过；读到的按课堂去重，只剩一个就直接显示，
/// 多个时分段切换。网络等其他失败只在顶部提示一行并可重试，不占分段、也不静默吞掉。
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
    // 两个 SPOC 课程可能签到同一个智学北航课堂，按课堂去重。
    final seen = <String>{};
    final ok = [
      for (final r in reads)
        if (r.catalog case final c? when seen.add(c.courseId)) r,
    ];
    // 业务不可用（未开通课堂等）不算失败；其他失败在顶部提示并可重试。
    final failed = [
      for (final r in reads)
        if (r.catalog == null && !_unavailable(r.error)) r,
    ];
    if (ok.isEmpty) {
      final error = failed.firstOrNull?.error ?? reads.first.error;
      final ui = error is UiError ? error : null;
      return ListView(
        padding: UbaaTheme.pageInsets(context, top: 12),
        children: [
          UiStatePanel(
            icon: Icons.smart_display_outlined,
            title: failed.isEmpty ? '暂无课堂' : '课堂读取失败',
            detail: ui?.message ?? '请稍后重试',
            error: ui,
            action: '重试',
            onAction: _loading ? null : _load,
          ),
        ],
      );
    }
    final index = _selected.clamp(0, ok.length - 1);
    final current = ok[index];
    final labels = _labels(ok);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (failed.isNotEmpty)
          Padding(
            padding: UbaaTheme.pageInsets(context, top: 12, bottom: 0),
            child: UiInlineRetry(
              message: '另有 ${failed.length} 个课堂未能读取',
              error: failed.first.error is UiError
                  ? failed.first.error as UiError
                  : null,
              onRetry: _loading ? null : _load,
            ),
          ),
        if (ok.length > 1)
          Padding(
            padding: UbaaTheme.pageInsets(context, top: 12, bottom: 0),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                for (final (i, _) in ok.indexed)
                  ButtonSegment(value: i, label: Text(labels[i])),
              ],
              selected: {index},
              onSelectionChanged: (v) => setState(() => _selected = v.single),
            ),
          ),
        Expanded(
          child: ClassroomSessionList(
            access: widget.access,
            catalog: current.catalog!,
            courseName: widget.courseName,
            onRefresh: _load,
          ),
        ),
      ],
    );
  }

  /// 教师各不相同时按教师标注，否则按顺序编号，避免两个同名分段。
  static List<String> _labels(List<_Read> reads) {
    final teachers = [for (final r in reads) uiNonBlank(r.course.teacher)];
    final distinct =
        !teachers.contains(null) && teachers.toSet().length == teachers.length;
    return [
      for (final (i, t) in teachers.indexed) distinct ? t! : '课堂 ${i + 1}',
    ];
  }
}

import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import '../../shared/dialogs/form_page.dart' show showUiPage;
import '../../shared/dialogs/sheet.dart' show showUiSheet, UiSheetBody;
import '../../shared/feedback.dart' show UbaaFeedback, UbaaFeedbackKind;
import '../../shared/text.dart' show uiNonBlank;
import '../../theme.dart' show UbaaTheme;
import '../coursework/spoc_classroom_access.dart' show SpocClassroomAccess;
import 'classroom_view.dart' show ClassroomView;

/// 课程标题行右侧的“课堂”入口。
///
/// 作业摘要按课程名分组，组内第一条的课程标识不一定是全部：同名课程可能有多个
/// SPOC kcid（例如理论与实验分开），分别对应不同的课堂。这里先用课程列表找出
/// 同名的全部 kcid，只有一个就直接进入，多个就让用户选，不靠课程名猜。
class ClassroomEntryButton extends StatefulWidget {
  const ClassroomEntryButton({
    super.key,
    required this.access,
    required this.courseName,
    this.fallbackCourseId,
  });
  final SpocClassroomAccess access;
  final String courseName;

  /// 课程列表读取失败或找不到同名课程时使用的 kcid（来自作业记录）。
  final String? fallbackCourseId;

  @override
  State<ClassroomEntryButton> createState() => _ClassroomEntryButtonState();
}

class _ClassroomEntryButtonState extends State<ClassroomEntryButton> {
  var _busy = false;

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    List<SpocCourse> candidates = const [];
    try {
      final read = await widget.access.courses();
      candidates = [
        for (final c in read.data)
          if (c.name.trim() == widget.courseName.trim()) c,
      ];
    } on Object catch (error) {
      if (widget.fallbackCourseId == null && mounted) {
        UbaaFeedback.show(
          context,
          error is UiError ? error.message : '课程列表读取失败，请稍后重试',
          error: error is UiError ? error : null,
          kind: UbaaFeedbackKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    String? kcid;
    if (candidates.length > 1) {
      kcid = await _pick(candidates);
    } else if (candidates.length == 1) {
      kcid = candidates.single.courseId;
    } else {
      kcid = widget.fallbackCourseId;
    }
    if (kcid == null || !mounted) return;
    await showUiPage<void>(
      context,
      fixedHeight: true,
      dialogWidth: 720,
      builder: (_) => ClassroomView(
        access: widget.access,
        kcid: kcid!,
        courseName: widget.courseName,
      ),
    );
  }

  Future<String?> _pick(List<SpocCourse> courses) {
    final teachers = {for (final c in courses) uiNonBlank(c.teacher) ?? ''};
    // 教师都相同或都缺失时，按顺序编号区分。
    final byTeacher =
        teachers.length == courses.length && !teachers.contains('');
    return showUiSheet<String>(
      context,
      builder: (sheetContext) => UiSheetBody(
        title: '选择课堂',
        children: [
          for (var i = 0; i < courses.length; i++)
            _ChoiceRow(
              title: widget.courseName,
              subtitle: byTeacher
                  ? courses[i].teacher!.trim()
                  : '第 ${i + 1} 个课堂${uiNonBlank(courses[i].teacher) == null ? '' : ' · ${courses[i].teacher!.trim()}'}',
              onTap: () => Navigator.of(sheetContext).pop(courses[i].courseId),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    style: TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(0, 32),
    ),
    onPressed: _busy ? null : _open,
    icon: _busy
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.smart_display_outlined, size: 18),
    label: const Text('课堂'),
  );
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(UbaaTheme.controlRadius),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.smart_display_outlined,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.bodyMedium),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

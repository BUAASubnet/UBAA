part of '../../widgets.dart';

extension _LoadedAssignmentPicker on _FeatureQueryControlsState {
  Widget _loadedAssignmentPicker(StateSetter setState, {required bool judge}) {
    final options = <(String, String), String>{};
    for (final detail in widget.details) {
      final p = detail.presentation;
      if (judge &&
          p is JudgeAssignmentPresentation &&
          p.courseId.trim().isNotEmpty &&
          p.assignmentId.trim().isNotEmpty) {
        options[(p.courseId, p.assignmentId)] =
            '${p.courseName} · ${detail.title}（${p.courseId} / ${p.assignmentId}）';
      } else if (!judge &&
          p is SpocAssignmentPresentation &&
          p.assignmentId.trim().isNotEmpty) {
        options[(p.courseId, p.assignmentId)] =
            '${p.courseName} · ${detail.title}（${p.assignmentId}）';
      }
    }
    return OutlinedButton.icon(
      onPressed: _submitting || options.isEmpty
          ? null
          : () async {
              final epoch = widget.readCacheEpoch;
              final snapshot = widget.snapshot;
              final selected = await showDialog<(String, String)>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('选择已加载作业'),
                  content: SizedBox(
                    width: 480,
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final entry in options.entries)
                          ListTile(
                            title: Text(entry.value),
                            onTap: () => Navigator.of(context).pop(entry.key),
                          ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ],
                ),
              );
              if (!mounted ||
                  selected == null ||
                  epoch != widget.readCacheEpoch ||
                  !identical(snapshot, widget.snapshot))
                return;
              setState(() {
                if (judge) {
                  _judgeCourseController.text = selected.$1;
                  _judgeAssignmentController.text = selected.$2;
                } else {
                  _spocAssignmentController.text = selected.$2;
                }
              });
            },
      icon: const Icon(Icons.list_alt),
      label: const Text('选择已加载作业'),
    );
  }
}

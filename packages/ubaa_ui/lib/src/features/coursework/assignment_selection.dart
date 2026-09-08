part of '../../widgets.dart';

extension _JudgeSelection on _FeatureDetailListState {
  Widget? _judgeSelection(FeatureDetail detail, StateSetter setState) {
    if (widget.feature != FeatureId.judge || widget.onNavigate == null)
      return null;
    final p = detail.presentation;
    if (p is! JudgeAssignmentPresentation ||
        p.isDetail ||
        p.courseId.trim().isEmpty ||
        p.assignmentId.trim().isEmpty)
      return null;
    final key = (p.courseId, p.assignmentId);
    return CheckboxListTile(
      key: ValueKey(('judge-selection', p.courseId, p.assignmentId)),
      contentPadding: EdgeInsets.zero,
      title: const Text('选择此作业查看批量详情'),
      value: _selectedJudgeKeys.contains(key),
      onChanged: (selected) => setState(() {
        if (selected == true) {
          if (!_selectedJudgeKeys.contains(key)) _selectedJudgeKeys.add(key);
        } else {
          _selectedJudgeKeys.remove(key);
        }
      }),
    );
  }

  List<Widget> _judgeBatchFields(StateSetter setState) => [
    if (widget.feature == FeatureId.judge &&
        _selectedJudgeKeys.isNotEmpty &&
        widget.onNavigate != null &&
        widget.details.any(
          (detail) => switch (detail.presentation) {
            JudgeAssignmentPresentation p
                when !p.isDetail &&
                    p.courseId.trim().isNotEmpty &&
                    p.assignmentId.trim().isNotEmpty =>
              true,
            _ => false,
          },
        ) &&
        (widget.query?.view ?? FeatureQueryView.summary) ==
            FeatureQueryView.summary)
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('已选择 ${_selectedJudgeKeys.length} 份作业'),
            FilledButton.tonalIcon(
              onPressed: _selectedJudgeKeys.isEmpty
                  ? null
                  : () => widget.onNavigate!(
                      FeatureReadNavigation(
                        feature: FeatureId.judge,
                        query: FeatureQuery(
                          view: FeatureQueryView.judgeBatchDetails,
                          includeExpired: widget.query?.includeExpired ?? false,
                          judgeKeys: [
                            for (final key in _selectedJudgeKeys)
                              JudgeAssignmentQueryKey(
                                courseId: key.$1,
                                assignmentId: key.$2,
                              ),
                          ],
                        ),
                      ),
                    ),
              icon: const Icon(Icons.library_books_outlined),
              label: const Text('查看所选作业'),
            ),
            if (_selectedJudgeKeys.isNotEmpty)
              TextButton(
                onPressed: () => setState(_selectedJudgeKeys.clear),
                child: const Text('清空选择'),
              ),
          ],
        ),
      ),
  ];
}

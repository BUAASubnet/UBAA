part of 'detail_list.dart';

extension BykcDetailActions on _FeatureDetailListState {
  String _bykcWriteLabel(WriteOperation operation, int courseId) {
    final label = operation == WriteOperation.bykcSelectCourse ? '选课' : '退选';
    return widget.bykcPendingCourseId == courseId ? '$label中…' : label;
  }

  Widget _bykcWriteIcon(WriteOperation operation, int courseId) =>
      widget.bykcPendingCourseId == courseId
      ? const LoadingGlyph(dimension: 18)
      : Icon(
          operation == WriteOperation.bykcSelectCourse
              ? Icons.add_circle_outline
              : Icons.remove_circle_outline,
        );

  Widget? _bykcListAction(
    FeatureDetail detail,
    int courseId, {
    required bool selected,
    bool full = false,
  }) {
    if (widget.onBykcWrite == null) return null;
    final select = detail.action<BykcSelectAction>();
    final deselect = detail.action<BykcDeselectAction>();
    final operation = selected
        ? WriteOperation.bykcDeselectCourse
        : WriteOperation.bykcSelectCourse;
    final target = selected ? deselect?.courseId : select?.courseId;
    final eligibility = selected ? deselect?.eligibility : select?.eligibility;
    // 缓存只有展示信息，预留相同的禁用按钮；回调必须由在线动作授权。
    final allowed =
        widget.writesEnabled &&
        courseId > 0 &&
        target == courseId &&
        eligibility == ActionEligibility.allowed &&
        (selected || !full);
    // 已满时直接说明原因，不只留一个灰掉的“选课”。
    if (!selected && full && widget.bykcPendingCourseId != courseId) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.block),
        label: const Text('已满'),
      );
    }
    final onPressed = allowed
        ? () => widget.onBykcWrite!(operation, target!)
        : null;
    // 可选的课用浅色实底按钮，与“已满”、不可选的灰色描边按钮一眼可分；退选保持描边。
    return selected
        ? OutlinedButton.icon(
            onPressed: onPressed,
            icon: _bykcWriteIcon(operation, courseId),
            label: Text(_bykcWriteLabel(operation, courseId)),
          )
        : FilledButton.tonalIcon(
            onPressed: onPressed,
            icon: _bykcWriteIcon(operation, courseId),
            label: Text(_bykcWriteLabel(operation, courseId)),
          );
  }

  List<Widget> _bykcCourseWriteFields(
    BuildContext context,
    int? courseId,
    BykcSelectAction? bykcSelectAction,
    BykcDeselectAction? bykcDeselectAction,
    bool canBykcSelect,
    bool canBykcDeselect,
  ) => <Widget>[
    if (widget.feature == FeatureId.bykc &&
        widget.onBykcWrite != null &&
        (bykcSelectAction != null ||
            bykcDeselectAction != null ||
            courseId != null)) ...<Widget>[
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          OutlinedButton.icon(
            onPressed: !widget.writesEnabled
                ? null
                : canBykcSelect
                ? () => widget.onBykcWrite!(
                    WriteOperation.bykcSelectCourse,
                    bykcSelectAction!.courseId,
                  )
                : null,
            icon: _bykcWriteIcon(
              WriteOperation.bykcSelectCourse,
              bykcSelectAction?.courseId ?? 0,
            ),
            label: Text(
              _bykcWriteLabel(
                WriteOperation.bykcSelectCourse,
                bykcSelectAction?.courseId ?? 0,
              ),
            ),
          ),
          if (bykcDeselectAction != null || courseId != null)
            OutlinedButton.icon(
              onPressed: !widget.writesEnabled
                  ? null
                  : canBykcDeselect
                  ? () => widget.onBykcWrite!(
                      bykcDeselectAction!.operation,
                      bykcDeselectAction.courseId,
                    )
                  : null,
              icon: _bykcWriteIcon(
                WriteOperation.bykcDeselectCourse,
                bykcDeselectAction?.courseId ?? 0,
              ),
              label: Text(
                _bykcWriteLabel(
                  WriteOperation.bykcDeselectCourse,
                  bykcDeselectAction?.courseId ?? 0,
                ),
              ),
            ),
        ],
      ),
      if (!canBykcSelect || !canBykcDeselect)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '部分操作当前不可用',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    ],
  ];

  List<Widget> _bykcSignWriteFields(
    BuildContext context,
    BykcSignAction? bykcSignInAction,
    BykcSignAction? bykcSignOutAction,
    bool canBykcSign,
    bool canBykcSignOut,
  ) => <Widget>[
    if (widget.feature == FeatureId.bykc &&
        widget.onBykcSignWrite != null &&
        (bykcSignInAction != null || bykcSignOutAction != null)) ...<Widget>[
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          if (bykcSignInAction != null)
            OutlinedButton.icon(
              onPressed: !widget.writesEnabled
                  ? null
                  : canBykcSign
                  ? () => widget.onBykcSignWrite!(bykcSignInAction)
                  : null,
              icon: const Icon(Icons.login),
              label: const Text('博雅签到'),
            ),
          if (bykcSignOutAction != null)
            OutlinedButton.icon(
              onPressed: !widget.writesEnabled
                  ? null
                  : canBykcSignOut
                  ? () => widget.onBykcSignWrite!(bykcSignOutAction)
                  : null,
              icon: const Icon(Icons.logout),
              label: const Text('博雅签退'),
            ),
        ],
      ),
      if ((bykcSignInAction != null && !canBykcSign) ||
          (bykcSignOutAction != null && !canBykcSignOut))
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '部分签到操作当前不可用',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    ],
  ];

  int? _courseId(FeatureDetail detail) {
    for (final field in detail.fields) {
      if (field.label == '课程 ID') return int.tryParse(field.value.trim());
    }
    return null;
  }

  BykcSignAction? _bykcSignAction(FeatureDetail detail, BykcSignKind kind) {
    for (final action in detail.actions) {
      if (action is BykcSignAction && action.kind == kind) return action;
    }
    return null;
  }
}

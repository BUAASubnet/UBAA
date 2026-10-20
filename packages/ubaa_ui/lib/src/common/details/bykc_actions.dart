part of 'detail_list.dart';

extension BykcDetailActions on _FeatureDetailListState {
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
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('准备选课'),
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
              icon: const Icon(Icons.remove_circle_outline),
              label: const Text('准备退选'),
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
              label: const Text('准备博雅签到'),
            ),
          if (bykcSignOutAction != null)
            OutlinedButton.icon(
              onPressed: !widget.writesEnabled
                  ? null
                  : canBykcSignOut
                  ? () => widget.onBykcSignWrite!(bykcSignOutAction)
                  : null,
              icon: const Icon(Icons.logout),
              label: const Text('准备博雅签退'),
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

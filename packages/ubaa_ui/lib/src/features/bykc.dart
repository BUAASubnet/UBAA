part of '../widgets.dart';

extension _BykcQueryControls on _FeatureQueryControlsState {
  List<Widget> _bykcQueryFields(StateSetter setState) => <Widget>[
    if (widget.feature == FeatureId.bykc) ...<Widget>[
      DropdownButton<FeatureQueryView>(
        value: _bykcView,
        onChanged: _submitting
            ? null
            : (value) =>
                  setState(() => _bykcView = value ?? FeatureQueryView.summary),
        items: const <DropdownMenuItem<FeatureQueryView>>[
          DropdownMenuItem(
            value: FeatureQueryView.summary,
            child: Text('课程列表'),
          ),
          DropdownMenuItem(
            value: FeatureQueryView.bykcDetail,
            child: Text('课程详情'),
          ),
          DropdownMenuItem(
            value: FeatureQueryView.bykcChosenCourses,
            child: Text('已选课程'),
          ),
          DropdownMenuItem(
            value: FeatureQueryView.bykcStatistics,
            child: Text('修读统计'),
          ),
          DropdownMenuItem(
            value: FeatureQueryView.bykcProfile,
            child: Text('个人资料'),
          ),
        ],
      ),
      if (_bykcView == FeatureQueryView.summary) ...<Widget>[
        SizedBox(
          width: 110,
          child: TextField(
            controller: _pageController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '页码',
              hintText: '从 1 开始',
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          width: 110,
          child: TextField(
            controller: _sizeController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '每页数量',
              hintText: '1–100',
              isDense: true,
            ),
          ),
        ),
      ],
      if (_bykcView == FeatureQueryView.bykcDetail) ...<Widget>[
        SizedBox(
          width: 150,
          child: TextField(
            controller: _bykcCourseController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '课程 ID',
              hintText: '从课程列表选择',
              isDense: true,
            ),
          ),
        ),
        _valuePicker(
          label: '从当前列表选择课程',
          values: _detailFieldValues('课程 ID'),
          onSelected: (value) => _bykcCourseController.text = value,
        ),
      ],
    ],
  ];
}

extension _BykcDetailActions on _FeatureDetailListState {
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
            onPressed: canBykcSelect
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
              onPressed: canBykcDeselect
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
            '当前课程状态不支持该操作；最终资格和时间窗仍由 Core 校验。',
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
              onPressed: canBykcSign
                  ? () => widget.onBykcSignWrite!(bykcSignInAction)
                  : null,
              icon: const Icon(Icons.login),
              label: const Text('准备博雅签到'),
            ),
          if (bykcSignOutAction != null)
            OutlinedButton.icon(
              onPressed: canBykcSignOut
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
            '当前不在可操作时间窗或状态不允许，具体条件由 Core 判定。',
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

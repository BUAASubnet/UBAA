part of 'query_controls.dart';

extension BykcQueryControls on FeatureQueryControlsState {
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
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('当前页课程状态'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final status in BykcCourseStatus.values)
                    FilterChip(
                      label: Text(uiBykcStatusLabel(status)),
                      selected: widget.bykcStatuses.contains(status),
                      onSelected: (selected) {
                        final values = {...widget.bykcStatuses};
                        selected ? values.add(status) : values.remove(status);
                        widget.onBykcStatusesChanged?.call(values);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('当前页课程类别'),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final category in BykcCourseSubCategory.values.where(
                    (value) => value != BykcCourseSubCategory.unknown,
                  ))
                    FilterChip(
                      label: Text(category.displayName),
                      selected: widget.bykcCategories.contains(
                        category.displayName,
                      ),
                      onSelected: (selected) {
                        final values = {...widget.bykcCategories};
                        selected
                            ? values.add(category.displayName)
                            : values.remove(category.displayName);
                        widget.onBykcCategoriesChanged?.call(values);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('适用校区'),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final campus in uiBykcCampusOptions(
                    widget.details,
                    widget.bykcCampuses,
                  ))
                    FilterChip(
                      label: Text(campus),
                      selected: widget.bykcCampuses.contains(campus),
                      onSelected: (selected) {
                        final values = {...widget.bykcCampuses};
                        selected ? values.add(campus) : values.remove(campus);
                        widget.onBykcCampusesChanged?.call(values);
                      },
                    ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('仅筛选当前服务器页；其他页请翻页查询。'),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: () => widget.onBykcStatusesChanged?.call({}),
                    child: const Text('状态不限'),
                  ),
                  TextButton(
                    onPressed: widget.onBykcReset,
                    child: const Text('恢复默认'),
                  ),
                ],
              ),
            ],
          ),
        ),
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
          values: _bykcCourseValues(),
          onSelected: (value) => _bykcCourseController.text = value,
        ),
      ],
    ],
  ];

  List<String> _bykcCourseValues() {
    final values = <String>{};
    var hasTyped = false;
    for (final detail in widget.details) {
      switch (detail.presentation) {
        case BykcCoursePresentation course:
          hasTyped = true;
          if (course.id > 0) values.add('${course.id}');
        case BykcChosenPresentation course:
          hasTyped = true;
          if (course.courseId > 0) values.add('${course.courseId}');
        default:
          break;
      }
    }
    return hasTyped ? values.toList() : _detailFieldValues('课程 ID');
  }
}

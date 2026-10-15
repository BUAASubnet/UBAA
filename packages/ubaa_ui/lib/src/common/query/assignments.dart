part of 'query_controls.dart';

extension AssignmentsQueryControls on FeatureQueryControlsState {
  List<Widget> _spocQueryFields(StateSetter setState) => <Widget>[
    if (widget.feature == FeatureId.spoc) ...<Widget>[
      DropdownButton<FeatureQueryView>(
        value: _spocView,
        onChanged: _submitting
            ? null
            : (value) =>
                  setState(() => _spocView = value ?? FeatureQueryView.summary),
        items: const <DropdownMenuItem<FeatureQueryView>>[
          DropdownMenuItem(
            value: FeatureQueryView.summary,
            child: Text('作业列表'),
          ),
          DropdownMenuItem(
            value: FeatureQueryView.spocDetail,
            child: Text('作业详情'),
          ),
        ],
      ),
      if (_spocView == FeatureQueryView.spocDetail) ...<Widget>[
        SizedBox(
          width: 160,
          child: TextField(
            controller: _spocAssignmentController,
            decoration: const InputDecoration(
              labelText: '作业编号',
              hintText: '从作业列表选择',
              isDense: true,
            ),
          ),
        ),
        _loadedAssignmentPicker(setState, judge: false),
      ],
    ],
  ];

  List<Widget> _signinQueryFields(StateSetter setState) => <Widget>[
    if (widget.feature == FeatureId.signin)
      DropdownButton<FeatureQueryView>(
        value: _signinView,
        onChanged: _submitting
            ? null
            : (value) => setState(
                () => _signinView = value ?? FeatureQueryView.summary,
              ),
        items: const <DropdownMenuItem<FeatureQueryView>>[
          DropdownMenuItem(
            value: FeatureQueryView.summary,
            child: Text('全部课程'),
          ),
          DropdownMenuItem(
            value: FeatureQueryView.signinPending,
            child: Text('可签到'),
          ),
          DropdownMenuItem(
            value: FeatureQueryView.signinCompleted,
            child: Text('已签到'),
          ),
        ],
      ),
  ];

  List<Widget> _judgeQueryFields(StateSetter setState) => <Widget>[
    if (widget.feature == FeatureId.judge) ...<Widget>[
      DropdownButton<FeatureQueryView>(
        value: _judgeView,
        onChanged: _submitting
            ? null
            : (value) => setState(
                () => _judgeView = value ?? FeatureQueryView.summary,
              ),
        items: const <DropdownMenuItem<FeatureQueryView>>[
          DropdownMenuItem(
            value: FeatureQueryView.summary,
            child: Text('作业列表'),
          ),
          DropdownMenuItem(
            value: FeatureQueryView.judgeDetail,
            child: Text('作业详情'),
          ),
          DropdownMenuItem(
            value: FeatureQueryView.judgeBatchDetails,
            child: Text('批量详情'),
          ),
        ],
      ),
      if (_judgeView == FeatureQueryView.judgeDetail) ...<Widget>[
        SizedBox(
          width: 140,
          child: TextField(
            controller: _judgeCourseController,
            decoration: const InputDecoration(
              labelText: '课程编号',
              hintText: '从作业列表选择',
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          width: 160,
          child: TextField(
            controller: _judgeAssignmentController,
            decoration: const InputDecoration(
              labelText: '作业编号',
              hintText: '从作业列表选择',
              isDense: true,
            ),
          ),
        ),
        _loadedAssignmentPicker(setState, judge: true),
      ],
      if (_judgeView == FeatureQueryView.judgeBatchDetails)
        SizedBox(
          width: 320,
          child: TextField(
            controller: _judgeBatchController,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: '批量作业键',
              hintText: '每行：课程编号/作业编号',
              isDense: true,
            ),
          ),
        ),
      if (_judgeView == FeatureQueryView.summary)
        FilterChip(
          label: const Text('完整刷新'),
          selected: _fullRefresh,
          onSelected: _submitting
              ? null
              : (selected) => setState(() => _fullRefresh = selected),
        ),
      if (_judgeView == FeatureQueryView.summary)
        FilterChip(
          label: const Text('包含已过期作业'),
          selected: _includeExpired,
          onSelected: _submitting
              ? null
              : (selected) => setState(() => _includeExpired = selected),
        ),
    ],
  ];
}

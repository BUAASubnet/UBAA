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
        _loadedAssignmentPicker(setState),
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
}

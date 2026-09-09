part of '../widgets.dart';

extension _AcademicQueryControls on _FeatureQueryControlsState {
  List<Widget> _academicQueryFields(StateSetter setState) => <Widget>[
    if (widget.feature == FeatureId.schedule)
      DropdownButton<FeatureQueryView>(
        value: _scheduleView,
        onChanged: _submitting
            ? null
            : (value) => setState(
                () => _scheduleView = value ?? FeatureQueryView.scheduleToday,
              ),
        items: const <DropdownMenuItem<FeatureQueryView>>[
          DropdownMenuItem(
            value: FeatureQueryView.scheduleToday,
            child: Text('今日课程'),
          ),
          DropdownMenuItem(
            value: FeatureQueryView.summary,
            child: Text('按输入查询'),
          ),
          DropdownMenuItem(
            value: FeatureQueryView.scheduleTerms,
            child: Text('学期列表'),
          ),
          DropdownMenuItem(
            value: FeatureQueryView.scheduleWeeks,
            child: Text('周次列表'),
          ),
          DropdownMenuItem(
            value: FeatureQueryView.scheduleWeek,
            child: Text('周课表'),
          ),
        ],
      ),
    if (widget.feature == FeatureId.exam)
      DropdownButton<FeatureQueryView>(
        value: _examView,
        onChanged: _submitting
            ? null
            : (value) =>
                  setState(() => _examView = value ?? FeatureQueryView.summary),
        items: const <DropdownMenuItem<FeatureQueryView>>[
          DropdownMenuItem(
            value: FeatureQueryView.summary,
            child: Text('全部考试'),
          ),
          DropdownMenuItem(
            value: FeatureQueryView.examArranged,
            child: Text('已安排'),
          ),
          DropdownMenuItem(
            value: FeatureQueryView.examNotArranged,
            child: Text('未安排'),
          ),
        ],
      ),
    if (widget.feature == FeatureId.grades)
      DropdownButton<FeatureQueryView>(
        value: _gradesView,
        onChanged: _submitting
            ? null
            : (value) => setState(
                () => _gradesView = value ?? FeatureQueryView.summary,
              ),
        items: const <DropdownMenuItem<FeatureQueryView>>[
          DropdownMenuItem(
            value: FeatureQueryView.summary,
            child: Text('全部成绩'),
          ),
          DropdownMenuItem(
            value: FeatureQueryView.gradesScored,
            child: Text('已出成绩'),
          ),
          DropdownMenuItem(
            value: FeatureQueryView.gradesMissing,
            child: Text('待出成绩'),
          ),
        ],
      ),
    if ((widget.feature == FeatureId.schedule &&
            _scheduleView != FeatureQueryView.scheduleToday) ||
        widget.feature == FeatureId.exam ||
        widget.feature == FeatureId.grades) ...<Widget>[
      if (widget.onLoadAcademicTerms != null)
        OutlinedButton.icon(
          onPressed: _submitting ? null : _chooseTerm,
          icon: const Icon(Icons.calendar_month_outlined),
          label: const Text('选择学期'),
        ),
      if (widget.feature == FeatureId.schedule &&
          _scheduleView == FeatureQueryView.scheduleWeek &&
          widget.onLoadAcademicWeeks != null)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '上一教学周',
              onPressed: _submitting ? null : () => _stepWeek(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            OutlinedButton(
              onPressed: _submitting ? null : _chooseWeek,
              child: const Text('选择教学周'),
            ),
            IconButton(
              tooltip: '下一教学周',
              onPressed: _submitting ? null : () => _stepWeek(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      SizedBox(
        width: 180,
        child: TextField(
          controller: _termController,
          decoration: InputDecoration(
            labelText: '学期编码',
            helperText: _needsTerm ? '必填' : null,
            hintText: _needsTerm ? '可从学期列表选择' : '留空使用当前学期',
            isDense: true,
          ),
        ),
      ),
      if (widget.feature == FeatureId.schedule)
        SizedBox(
          width: 110,
          child: TextField(
            controller: _weekController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '周次',
              helperText: _scheduleView == FeatureQueryView.scheduleWeek
                  ? '必填'
                  : null,
              hintText: '如 1',
              isDense: true,
            ),
          ),
        ),
    ],
    ..._classroomQueryFields(setState),
  ];

  bool get _needsTerm =>
      widget.feature == FeatureId.schedule &&
      (_scheduleView == FeatureQueryView.scheduleWeeks ||
          _scheduleView == FeatureQueryView.scheduleWeek);

  Future<void> _chooseTerm() async {
    final loader = widget.onLoadAcademicTerms;
    if (loader == null) return;
    final epoch = widget.readCacheEpoch;
    final selected = await showDialog<String>(
      context: context,
      builder: (_) =>
          _AcademicTermDialog(loader: loader, selected: _termController.text),
    );
    if (selected == null || !mounted) return;
    if (widget.readCacheEpoch != epoch) {
      _showMessage('连接状态已变化，请重新选择学期。');
      return;
    }
    _updateQueryDraft(() {
      if (widget.feature == FeatureId.schedule &&
          _termController.text != selected)
        _weekController.clear();
      _termController.text = selected;
    });
  }
}

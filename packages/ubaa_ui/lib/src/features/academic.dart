part of '../widgets.dart';

extension _AcademicQueryControls on _FeatureQueryControlsState {
  List<Widget> _academicQueryFields(StateSetter setState) => <Widget>[
    if (widget.feature == FeatureId.schedule)
      DropdownButton<FeatureQueryView>(
        value: _scheduleView,
        onChanged: _submitting
            ? null
            : (value) => setState(
                () => _scheduleView = value ?? FeatureQueryView.summary,
              ),
        items: const <DropdownMenuItem<FeatureQueryView>>[
          DropdownMenuItem(
            value: FeatureQueryView.summary,
            child: Text('今日课程'),
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
    if (widget.feature == FeatureId.schedule ||
        widget.feature == FeatureId.exam ||
        widget.feature == FeatureId.grades) ...<Widget>[
      SizedBox(
        width: 180,
        child: TextField(
          controller: _termController,
          decoration: const InputDecoration(
            labelText: '学期编码（可选）',
            hintText: '留空使用当前学期',
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
            decoration: const InputDecoration(
              labelText: '周次（可选）',
              hintText: '如 1',
              isDense: true,
            ),
          ),
        ),
    ],
    if (widget.feature == FeatureId.classroom) ...<Widget>[
      SizedBox(
        width: 150,
        child: TextField(
          controller: _dateController,
          decoration: const InputDecoration(
            labelText: '日期',
            hintText: 'YYYY-MM-DD',
            isDense: true,
          ),
        ),
      ),
      SizedBox(
        width: 130,
        child: TextField(
          controller: _floorController,
          decoration: const InputDecoration(
            labelText: '楼层（可选）',
            hintText: '如 F2',
            isDense: true,
          ),
        ),
      ),
      SizedBox(
        width: 130,
        child: TextField(
          controller: _sectionController,
          decoration: const InputDecoration(
            labelText: '节次（可选）',
            hintText: '如 3',
            isDense: true,
          ),
        ),
      ),
      DropdownButton<int>(
        value: _campus,
        onChanged: _submitting
            ? null
            : (value) => setState(() => _campus = value ?? 1),
        items: const <DropdownMenuItem<int>>[
          DropdownMenuItem(value: 1, child: Text('校区 1')),
          DropdownMenuItem(value: 2, child: Text('校区 2')),
          DropdownMenuItem(value: 3, child: Text('校区 3')),
        ],
      ),
    ],
  ];
}

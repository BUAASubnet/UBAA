part of '../widgets.dart';

extension _ClassroomQueryControls on _FeatureQueryControlsState {
  List<Widget> _classroomQueryFields(StateSetter setState) => <Widget>[
    if (widget.feature == FeatureId.classroom) ...<Widget>[
      SizedBox(
        width: 220 * MediaQuery.textScalerOf(context).scale(14) / 14,
        child: TextField(
          controller: _dateController,
          decoration: InputDecoration(
            labelText: '日期',
            hintText: 'YYYY-MM-DD',
            isDense: true,
            suffixIcon: IconButton(
              tooltip: '选择日期',
              onPressed: _submitting ? null : _chooseDate,
              icon: const Icon(Icons.calendar_month_outlined),
            ),
          ),
        ),
      ),
      SizedBox(
        width: 190,
        child: TextField(
          controller: _floorController,
          decoration: InputDecoration(
            suffixIcon: IconButton(
              tooltip: '选择楼层',
              onPressed: _submitting
                  ? null
                  : () => _chooseClassroomOption(true),
              icon: const Icon(Icons.arrow_drop_down),
            ),
            labelText: '楼层',
            hintText: '可选，如 F2',
            isDense: true,
          ),
        ),
      ),
      SizedBox(
        width: 170,
        child: TextField(
          controller: _sectionController,
          decoration: InputDecoration(
            suffixIcon: IconButton(
              tooltip: '选择节次',
              onPressed: _submitting
                  ? null
                  : () => _chooseClassroomOption(false),
              icon: const Icon(Icons.arrow_drop_down),
            ),
            labelText: '节次',
            hintText: '可选，如 3',
            isDense: true,
          ),
        ),
      ),
      DropdownButton<int>(
        value: _campus,
        onChanged: _submitting
            ? null
            : (value) => setState(() {
                final next = value ?? 1;
                if (next != _campus) {
                  _campus = next;
                  _clearClassroomOptions();
                }
              }),
        items: const <DropdownMenuItem<int>>[
          DropdownMenuItem(value: 1, child: Text('校区 1')),
          DropdownMenuItem(value: 2, child: Text('校区 2')),
          DropdownMenuItem(value: 3, child: Text('校区 3')),
        ],
      ),
    ],
  ];

  Future<void> _chooseDate() async {
    final parsed = _parseDateOnly(_dateController.text);
    final initial = parsed != null && parsed.year >= 1 && parsed.year <= 9999
        ? parsed
        : DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
      helpText: '选择查询日期',
      cancelText: '取消',
      confirmText: '使用此日期',
      builder: (context, child) => Localizations.override(
        context: context,
        locale: const Locale('zh'),
        delegates: GlobalMaterialLocalizations.delegates,
        child: child!,
      ),
    );
    if (selected == null || !mounted) return;
    _updateQueryDraft(
      () => _dateController.text =
          '${selected.year.toString().padLeft(4, '0')}-${selected.month.toString().padLeft(2, '0')}-${selected.day.toString().padLeft(2, '0')}',
    );
  }

  void _clearClassroomOptions() {
    _classroomFloors.clear();
    _classroomSections.clear();
    _classroomGeneration++;
  }

  void _classroomDateChanged() {
    final date = _dateController.text.trim();
    if (date == _classroomDraftDate) return;
    _classroomDraftDate = date;
    if (widget.feature == FeatureId.classroom) {
      _updateQueryDraft(_clearClassroomOptions);
    }
  }

  // 同一个读取上下文只消费一次：日期来回切换或旧快照重绘不能复活选项。
  void _consumeClassroomOptions() {
    if (widget.feature != FeatureId.classroom) return;
    final snapshot = widget.snapshot;
    if (snapshot.status != FeatureLoadStatus.success) return;
    if (_classroomConsumed &&
        (snapshot.readContext != null
            ? identical(snapshot.readContext, _classroomLastContext)
            : identical(snapshot.details, _classroomLastDetails))) {
      return;
    }
    _classroomConsumed = true;
    _classroomLastContext = snapshot.readContext;
    _classroomLastDetails = snapshot.details;
    for (final detail in snapshot.details) {
      if (detail.presentation case final ClassroomPresentation room) {
        if (room.queryDate == null ||
            room.queryDate != _dateController.text.trim() ||
            room.campus != _campus) {
          continue;
        }
        if (room.floorId.trim().isNotEmpty) {
          _classroomFloors[room.floorId] = room.floorName.trim().isEmpty
              ? room.floorId
              : '${room.floorName} · ${room.floorId}';
        }
        for (final token in room.sectionTokens) {
          final section = int.tryParse(token);
          if (section != null && section > 0) _classroomSections.add(token);
        }
      }
    }
  }

  Future<void> _chooseClassroomOption(bool floor) async {
    final generation = _classroomGeneration;
    final options = floor
        ? Map<String, String>.of(_classroomFloors)
        : {for (final token in _classroomSections) token: '第 $token 节'};
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(floor ? '选择楼层' : '选择节次'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  options.isEmpty
                      ? '先查询该日期校区以获取选项，也可关闭后手填。'
                      : '来自该日期校区已查询的结果，可能仅含部分选项；也可手填。',
                ),
                for (final option in options.entries)
                  ListTile(
                    title: Text(option.value),
                    onTap: () => Navigator.of(context).pop(option.key),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
    if (!mounted || selected == null) return;
    if (generation != _classroomGeneration) {
      _showMessage('日期、校区或连接状态已变化，请重新查询后选择。');
      return;
    }
    _updateQueryDraft(
      () => (floor ? _floorController : _sectionController).text = selected,
    );
  }
}

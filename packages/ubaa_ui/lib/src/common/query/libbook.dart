part of 'query_controls.dart';

extension LibbookQueryControls on FeatureQueryControlsState {
  List<String> _libbookValues(String label) {
    final models = widget.details.map((d) => d.presentation).toList();
    final typed = models.any(
      (p) =>
          p is LibbookLibraryPresentation ||
          p is LibbookAreaPresentation ||
          p is LibbookAreaDetailPresentation ||
          p is LibbookAreaSchedulePresentation ||
          p is LibbookSeatPresentation ||
          p is LibbookBookingPresentation,
    );
    if (!typed) return _detailFieldValues(label);
    return {
      for (final p in models)
        if (label == '馆 ID' &&
            p is LibbookLibraryPresentation &&
            p.id.trim().isNotEmpty)
          p.id,
      for (final p in models)
        if (label == '分区 ID')
          ...switch (p) {
            LibbookAreaPresentation(:final id) when id.trim().isNotEmpty => [
              id,
            ],
            LibbookAreaDetailPresentation(:final id)
                when id.trim().isNotEmpty =>
              [id],
            LibbookAreaSchedulePresentation(:final id)
                when id.trim().isNotEmpty =>
              [id],
            LibbookSeatPresentation(:final areaId)
                when areaId.trim().isNotEmpty =>
              [areaId],
            _ => <String>[],
          },
    }.toList();
  }

  List<Widget> _libbookQueryFields(StateSetter setState) => <Widget>[
    if (widget.feature == FeatureId.libbook) ...<Widget>[
      DropdownButton<FeatureQueryView>(
        value: _libbookView,
        onChanged: _submitting
            ? null
            : (value) => setState(
                () => _libbookView = value ?? FeatureQueryView.summary,
              ),
        items: const <DropdownMenuItem<FeatureQueryView>>[
          DropdownMenuItem(value: FeatureQueryView.summary, child: Text('馆列表')),
          DropdownMenuItem(
            value: FeatureQueryView.libbookAreas,
            child: Text('馆区列表'),
          ),
          DropdownMenuItem(
            value: FeatureQueryView.libbookAreaDetail,
            child: Text('分区详情'),
          ),
          DropdownMenuItem(
            value: FeatureQueryView.libbookSeats,
            child: Text('座位查询'),
          ),
          DropdownMenuItem(
            value: FeatureQueryView.libbookBookings,
            child: Text('预约记录'),
          ),
        ],
      ),
      if (_libbookView != FeatureQueryView.libbookBookings)
        SizedBox(
          width: 220,
          child: TextField(
            controller: _dateController,
            onChanged: (_) => setState(() => _libraryDateError = false),
            decoration: InputDecoration(
              labelText: '日期',
              hintText: 'YYYY-MM-DD',
              helperText: _libraryNeedsExplicitDate ? '请明确选择日期' : null,
              errorText: _libraryDateError ? '请先明确选择预约日期。' : null,
              isDense: true,
            ),
          ),
        ),
      if (_libbookView == FeatureQueryView.libbookAreas) ...<Widget>[
        SizedBox(
          width: 200,
          child: TextField(
            controller: _premisesController,
            decoration: const InputDecoration(
              labelText: '馆区 ID',
              hintText: '从馆列表选择',
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          width: 200,
          child: TextField(
            controller: _storeyController,
            decoration: const InputDecoration(
              labelText: '楼层 ID（可选）',
              isDense: true,
            ),
          ),
        ),
        _valuePicker(
          label: '从当前馆列表选择',
          values: _libbookValues('馆 ID'),
          onSelected: (value) {
            _premisesController.text = value;
            _storeyController.clear();
            _areaController.clear();
            _segmentController.clear();
          },
        ),
      ],
      if (_libbookView == FeatureQueryView.libbookAreaDetail) ...<Widget>[
        SizedBox(
          width: 200,
          child: TextField(
            controller: _areaController,
            decoration: const InputDecoration(
              labelText: '分区 ID',
              hintText: '从馆区列表选择',
              isDense: true,
            ),
          ),
        ),
        _valuePicker(
          label: '从当前馆区选择',
          values: _libbookValues('分区 ID'),
          onSelected: (value) => _areaController.text = value,
        ),
      ],
      if (_libbookView == FeatureQueryView.libbookSeats) ...<Widget>[
        SizedBox(
          width: 200,
          child: TextField(
            controller: _areaController,
            decoration: const InputDecoration(
              labelText: '分区 ID',
              hintText: '从馆区列表选择',
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          width: 140,
          child: TextField(
            controller: _startController,
            decoration: const InputDecoration(
              labelText: '开始时间',
              hintText: '08:00',
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          width: 140,
          child: TextField(
            controller: _endController,
            decoration: const InputDecoration(
              labelText: '结束时间',
              hintText: '22:00',
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          width: 220,
          child: TextField(
            controller: _segmentController,
            decoration: const InputDecoration(
              labelText: '时段编号（必填）',
              isDense: true,
            ),
          ),
        ),
        _valuePicker(
          label: '从当前馆区选择',
          values: _libbookValues('分区 ID'),
          onSelected: (value) => _areaController.text = value,
        ),
      ],
      if (_libbookView == FeatureQueryView.libbookBookings) ...<Widget>[
        SizedBox(
          width: 140,
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
          width: 140,
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
    ],
  ];
}

part of '../widgets.dart';

extension _LibbookQueryControls on _FeatureQueryControlsState {
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
      if (_libbookView == FeatureQueryView.libbookAreas) ...<Widget>[
        SizedBox(
          width: 150,
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
          width: 130,
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
          values: _detailFieldValues('馆 ID'),
          onSelected: (value) => _premisesController.text = value,
        ),
      ],
      if (_libbookView == FeatureQueryView.libbookAreaDetail) ...<Widget>[
        SizedBox(
          width: 150,
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
          values: _detailFieldValues('分区 ID'),
          onSelected: (value) => _areaController.text = value,
        ),
      ],
      if (_libbookView == FeatureQueryView.libbookSeats) ...<Widget>[
        SizedBox(
          width: 150,
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
            controller: _dateController,
            decoration: const InputDecoration(
              labelText: '日期',
              hintText: 'YYYY-MM-DD',
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          width: 110,
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
          width: 110,
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
          width: 120,
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
          values: _detailFieldValues('分区 ID'),
          onSelected: (value) => _areaController.text = value,
        ),
      ],
      if (_libbookView == FeatureQueryView.libbookBookings) ...<Widget>[
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
    ],
  ];
}

extension _LibbookDetailActions on _FeatureDetailListState {
  List<Widget> _libbookCancelWriteFields(
    BuildContext context,
    LibbookCancelAction? libbookCancelAction,
    bool canLibbookCancel,
  ) => <Widget>[
    if (libbookCancelAction != null &&
        widget.onLibbookCancelWrite != null) ...<Widget>[
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: canLibbookCancel
            ? () => widget.onLibbookCancelWrite!(libbookCancelAction)
            : null,
        icon: const Icon(Icons.event_busy),
        label: const Text('准备取消预约'),
      ),
      if (!canLibbookCancel)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            libbookCancelAction.eligibility == ActionEligibility.denied
                ? '该预约当前不可取消。'
                : '当前取消资格无法确认，请刷新后重试。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    ],
  ];

  List<Widget> _libbookReserveWriteFields(
    BuildContext context,
    LibbookReserveAction? libbookReserveAction,
    bool canLibbookReserve,
  ) => <Widget>[
    if (libbookReserveAction != null &&
        widget.onLibbookReserveWrite != null) ...<Widget>[
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: canLibbookReserve
            ? () => widget.onLibbookReserveWrite!(libbookReserveAction)
            : null,
        icon: const Icon(Icons.event_available),
        label: const Text('准备预约此座位'),
      ),
      if (!canLibbookReserve)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            libbookReserveAction.eligibility == ActionEligibility.denied
                ? '该座位当前不可预约。'
                : '当前预约资格无法确认，请刷新后重试。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    ],
  ];
}

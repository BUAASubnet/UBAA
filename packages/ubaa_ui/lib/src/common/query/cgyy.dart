part of 'query_controls.dart';

extension CgyyQueryControls on FeatureQueryControlsState {
  List<Widget> _cgyyQueryFields(StateSetter setState) => <Widget>[
    if (widget.feature == FeatureId.cgyy) ...<Widget>[
      DropdownButton<FeatureQueryView>(
        value: _cgyyView,
        onChanged: _submitting
            ? null
            : (value) =>
                  setState(() => _cgyyView = value ?? FeatureQueryView.summary),
        items: const <DropdownMenuItem<FeatureQueryView>>[
          DropdownMenuItem(
            value: FeatureQueryView.summary,
            child: Text('站点列表'),
          ),
          DropdownMenuItem(
            value: FeatureQueryView.cgyyPurposeTypes,
            child: Text('用途类型'),
          ),
          DropdownMenuItem(
            value: FeatureQueryView.cgyyDayInfo,
            child: Text('日期空间'),
          ),
          DropdownMenuItem(
            value: FeatureQueryView.cgyyOrders,
            child: Text('订单列表'),
          ),
          DropdownMenuItem(
            value: FeatureQueryView.cgyyOrderDetail,
            child: Text('订单详情'),
          ),
          DropdownMenuItem(
            value: FeatureQueryView.cgyyLockCode,
            child: Text('查看密码'),
          ),
        ],
      ),
      if (_cgyyView == FeatureQueryView.cgyyDayInfo) ...<Widget>[
        SizedBox(
          width: 110,
          child: TextField(
            controller: _siteController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '站点 ID',
              hintText: '从站点列表选择',
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
        _valuePicker(
          label: '从当前站点选择',
          values: _cgyyValues('站点 ID'),
          onSelected: (value) => _siteController.text = value,
        ),
      ],
      if (_cgyyView == FeatureQueryView.cgyyOrders) ...<Widget>[
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
      if (_cgyyView == FeatureQueryView.cgyyOrderDetail) ...<Widget>[
        SizedBox(
          width: 110,
          child: TextField(
            controller: _orderController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '订单 ID',
              hintText: '从订单列表选择',
              isDense: true,
            ),
          ),
        ),
        _valuePicker(
          label: '从当前订单选择',
          values: _cgyyValues('订单编号'),
          onSelected: (value) => _orderController.text = value,
        ),
      ],
    ],
  ];

  List<String> _cgyyValues(String label) {
    final typed = widget.snapshot.details
        .map((d) => d.presentation)
        .whereType<FeaturePresentation>()
        .toList();
    if (typed.isEmpty) return _detailFieldValues(label);
    return <String>{
      for (final p in typed)
        if (label == '站点 ID' && p is CgyySitePresentation && p.id > 0)
          '${p.id}'
        else if (label == '站点 ID' &&
            p is CgyyDayPresentation &&
            p.venueSiteId > 0)
          '${p.venueSiteId}'
        else if (label == '订单编号' && p is CgyyOrderPresentation && p.id > 0)
          '${p.id}',
    }.toList();
  }
}

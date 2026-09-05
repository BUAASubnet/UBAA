part of '../widgets.dart';

extension _YgdkQueryControls on _FeatureQueryControlsState {
  List<Widget> _ygdkQueryFields(StateSetter setState) => <Widget>[
    if (widget.feature == FeatureId.ygdk) ...<Widget>[
      DropdownButton<FeatureQueryView>(
        value: _ygdkView,
        onChanged: _submitting
            ? null
            : (value) =>
                  setState(() => _ygdkView = value ?? FeatureQueryView.summary),
        items: const <DropdownMenuItem<FeatureQueryView>>[
          DropdownMenuItem(value: FeatureQueryView.summary, child: Text('概览')),
          DropdownMenuItem(
            value: FeatureQueryView.ygdkRecords,
            child: Text('记录列表'),
          ),
        ],
      ),
      if (_ygdkView == FeatureQueryView.ygdkRecords) ...<Widget>[
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

extension _YgdkDetailActions on _FeatureDetailListState {
  List<Widget> _ygdkWriteFields(
    BuildContext context,
    YgdkSubmitAction? ygdkAction,
    FeatureDetail detail,
  ) => <Widget>[
    if (ygdkAction != null && widget.onYgdkSubmitWrite != null) ...<Widget>[
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () =>
            _showYgdkForm(context, action: ygdkAction, title: detail.title),
        icon: const Icon(Icons.directions_run),
        label: const Text('准备阳光打卡'),
      ),
    ],
  ];

  YgdkSubmitAction? _ygdkAction(FeatureDetail detail) {
    if (widget.feature != FeatureId.ygdk) return null;
    final action = detail.action<YgdkSubmitAction>();
    return action?.hasCanonicalTarget == true ? action : null;
  }
}

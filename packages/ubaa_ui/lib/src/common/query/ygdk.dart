part of 'query_controls.dart';

extension YgdkQueryControls on FeatureQueryControlsState {
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
    ],
  ];
}

part of 'query_controls.dart';

extension SigninQueryControls on FeatureQueryControlsState {
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

part of 'query_controls.dart';

extension EvaluationQueryControls on FeatureQueryControlsState {
  List<Widget> _evaluationQueryFields(StateSetter setState) => <Widget>[
    if (widget.feature == FeatureId.evaluation)
      DropdownButton<FeatureQueryView>(
        value: _evaluationView,
        onChanged: _submitting
            ? null
            : (value) => setState(
                () => _evaluationView = value ?? FeatureQueryView.summary,
              ),
        items: const <DropdownMenuItem<FeatureQueryView>>[
          DropdownMenuItem(
            value: FeatureQueryView.summary,
            child: Text('全部课程'),
          ),
          DropdownMenuItem(
            value: FeatureQueryView.evaluationPending,
            child: Text('待评课程'),
          ),
        ],
      ),
  ];
}

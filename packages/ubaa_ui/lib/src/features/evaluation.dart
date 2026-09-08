part of '../widgets.dart';

extension _EvaluationQueryControls on _FeatureQueryControlsState {
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

extension _EvaluationDetailActions on _FeatureDetailListState {
  List<Widget> _evaluationSelectionFields(
    StateSetter setState,
    EvaluationSubmitTarget? evaluation,
  ) => <Widget>[
    if (evaluation != null && widget.onEvaluationWrite != null) ...<Widget>[
      const SizedBox(height: 8),
      CheckboxListTile(
        key: ValueKey<String>('evaluation-${evaluation.selectionKey}'),
        value: _selectedEvaluationKeys.contains(evaluation.selectionKey),
        onChanged: (selected) => setState(() {
          if (selected == true) {
            _selectedEvaluationKeys.add(evaluation.selectionKey);
          } else {
            _selectedEvaluationKeys.remove(evaluation.selectionKey);
          }
        }),
        contentPadding: EdgeInsets.zero,
        title: const Text('选择此课程进行批量评教'),
      ),
    ],
  ];

  List<Widget> _evaluationSubmitFields(EvaluationSubmitTarget? evaluation) =>
      <Widget>[
        if (evaluation != null && widget.onEvaluationWrite != null) ...<Widget>[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () =>
                widget.onEvaluationWrite!(<EvaluationSubmitTarget>[evaluation]),
            icon: const Icon(Icons.rate_review_outlined),
            label: const Text('准备提交评教'),
          ),
        ],
      ];

  List<Widget> _evaluationBatchFields(
    StateSetter setState,
    List<EvaluationSubmitTarget> pendingEvaluations,
    List<EvaluationSubmitTarget> selectedEvaluations,
  ) => <Widget>[
    if (widget.feature == FeatureId.evaluation &&
        selectedEvaluations.isNotEmpty &&
        widget.onEvaluationWrite != null)
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text('已选择 ${selectedEvaluations.length} 门待评课程'),
            OutlinedButton(
              onPressed: pendingEvaluations.isEmpty
                  ? null
                  : () => setState(() {
                      if (selectedEvaluations.length ==
                          pendingEvaluations.length) {
                        _selectedEvaluationKeys.clear();
                      } else {
                        _selectedEvaluationKeys
                          ..clear()
                          ..addAll(
                            pendingEvaluations.map(
                              (target) => target.selectionKey,
                            ),
                          );
                      }
                    }),
              child: Text(
                selectedEvaluations.length == pendingEvaluations.length
                    ? '取消全选'
                    : '全选待评',
              ),
            ),
            FilledButton.icon(
              onPressed: selectedEvaluations.isEmpty
                  ? null
                  : () => widget.onEvaluationWrite!(selectedEvaluations),
              icon: const Icon(Icons.rate_review_outlined),
              label: const Text('准备批量评教'),
            ),
          ],
        ),
      ),
  ];

  EvaluationSubmitTarget? _evaluationSubmitTarget(FeatureDetail detail) {
    if (widget.feature != FeatureId.evaluation) return null;
    final action = detail.action<EvaluationSubmitAction>();
    return action?.hasCanonicalTarget == true ? action!.target : null;
  }
}

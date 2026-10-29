part of 'detail_list.dart';

extension EvaluationDetailActions on _FeatureDetailListState {
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
            onPressed: !widget.writesEnabled
                ? null
                : () => widget.onEvaluationWrite!(<EvaluationSubmitTarget>[
                    evaluation,
                  ]),
            icon: const Icon(Icons.rate_review_outlined),
            label: const Text('提交评教'),
          ),
        ],
      ];

  /// 评教底部操作栏：常驻于列表下方，不随选择数量改变列表位置。
  List<Widget> _evaluationBatchFields(
    StateSetter setState,
    List<EvaluationSubmitTarget> pendingEvaluations,
    List<EvaluationSubmitTarget> selectedEvaluations,
  ) => <Widget>[
    if (widget.feature == FeatureId.evaluation &&
        pendingEvaluations.isNotEmpty &&
        widget.onEvaluationWrite != null)
      Material(
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: Padding(
          padding: UbaaTheme.pageInsets(context, top: 8, bottom: 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  selectedEvaluations.isEmpty
                      ? '待评 ${pendingEvaluations.length} 门'
                      : '已选 ${selectedEvaluations.length} 门',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              TextButton(
                onPressed: !widget.writesEnabled
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
                      : '全选',
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: !widget.writesEnabled || selectedEvaluations.isEmpty
                    ? null
                    : () => widget.onEvaluationWrite!(selectedEvaluations),
                child: Text(
                  selectedEvaluations.length <= 1
                      ? '提交评教'
                      : '提交 ${selectedEvaluations.length} 门',
                ),
              ),
            ],
          ),
        ),
      ),
  ];

  EvaluationSubmitTarget? _evaluationSubmitTarget(FeatureDetail detail) {
    if (widget.feature != FeatureId.evaluation) return null;
    final action = detail.action<EvaluationSubmitAction>();
    return action?.hasCanonicalTarget == true ? action!.target : null;
  }
}

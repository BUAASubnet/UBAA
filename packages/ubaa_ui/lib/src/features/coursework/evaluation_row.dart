part of '../../widgets.dart';

extension _EvaluationCourseRows on _FeatureDetailListState {
  Widget _evaluationCourseRow(FeatureDetail detail, StateSetter update) {
    final presentation = detail.presentation! as EvaluationCoursePresentation;
    final target = _evaluationSubmitTarget(detail);
    final selected =
        target != null && _selectedEvaluationKeys.contains(target.selectionKey);
    final theme = Theme.of(context);
    final title = Text(detail.title, style: theme.textTheme.titleMedium);
    final reason = target == null && !presentation.isEvaluated
        ? detail.action<EvaluationSubmitAction>()?.eligibility ==
                  ActionEligibility.denied
              ? '当前课程不允许提交评教。'
              : '当前评教资格无法确认，请刷新后重试。'
        : null;
    final subtitle = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_nonBlank(detail.subtitle) ?? '教师未提供'),
        if (reason != null) Text(reason),
      ],
    );
    final info = IconButton(
      tooltip: '课程详情',
      icon: const Icon(Icons.info_outline),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(detail.title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_nonBlank(detail.subtitle) ?? '教师未提供'),
                Text(presentation.isEvaluated ? '已评' : '待评'),
                if (reason != null) Text(reason),
                for (final field in detail.fields)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('${field.label}：${field.value}'),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHigh,
      child: target != null && widget.onEvaluationWrite != null
          ? CheckboxListTile(
              key: ValueKey<String>('evaluation-${target.selectionKey}'),
              value: selected,
              onChanged: (value) => update(() {
                if (value == true) {
                  _selectedEvaluationKeys.add(target.selectionKey);
                } else {
                  _selectedEvaluationKeys.remove(target.selectionKey);
                }
              }),
              controlAffinity: ListTileControlAffinity.leading,
              title: title,
              subtitle: subtitle,
              secondary: info,
            )
          : ListTile(
              leading: Icon(
                presentation.isEvaluated
                    ? Icons.check_circle_outline
                    : Icons.help_outline,
              ),
              title: title,
              subtitle: subtitle,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [Text(presentation.isEvaluated ? '已评' : '待评'), info],
              ),
            ),
    );
  }
}

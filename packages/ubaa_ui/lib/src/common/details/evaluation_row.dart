part of 'detail_list.dart';

extension EvaluationCourseRows on _FeatureDetailListState {
  Widget _evaluationCourseRow(FeatureDetail detail, StateSetter update) {
    final presentation = detail.presentation! as EvaluationCoursePresentation;
    final target = _evaluationSubmitTarget(detail);
    final selected =
        target != null && _selectedEvaluationKeys.contains(target.selectionKey);
    final theme = Theme.of(context);
    final title = Text(detail.title, style: theme.textTheme.titleMedium);
    // 只标出确定不可评的课程；资格未确认时不打扰用户。
    final reason =
        target == null &&
            !presentation.isEvaluated &&
            detail.action<EvaluationSubmitAction>()?.eligibility ==
                ActionEligibility.denied
        ? '当前课程不允许提交评教。'
        : null;
    // 资格说明只留短标签，完整原因在详情里查看。
    final subtitle = Row(
      children: [
        Flexible(child: Text(uiNonBlank(detail.subtitle) ?? '教师未提供')),
        if (reason != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '不可评',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
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
                Text(uiNonBlank(detail.subtitle) ?? '教师未提供'),
                Text(presentation.isEvaluated ? '已评' : '待评'),
                if (reason != null) Text(reason),
                for (final field in detail.fields.where(
                  (f) => !uiHiddenAcademicField(f.label),
                ))
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

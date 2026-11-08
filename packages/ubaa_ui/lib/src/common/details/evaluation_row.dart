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
          const UiTag('不可评', tone: UiTagTone.error),
        ],
      ],
    );
    final info = IconButton(
      tooltip: '课程详情',
      icon: const Icon(Icons.info_outline),
      onPressed: () => showUiSheet<void>(
        context,
        builder: (sheetContext) => UiSheetBody(
          title: detail.title,
          subtitle: [
            uiNonBlank(detail.subtitle) ?? '教师未提供',
            presentation.isEvaluated ? '已评' : '待评',
          ].join(' · '),
          children: [
            if (reason != null)
              UiInfoRow(
                icon: Icons.block_outlined,
                text: reason,
                color: theme.colorScheme.error,
              ),
            for (final field in detail.fields)
              if (!uiHiddenAcademicField(field.label) &&
                  field.value.trim().isNotEmpty)
                UiInfoRow(
                  icon: Icons.info_outline,
                  text: field.value,
                  label: field.label,
                ),
          ],
        ),
      ),
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: selected ? theme.colorScheme.primaryContainer : null,
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

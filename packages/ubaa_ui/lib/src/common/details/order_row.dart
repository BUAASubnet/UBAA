part of 'detail_list.dart';

extension CgyyOrderRows on _FeatureDetailListState {
  Widget _cgyyOrderRow(
    BuildContext context,
    FeatureDetail detail,
    CgyyOrderPresentation order,
    CgyyCancelAction? action,
  ) {
    final theme = Theme.of(context);
    final place = [
      order.venueName,
      order.venueSpaceName ?? order.siteName,
    ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' / ');
    final isDetail = widget.query?.view == FeatureQueryView.cgyyOrderDetail;
    final navigation = detail.readNavigation;
    final title = Text(
      place.isEmpty ? '研讨室预约' : place,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
    final status = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        order.statusText,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
    final information = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          order.reservationDateDetail ??
              [
                order.reservationDate,
                order.reservationStartDate,
                order.reservationEndDate,
              ].whereType<String>().where((s) => s.isNotEmpty).join(' '),
          style: theme.textTheme.bodyMedium,
        ),
        if (order.theme?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('主题：${order.theme}'),
          ),
        if (order.purposeTypeName?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '活动类型：${order.purposeTypeName}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
    final buttons = [
      if (!isDetail && navigation != null && widget.onNavigate != null)
        TextButton(
          onPressed: () => widget.onNavigate!(navigation),
          child: const Text('查看详情'),
        ),
      if (action != null && widget.onCgyyCancelWrite != null)
        _cgyyCancelButton(action),
    ];
    final actions = Wrap(
      alignment: WrapAlignment.end,
      spacing: 4,
      runSpacing: 4,
      children: buttons,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontal =
                constraints.maxWidth >=
                560 * MediaQuery.textScalerOf(context).scale(14) / 14;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (horizontal)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [title, information],
                        ),
                      ),
                      const SizedBox(width: 24),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 240),
                            child: status,
                          ),
                          if (buttons.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            actions,
                          ],
                        ],
                      ),
                    ],
                  )
                else ...[
                  title,
                  const SizedBox(height: 8),
                  status,
                  information,
                  if (buttons.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: actions),
                  ],
                ],
                if (isDetail) ...[
                  const SizedBox(height: 12),
                  for (final field in detail.fields)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: DetailField(
                        label: field.label,
                        value: field.value,
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

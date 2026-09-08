part of '../../widgets.dart';

extension _CgyyOrderRows on _FeatureDetailListState {
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    place.isEmpty ? '研讨室预约' : place,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(
                    order.statusText,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              order.reservationDateDetail ??
                  [
                    order.reservationDate,
                    order.reservationStartDate,
                    order.reservationEndDate,
                  ].whereType<String>().where((s) => s.isNotEmpty).join(' '),
            ),
            if (order.theme?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('主题：${order.theme}'),
              ),
            if (order.purposeTypeName?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '活动类型：${order.purposeTypeName}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (isDetail) ...[
              const SizedBox(height: 12),
              for (final field in detail.fields)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _DetailField(label: field.label, value: field.value),
                ),
            ],
            Wrap(
              spacing: 8,
              children: [
                if (!isDetail &&
                    navigation != null &&
                    widget.onNavigate != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: OutlinedButton(
                      onPressed: () => widget.onNavigate!(navigation),
                      child: const Text('查看详情'),
                    ),
                  ),
                if (action != null && widget.onCgyyCancelWrite != null)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _cgyyCancelWriteFields(action),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

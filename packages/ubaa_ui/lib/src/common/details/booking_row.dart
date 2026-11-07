part of 'detail_list.dart';

extension LibbookBookingRows on _FeatureDetailListState {
  Widget _libbookBookingRow(
    BuildContext context,
    FeatureDetail detail,
    LibbookBookingPresentation booking,
    LibbookCancelAction? action,
    bool canCancel,
  ) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(booking.name, style: theme.textTheme.titleMedium),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    booking.statusName.isEmpty ? '状态未说明' : booking.statusName,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  tooltip: '预约详情',
                  icon: const Icon(Icons.info_outline, size: 20),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => showUiSheet<void>(
                    context,
                    builder: (context) => UiSheetBody(
                      title: booking.name,
                      subtitle: booking.statusName.isEmpty
                          ? null
                          : booking.statusName,
                      children: [
                        UiInfoRow(
                          icon: Icons.confirmation_number_outlined,
                          text: booking.id,
                          detail: '预约编号',
                        ),
                        for (final field in detail.fields)
                          if (field.value.trim().isNotEmpty)
                            UiInfoRow(
                              icon: Icons.info_outline,
                              text: field.value,
                              detail: field.label,
                            ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Text(
              '${uiShortDateTime(booking.day)} ${booking.beginTime}–${booking.endTime}',
            ),
            const SizedBox(height: 4),
            Text(
              '${booking.areaName} · 座位 ${booking.seatNumber}',
              style: theme.textTheme.bodySmall,
            ),
            ..._libbookCancelWriteFields(context, action, canCancel),
          ],
        ),
      ),
    );
  }
}

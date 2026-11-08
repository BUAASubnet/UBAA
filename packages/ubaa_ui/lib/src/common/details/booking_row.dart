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
    final colors = theme.colorScheme;
    // 上游开始/结束可能带完整日期，统一成「5月8日 14:59–23:00」；只有时刻时补上日期。
    final range =
        uiShortRange(
          booking.beginTime.contains('-') || booking.day.trim().isEmpty
              ? booking.beginTime
              : '${booking.day} ${booking.beginTime}',
          booking.endTime.contains('-') || booking.day.trim().isEmpty
              ? booking.endTime
              : '${booking.day} ${booking.endTime}',
        ) ??
        '${booking.beginTime}–${booking.endTime}';
    final seat = '座位 ${booking.seatNumber}';
    final place =
        booking.areaName.trim().isEmpty ||
            booking.areaName.trim() == booking.seatNumber.trim()
        ? seat
        : '${booking.areaName} · $seat';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    booking.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                UiTag(
                  booking.statusName.isEmpty ? '状态未说明' : booking.statusName,
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
                          label: '预约编号',
                        ),
                        for (final field in detail.fields)
                          if (field.value.trim().isNotEmpty)
                            UiInfoRow(
                              icon: Icons.info_outline,
                              text: field.value,
                              label: field.label,
                            ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(range, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(
                    place,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            ..._libbookCancelWriteFields(context, action, canCancel),
          ],
        ),
      ),
    );
  }
}

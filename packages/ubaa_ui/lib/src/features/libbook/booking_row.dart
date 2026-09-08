part of '../../widgets.dart';

extension _LibbookBookingRows on _FeatureDetailListState {
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
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(booking.name),
                      content: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('预约编号：${booking.id}'),
                            Text('状态码：${booking.status?.toString() ?? '未提供'}'),
                            for (final field in detail.fields)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: _DetailField(
                                  label: field.label,
                                  value: field.value,
                                ),
                              ),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('关闭'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Text('${booking.day} ${booking.beginTime}–${booking.endTime}'),
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

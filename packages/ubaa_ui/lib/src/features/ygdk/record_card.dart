part of '../../widgets.dart';

List<String> _ygdkRecordSearchValues(YgdkRecordPresentation p) => [
  '记录编号',
  '${p.recordId}',
  '图片数量',
  '${p.imageCount}',
  '开始时间',
  '结束时间',
  '地点',
  '公开状态',
  p.isOpen ? '公开 已分享' : '不公开 未分享',
  ...[
    p.itemId?.toString(),
    p.itemName,
    p.startTime,
    p.endTime,
    p.place,
    p.state?.toString(),
    p.createdAt,
    p.createdAtLabel,
  ].whereType<String>(),
];

String _ygdkRecordTime(YgdkRecordPresentation record) {
  final start = record.startTime?.trim();
  final end = record.endTime?.trim();
  if (start == null || start.isEmpty) return end ?? '时间待定';
  if (end == null || end.isEmpty) return start;
  final sameDay =
      start.length >= 11 &&
      end.length >= 11 &&
      start.substring(0, 10) == end.substring(0, 10);
  return '$start–${sameDay ? end.substring(11) : end}';
}

class _YgdkRecordCard extends StatelessWidget {
  const _YgdkRecordCard(this.record);
  final YgdkRecordPresentation record;
  @override
  Widget build(BuildContext context) {
    final p = record;
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('记录详情'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BykcInfoLine('项目', p.itemName),
                  _BykcInfoLine('记录编号', '${p.recordId}'),
                  _BykcInfoLine('项目编号', p.itemId?.toString()),
                  _BykcInfoLine('开始时间', p.startTime),
                  _BykcInfoLine('结束时间', p.endTime),
                  _BykcInfoLine('地点', p.place),
                  _BykcInfoLine('图片数量', '${p.imageCount}'),
                  _BykcInfoLine('分享状态', p.isOpen ? '已分享' : '未分享'),
                  _BykcInfoLine('记录状态编号', p.state?.toString() ?? '未提供'),
                  _BykcInfoLine('提交时间', p.createdAtLabel ?? p.createdAt),
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
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.directions_run),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p.itemName ?? '运动打卡',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              if (p.place?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.place_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        p.place!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Text(_ygdkRecordTime(p), style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text(
                '${p.createdAtLabel ?? p.createdAt ?? '提交时间未知'}'
                '${p.imageCount > 0 ? ' · ${p.imageCount} 张图片' : ''}'
                ' · ${p.isOpen ? '已分享' : '未分享'}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

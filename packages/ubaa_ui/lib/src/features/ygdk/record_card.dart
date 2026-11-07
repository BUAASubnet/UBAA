import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../shared/dialogs/sheet.dart';
import '../../shared/text.dart' show uiNonBlank;
import '../../shared/when.dart' show uiShortRange;

List<String> uiYgdkRecordSearchValues(YgdkRecordPresentation p) => [
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

/// 列表统一为“9月9日 23:30–00:30”，跨天时两端都带日期。
String _ygdkRecordTime(YgdkRecordPresentation record) =>
    uiShortRange(uiNonBlank(record.startTime), uiNonBlank(record.endTime)) ??
    '时间待定';

class YgdkRecordCard extends StatelessWidget {
  const YgdkRecordCard(this.record);
  final YgdkRecordPresentation record;
  @override
  Widget build(BuildContext context) {
    final p = record;
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showUiSheet<void>(
          context,
          builder: (context) => UiSheetBody(
            title: uiNonBlank(p.itemName) ?? '运动打卡',
            subtitle: switch (uiNonBlank(p.createdAtLabel ?? p.createdAt)) {
              final submitted? => '提交于 $submitted',
              null => null,
            },
            children: [
              UiInfoRow(
                icon: Icons.schedule_outlined,
                text: _ygdkRecordTime(p),
              ),
              if (uiNonBlank(p.place) case final place?)
                UiInfoRow(icon: Icons.place_outlined, text: place),
              UiInfoRow(
                icon: Icons.image_outlined,
                text: '${p.imageCount} 张图片',
              ),
              UiInfoRow(
                icon: p.isOpen ? Icons.public : Icons.lock_outline,
                text: p.isOpen ? '已分享' : '未分享',
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

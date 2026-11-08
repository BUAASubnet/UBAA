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
        // 紧凑三行：项目名、时间与地点、提交信息；左侧一个图标块对齐整卡。
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.directions_run,
                  size: 22,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.itemName ?? '运动打卡',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [_ygdkRecordTime(p), ?uiNonBlank(p.place)].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        '提交于 ${p.createdAtLabel ?? p.createdAt ?? '时间未知'}',
                        if (p.imageCount > 0) '${p.imageCount} 张图片',
                        p.isOpen ? '已分享' : '未分享',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

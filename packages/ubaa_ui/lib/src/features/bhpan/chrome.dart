import 'package:clock/clock.dart' show clock;
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import '../../shared/file_list/file_tile.dart';
import 'format.dart';

/// 列表用的短时间：今天 21:57、昨天 21:57、今年 3月13日、往年 2025年12月8日。
String bhpanShortDate(DateTime time, {DateTime? now}) {
  final d = time.toUtc().add(const Duration(hours: 8));
  final n = (now ?? clock.now()).toUtc().add(const Duration(hours: 8));
  final day = DateTime.utc(d.year, d.month, d.day),
      today = DateTime.utc(n.year, n.month, n.day);
  final hm =
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  final diff = today.difference(day).inDays;
  if (diff == 0) return '今天 $hm';
  if (diff == 1) return '昨天 $hm';
  if (d.year == n.year) return '${d.month}月${d.day}日';
  return '${d.year}年${d.month}月${d.day}日';
}

/// 列表行副标题：文件显示大小，有时间时追加短时间。
String bhpanItemMeta(BhpanItem item, {String datePrefix = ''}) => [
  if (!item.isFolder) bhpanBytes(item.bytes ?? 0),
  if (item.modifiedAt != null) '$datePrefix${bhpanShortDate(item.modifiedAt!)}',
].join(' · ');

/// 将北航云盘条目映射为通用文件行，业务操作仍由云盘页面决定。
class BhpanItemTile extends StatelessWidget {
  const BhpanItemTile({
    super.key,
    required this.item,
    required this.selecting,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
    this.meta,
  });
  final BhpanItem item;
  final bool selecting, selected, enabled;
  final VoidCallback onTap, onLongPress, onMore;
  final String? meta;

  @override
  Widget build(BuildContext context) => UiFileTile(
    name: item.name,
    leading: UiFileTypeIcon(name: item.name, isFolder: item.isFolder),
    meta: meta ?? bhpanItemMeta(item),
    selecting: selecting,
    selected: selected,
    enabled: enabled,
    onTap: onTap,
    onLongPress: onLongPress,
    onMore: onMore,
  );
}

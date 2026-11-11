import 'package:clock/clock.dart' show clock;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'format.dart';

/// 文件类型图标与配色，仅按扩展名推断展示，不参与任何协议判断。
(IconData, Color) bhpanTypeVisual(BhpanItem item, ColorScheme colors) {
  if (item.isFolder) return (Icons.folder_rounded, const Color(0xFFF2B53A));
  final name = item.name.toLowerCase();
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1);
  return switch (ext) {
    'pdf' => (Icons.picture_as_pdf_rounded, const Color(0xFFE5483B)),
    'doc' ||
    'docx' ||
    'rtf' ||
    'odt' => (Icons.description_rounded, const Color(0xFF2B6FD6)),
    'ppt' ||
    'pptx' ||
    'key' => (Icons.slideshow_rounded, const Color(0xFFE5772E)),
    'xls' ||
    'xlsx' ||
    'csv' ||
    'numbers' => (Icons.table_chart_rounded, const Color(0xFF1E8E4E)),
    'zip' ||
    'rar' ||
    '7z' ||
    'tar' ||
    'gz' => (Icons.folder_zip_rounded, const Color(0xFF8D6E63)),
    'png' ||
    'jpg' ||
    'jpeg' ||
    'gif' ||
    'webp' ||
    'heic' ||
    'bmp' ||
    'svg' => (Icons.image_rounded, const Color(0xFF8E5CD9)),
    'mp4' ||
    'mov' ||
    'mkv' ||
    'avi' ||
    'webm' => (Icons.movie_rounded, const Color(0xFFD6336C)),
    'mp3' ||
    'wav' ||
    'flac' ||
    'm4a' ||
    'aac' => (Icons.audiotrack_rounded, const Color(0xFF0F9D9A)),
    'txt' || 'md' => (Icons.article_rounded, colors.onSurfaceVariant),
    'c' ||
    'cpp' ||
    'h' ||
    'java' ||
    'py' ||
    'rs' ||
    'dart' ||
    'js' ||
    'ts' ||
    'go' ||
    'html' ||
    'json' => (Icons.code_rounded, const Color(0xFF5B6FCB)),
    _ => (Icons.insert_drive_file_rounded, colors.outline),
  };
}

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

class BhpanTypeIcon extends StatelessWidget {
  const BhpanTypeIcon({super.key, required this.item, this.size = 40});
  final BhpanItem item;
  final double size;
  @override
  Widget build(BuildContext context) {
    final (icon, color) = bhpanTypeVisual(item, Theme.of(context).colorScheme);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(size / 4),
      ),
      child: Icon(icon, color: color, size: size * .6),
    );
  }
}

/// 文件行。桌面端：悬停显示勾选框进入多选，右键打开更多操作，⌘/Ctrl 加点击切换选中；
/// 触屏仍用长按进入多选。
class BhpanItemTile extends StatefulWidget {
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
  State<BhpanItemTile> createState() => _BhpanItemTileState();
}

class _BhpanItemTileState extends State<BhpanItemTile> {
  bool _hovering = false;

  bool get _desktop => switch (Theme.of(context).platform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => true,
    _ => false,
  };

  void _tap() {
    final keys = HardwareKeyboard.instance;
    // 桌面习惯：按住 ⌘/Ctrl 点击切换选中，不打开文件。
    if (_desktop && (keys.isMetaPressed || keys.isControlPressed)) {
      widget.onLongPress();
    } else {
      widget.onTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    final BhpanItemTile(
      :item,
      :selecting,
      :selected,
      :enabled,
      :onTap,
      :onLongPress,
      :onMore,
    ) = widget;
    final showCheck = selecting || (_desktop && _hovering && enabled);
    final check = Checkbox(
      value: selected,
      // 未进入多选时，勾选即进入多选并选中这一项。
      onChanged: enabled ? (_) => selecting ? onTap() : onLongPress() : null,
    );
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final meta = widget.meta ?? bhpanItemMeta(item);
    return Material(
      color: selected
          ? colors.secondaryContainer.withValues(alpha: .6)
          : Colors.transparent,
      child: InkWell(
        onTap: enabled ? _tap : null,
        onLongPress: enabled ? onLongPress : null,
        onSecondaryTap: enabled && !selecting ? onMore : null,
        onHover: _desktop ? (value) => setState(() => _hovering = value) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(
            children: [
              // 桌面端勾选框替换文件图标位置，悬停时内容不左右跳动；触屏多选时在图标前插入。
              if (_desktop)
                showCheck
                    ? SizedBox.square(
                        dimension: 40,
                        child: Center(child: check),
                      )
                    : BhpanTypeIcon(item: item)
              else ...[
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: showCheck
                      ? Padding(
                          key: const ValueKey('check'),
                          padding: const EdgeInsets.only(right: 4),
                          child: check,
                        )
                      : const SizedBox(key: ValueKey('none')),
                ),
                BhpanTypeIcon(item: item),
              ],
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (meta.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (!selecting)
                IconButton(
                  tooltip: '更多操作',
                  onPressed: enabled ? onMore : null,
                  icon: Icon(Icons.more_horiz, color: colors.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
